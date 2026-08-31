import Foundation
import GnoshbotData
import OSLog

/// On-device Foundation Models re-rank. Never the Bio-Shield. Never the Siri 400 ms clock.
enum PrototypeModelPicker {
    private static let log = Logger(subsystem: "com.gnoshbot", category: "FoundationModel")

    static func rerank(
        restaurants: [RestaurantSnapshot],
        menus: [String: MenuDocument],
        latitude: Double,
        longitude: Double,
        profile: ProfileEnvelope,
        remainingAllowanceUSDC: Decimal,
        prior: PriorLunch?
    ) async -> CachedPick? {
        let assembled = LunchScorer.workingSet(
            restaurants: restaurants,
            menus: menus,
            latitude: latitude,
            longitude: longitude,
            profile: profile,
            remainingAllowanceUSDC: remainingAllowanceUSDC
        )
        guard case .items(let survivors) = assembled else { return nil }
        let pool = LunchScorer.withoutImmediateRepeat(survivors, prior: prior)
        if let fromModel = await foundationPick(survivors: pool, profile: profile, prior: prior) {
            return fromModel
        }
        return LunchScorer.cachedPick(from: LunchScorer.argmax(pool), profile: profile)
    }

    private static func foundationPick(
        survivors: [ScoredItem],
        profile: ProfileEnvelope,
        prior: PriorLunch?
    ) async -> CachedPick? {
        guard await FoundationModelGate.shared.tryBegin() else {
            log.warning("skip: prior session still running")
            FoundationModelProbe.markFinished(outcome: .skippedBusy)
            return nil
        }
        let pick: CachedPick?
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            pick = await FoundationModelsBridge.pick(
                survivors: survivors,
                profile: profile,
                prior: prior,
                log: log
            )
        } else {
            log.info("skip: FoundationModels needs iOS 26")
            FoundationModelProbe.markFinished(outcome: .skippedUnavailable, detail: "needs iOS 26")
            pick = nil
        }
        #else
        log.info("skip: FoundationModels not linked")
        FoundationModelProbe.markFinished(outcome: .skippedUnavailable, detail: "not linked")
        pick = nil
        #endif
        await FoundationModelGate.shared.end()
        return pick
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
private enum FoundationModelsBridge {
    static func pick(
        survivors: [ScoredItem],
        profile: ProfileEnvelope,
        prior: PriorLunch?,
        log: Logger
    ) async -> CachedPick? {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            log.info("skip: availability \(String(describing: model.availability), privacy: .public)")
            FoundationModelProbe.markFinished(
                outcome: .skippedUnavailable,
                detail: String(describing: model.availability)
            )
            return nil
        }
        log.info("waiting \(FoundationModelProbe.siriTeardownNanoseconds / 1_000_000)ms for Siri teardown")
        try? await Task.sleep(nanoseconds: FoundationModelProbe.siriTeardownNanoseconds)
        if Task.isCancelled {
            FoundationModelProbe.markFinished(outcome: .error, detail: "cancelled before respond")
            return nil
        }

        let legal = survivors.map(\.item.id)
        let lines = survivors.map { scored in
            "\(scored.item.id) | \(scored.item.name) | \(scored.restaurant.name) | \(scored.restaurant.cuisineTags.joined(separator: ",")) | spice=\(scored.item.spice ?? "") | \(scored.item.description)"
        }.joined(separator: "\n")
        let avoid: String
        if let prior, !prior.itemName.isEmpty {
            avoid = """

            Last lunch (forbidden this turn): id=\(prior.menuItemId) item=\(prior.itemName) kitchen=\(prior.merchantName).
            Do not pick that id. Do not copy this reason: \(prior.pickReason)
            """
        } else {
            avoid = ""
        }
        let instructions = """
        You pick one lunch item from the legal list. Medical allergens are already removed. Do not invent ids.
        Flavor prefs: spice=\(profile.spice); cuisines=\(profile.preferredCuisines.joined(separator: ",")); meals=\(profile.preferredMealTypes.joined(separator: ",")).
        Reply with JSON only. menuItemId must be exactly the first token on one legal line (for example it-pepperoni), never the rest of the line.
        reason must be one new sentence of at least 12 words naming that dish and kitchen and why it fits the flavor prefs.
        Never put a lone tag in reason. Do not mention allergens. Do not reuse a previous reason.
        JSON shape: {"menuItemId":"<legal id>","reason":"<new sentence>"}
        """
        let prompt = "Legal items:\n\(lines)\(avoid)"
        let session = LanguageModelSession(instructions: instructions)
        FoundationModelProbe.markStarted(detail: "respond n=\(legal.count)")
        log.info("respond start timeout=\(FoundationModelProbe.respondTimeoutSeconds, privacy: .public)s")
        do {
            let text = try await AsyncTimeout.firstCompleted(
                seconds: FoundationModelProbe.respondTimeoutSeconds
            ) {
                let response = try await session.respond(to: prompt)
                return response.content
            }
            let parsed = ModelPickJSON.parse(text)
            let id = ModelPickJSON.legalMenuItemId(parsed?.menuItemId ?? "", legal: legal)
            guard let id else {
                log.warning("illegal or unparsable id")
                FoundationModelProbe.markFinished(outcome: .invalidId, detail: parsed?.menuItemId ?? "unparsed")
                return nil
            }
            if let prior, !prior.menuItemId.isEmpty, id == prior.menuItemId {
                log.warning("repeat of prior lunch")
                FoundationModelProbe.markFinished(outcome: .invalidId, detail: "repeat \(id)")
                return nil
            }
            var reason = ModelPickJSON.usableReason(parsed?.reason ?? "") ?? ""
            if let priorReason = prior?.pickReason, !priorReason.isEmpty,
               reason.caseInsensitiveCompare(priorReason) == .orderedSame {
                reason = ""
            }
            log.info("respond ok id=\(id, privacy: .public)")
            FoundationModelProbe.markFinished(outcome: .success, detail: id)
            return LunchScorer.pickIfLegal(
                itemId: id,
                from: survivors,
                source: "foundation-model",
                reason: reason,
                profile: profile
            )
        } catch is AsyncTimeoutError {
            log.error("respond timed out")
            FoundationModelProbe.markFinished(outcome: .timeout)
            return nil
        } catch {
            log.error("respond error \(error.localizedDescription, privacy: .public)")
            FoundationModelProbe.markFinished(outcome: .error, detail: error.localizedDescription)
            return nil
        }
    }
}
#endif
