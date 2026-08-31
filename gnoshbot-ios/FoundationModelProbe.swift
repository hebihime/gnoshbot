import Foundation

/// Survives force-quit and reboot. If Siri hangs and you restart, an unfinished
/// `inFlight` row means the on-device model call had started and never returned.
public struct FoundationModelProbeSnapshot: Equatable, Sendable, Codable {
    public enum Outcome: String, Codable, Sendable {
        case inFlight
        case skippedUnavailable
        case skippedBusy
        case timeout
        case success
        case invalidId
        case error
        case abandonedInFlight
    }

    public var startedAt: Date
    public var finishedAt: Date?
    public var outcome: Outcome
    public var durationMs: Int?
    public var detail: String

    public var summaryLine: String {
        let start = startedAt.formatted(date: .omitted, time: .standard)
        switch outcome {
        case .inFlight:
            return "On-device model: IN FLIGHT since \(start). If Siri is dead, this is the suspect. Force-quit Gnoshbot, then restart the phone if needed."
        case .abandonedInFlight:
            return "On-device model: last call started \(start) and never finished (app died or hung). Treat as evidence the Foundation Model call wedged the system."
        case .timeout:
            return "On-device model: timed out after \(durationMs ?? 0) ms at \(start). Scorer pick kept."
        case .success:
            return "On-device model: ok in \(durationMs ?? 0) ms (\(detail))."
        case .invalidId:
            return "On-device model: replied with an illegal id (\(detail)). Scorer pick kept."
        case .skippedUnavailable:
            return "On-device model: skipped, Apple Intelligence unavailable (\(detail))."
        case .skippedBusy:
            return "On-device model: skipped, a prior call was still running."
        case .error:
            return "On-device model: error (\(detail))."
        }
    }
}

public enum AsyncTimeoutError: Error, Equatable {
    case timedOut
}

public enum AsyncTimeout {
    public static func firstCompleted<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AsyncTimeoutError.timedOut
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                throw AsyncTimeoutError.timedOut
            }
            return value
        }
    }
}

/// Single-flight so two launches cannot overlap LanguageModelSession.
public actor FoundationModelGate {
    public static let shared = FoundationModelGate()
    private var busy = false

    public func tryBegin() -> Bool {
        if busy { return false }
        busy = true
        return true
    }

    public func end() {
        busy = false
    }
}

public enum FoundationModelProbe {
    public static let defaultsKey = "gnoshbot.prototype.fm.probe"
    public static let siriTeardownNanoseconds: UInt64 = 2_000_000_000
    /// Bounds a hung `respond`. Siri already said "On it."; this is background only.
    public static let respondTimeoutSeconds: TimeInterval = 20

    public static func defaults() -> UserDefaults {
        UserDefaults(suiteName: GnoshbotPersistence.appGroupId) ?? .standard
    }

    public static func load(from defaults: UserDefaults? = nil) -> FoundationModelProbeSnapshot? {
        let store = defaults ?? Self.defaults()
        guard let data = store.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(FoundationModelProbeSnapshot.self, from: data)
    }

    public static func persist(_ snapshot: FoundationModelProbeSnapshot, to defaults: UserDefaults? = nil) {
        if let data = try? JSONEncoder().encode(snapshot) {
            let store = defaults ?? Self.defaults()
            store.set(data, forKey: defaultsKey)
            store.synchronize()
        }
    }

    public static func markStarted(detail: String = "", defaults: UserDefaults? = nil) {
        persist(
            FoundationModelProbeSnapshot(
                startedAt: Date(),
                finishedAt: nil,
                outcome: .inFlight,
                durationMs: nil,
                detail: detail
            ),
            to: defaults
        )
    }

    public static func markFinished(
        outcome: FoundationModelProbeSnapshot.Outcome,
        detail: String = "",
        defaults: UserDefaults? = nil
    ) {
        var row = load(from: defaults) ?? FoundationModelProbeSnapshot(
            startedAt: Date(),
            finishedAt: nil,
            outcome: .inFlight,
            durationMs: nil,
            detail: ""
        )
        let end = Date()
        row.finishedAt = end
        row.outcome = outcome
        row.durationMs = Int(end.timeIntervalSince(row.startedAt) * 1000)
        row.detail = detail
        persist(row, to: defaults)
    }

    /// Call at process start. An `inFlight` row with no finish means the last
    /// model call never returned (hang, jetsam, or reboot).
    @discardableResult
    public static func reconcileAbandonedInFlight(defaults: UserDefaults? = nil) -> FoundationModelProbeSnapshot? {
        guard var row = load(from: defaults), row.outcome == .inFlight else {
            return load(from: defaults)
        }
        row.outcome = .abandonedInFlight
        row.finishedAt = Date()
        row.durationMs = Int(Date().timeIntervalSince(row.startedAt) * 1000)
        if row.detail.isEmpty {
            row.detail = "never returned"
        }
        persist(row, to: defaults)
        return row
    }
}

public enum ModelPickJSON {
    public static func parse(_ raw: String) -> (menuItemId: String, reason: String)? {
        let blob = extractObject(raw) ?? raw
        guard let data = blob.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["menuItemId"] as? String,
              !id.isEmpty
        else {
            return nil
        }
        let reason = (object["reason"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (id, reason)
    }

    /// Small models often paste a whole `id=… restaurant=…` line into menuItemId.
    public static func legalMenuItemId(_ raw: String, legal: [String]) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !legal.isEmpty else { return nil }
        if legal.contains(trimmed) { return trimmed }
        if trimmed.hasPrefix("id=") {
            let after = trimmed.dropFirst(3)
            let token = after.split(whereSeparator: { $0.isWhitespace || $0 == "," }).first.map(String.init) ?? ""
            if legal.contains(token) { return token }
        }
        let hits = legal.filter { id in
            trimmed == id
                || trimmed.hasPrefix(id + " ")
                || trimmed.contains("id=\(id)")
        }
        return hits.max(by: { $0.count < $1.count })
    }

    /// Drops spice/cuisine tags and other stubs the small model uses as "reason".
    public static func usableReason(_ raw: String, minWords: Int = 8) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let stubs: Set<String> = [
            "mild", "medium", "hot", "none", "spicy", "spice",
            "thai", "mexican", "italian", "ramen", "indian", "korean", "american",
            "mediterranean", "japanese", "chinese", "vietnamese",
        ]
        if stubs.contains(lower) { return nil }
        let words = trimmed.split { !$0.isLetter && !$0.isNumber }.filter { !$0.isEmpty }
        if words.count < minWords { return nil }
        return trimmed
    }

    private static func extractObject(_ raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end
        else {
            return nil
        }
        return String(raw[start...end])
    }
}
