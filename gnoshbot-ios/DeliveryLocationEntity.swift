import AppIntents
import Foundation

public struct DeliveryLocationEntity: AppEntity, Identifiable, Sendable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Delivery location")
    public static let defaultQuery = DeliveryLocationQuery()

    public var id: UUID
    public var spokenLine: String

    public init(id: UUID, spokenLine: String) {
        self.id = id
        self.spokenLine = spokenLine
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: spokenLine))
    }
}

extension DeliveryLocation {
    public func asEntity() -> DeliveryLocationEntity {
        DeliveryLocationEntity(id: id, spokenLine: spokenLine)
    }
}
