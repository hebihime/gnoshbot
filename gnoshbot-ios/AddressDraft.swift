import Foundation

public struct AddressDraft: Equatable, Sendable {
    public var label: String
    public var line1: String
    public var line2: String?
    public var city: String
    public var region: String
    public var postalCode: String
    public var country: String
    public var isDefault: Bool

    public init(
        label: String,
        line1: String,
        line2: String? = nil,
        city: String,
        region: String,
        postalCode: String,
        country: String,
        isDefault: Bool
    ) {
        self.label = label
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.region = region
        self.postalCode = postalCode
        self.country = country
        self.isDefault = isDefault
    }

    public var geocodeQuery: String {
        [line1, line2 ?? "", city, region, postalCode, country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    public static let brooklynHome = AddressDraft(
        label: BrooklynDemoAddress.label,
        line1: BrooklynDemoAddress.line1,
        city: BrooklynDemoAddress.city,
        region: BrooklynDemoAddress.region,
        postalCode: BrooklynDemoAddress.postalCode,
        country: BrooklynDemoAddress.country,
        isDefault: true
    )
}

public enum AddressSaveError: Error, Equatable {
    case emptyLabel
    case emptyLine1
    case duplicateLabel
    case geocodeFailed
}

public protocol AddressGeocoding: Sendable {
    func geocode(_ draft: AddressDraft) async throws -> (latitude: Double, longitude: Double)
}

public struct CoordinateGeocoder: AddressGeocoding {
    public var latitude: Double
    public var longitude: Double
    public var shouldFail: Bool

    public init(latitude: Double, longitude: Double, shouldFail: Bool = false) {
        self.latitude = latitude
        self.longitude = longitude
        self.shouldFail = shouldFail
    }

    public func geocode(_ draft: AddressDraft) async throws -> (latitude: Double, longitude: Double) {
        if shouldFail { throw AddressSaveError.geocodeFailed }
        return (latitude, longitude)
    }
}

public struct AddressCopy {
    public static let emptyState = "Gnoshbot will always ask before sending food. Add Home to start."
    public static let caption =
        "Siri will read this address back every time you order. GPS will not be used as the drop-off."
    public static let mappingKitchens = "Mapping kitchens nearby."
}
