import AppIntents
import Foundation

/// Resolves saved `DeliveryLocation` rows only. Unknown ids yield an empty result — never a geocoded street.
public struct DeliveryLocationQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [DeliveryLocationEntity] {
        try await MainActor.run {
            let saved = try GnoshbotStore.shared.deliveryLocations()
            let byId = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
            return identifiers.compactMap { id in
                byId[id]?.asEntity()
            }
        }
    }

    public func suggestedEntities() async throws -> [DeliveryLocationEntity] {
        try await MainActor.run {
            try GnoshbotStore.shared.deliveryLocations().map { $0.asEntity() }
        }
    }
}
