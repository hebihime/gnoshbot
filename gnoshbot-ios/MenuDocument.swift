import CryptoKit
import Foundation

public struct MenuItemDocument: Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var extraNames: [String]
    public var priceCents: Int
    public var spice: String?
    public var mealTypes: [String]
    public var cuisineTags: [String]

    public init(
        id: String,
        name: String,
        description: String,
        extraNames: [String] = [],
        priceCents: Int,
        spice: String? = nil,
        mealTypes: [String] = [],
        cuisineTags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.extraNames = extraNames
        self.priceCents = priceCents
        self.spice = spice
        self.mealTypes = mealTypes
        self.cuisineTags = cuisineTags
    }

    public var searchableText: String {
        ([name, description] + extraNames).joined(separator: " ")
    }

    public var hasIngredientText: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || extraNames.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Shop cents → USDC decimal guess. Worker ignores this; server price is law.
    public var costUsdcGuess: Decimal {
        Decimal(priceCents) / 100
    }
}

public struct MenuDocument: Equatable, Sendable {
    public var merchantName: String
    public var cuisineTags: [String]
    public var items: [MenuItemDocument]

    public init(merchantName: String, cuisineTags: [String] = [], items: [MenuItemDocument]) {
        self.merchantName = merchantName
        self.cuisineTags = cuisineTags
        self.items = items
    }

    public static func parse(json: Data) throws -> MenuDocument {
        let root = try JSONSerialization.jsonObject(with: json)
        guard let object = root as? [String: Any] else {
            throw MenuParseError.notObject
        }
        let cuisine = stringArray(object["cuisineTags"] ?? object["cuisine_tags"])
        let merchant = (object["name"] as? String)
            ?? ((object["store"] as? [String: Any])?["name"] as? String)
            ?? ""
        var items: [MenuItemDocument] = []
        if let rawItems = object["items"] as? [[String: Any]] {
            items = rawItems.compactMap { parseItem($0, cuisine: cuisine) }
        } else if let menus = object["menus"] as? [[String: Any]] {
            for menu in menus {
                let nested = (menu["menu"] as? [String: Any]) ?? menu
                let categories = nested["categories"] as? [[String: Any]] ?? []
                for category in categories {
                    let catItems = category["items"] as? [[String: Any]] ?? []
                    items.append(contentsOf: catItems.compactMap { parseItem($0, cuisine: cuisine) })
                }
            }
        }
        return MenuDocument(merchantName: merchant, cuisineTags: cuisine, items: items)
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func bundledDemoJSON() -> Data {
        if let url = Bundle.module.url(forResource: "demo-shop-menu", withExtension: "json"),
           let data = try? Data(contentsOf: url)
        {
            return data
        }
        return Data(MenuDocument.embeddedDemoUTF8.utf8)
    }

    private static func parseItem(_ raw: [String: Any], cuisine: [String]) -> MenuItemDocument? {
        let name = (raw["name"] as? String) ?? ""
        guard !name.isEmpty else { return nil }
        let id = (raw["id"] as? String)
            ?? (raw["menuItemId"] as? String)
            ?? (raw["merchant_supplied_id"] as? String)
            ?? UUID().uuidString
        let description = (raw["description"] as? String) ?? ""
        let price = intValue(raw["price"]) ?? 0
        let extras = raw["extras"] as? [[String: Any]] ?? []
        let extraNames = extras.compactMap { $0["name"] as? String }
        return MenuItemDocument(
            id: id,
            name: name,
            description: description,
            extraNames: extraNames,
            priceCents: price,
            spice: raw["spice"] as? String,
            mealTypes: stringArray(raw["mealTypes"] ?? raw["meal_types"]),
            cuisineTags: cuisine
        )
    }

    private static func stringArray(_ value: Any?) -> [String] {
        (value as? [String]) ?? []
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    /// Fallback if the SPM resource is missing (app target tests).
    public static let embeddedDemoUTF8 = """
    {"name":"Demo Kitchen (wrap)","cuisineTags":["american","bowls"],"items":[{"id":"3fa85f64-5717-4562-b3fc-2c963f66afa6","name":"Garden Bowl","description":"rice, greens, tahini, cucumber","price":1400,"spice":"medium","mealTypes":["bowls"]}]}
    """
}

public enum MenuParseError: Error {
    case notObject
}
