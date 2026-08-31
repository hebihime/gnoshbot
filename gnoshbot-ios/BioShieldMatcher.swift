import Foundation

/// In-memory profile for I12. I10 will SE-wrap this; empty shield means no allergen filter.
public struct ProfileEnvelope: Equatable, Sendable, Codable {
    public var allergens: [String]
    public var frameworks: [String]
    public var customExclusions: [String]
    public var spice: String
    public var preferredCuisines: [String]
    public var neverIngredients: [String]
    public var preferredMealTypes: [String]

    public init(
        allergens: [String] = [],
        frameworks: [String] = [],
        customExclusions: [String] = [],
        spice: String = "medium",
        preferredCuisines: [String] = [],
        neverIngredients: [String] = [],
        preferredMealTypes: [String] = []
    ) {
        self.allergens = allergens
        self.frameworks = frameworks
        self.customExclusions = customExclusions
        self.spice = spice
        self.preferredCuisines = preferredCuisines
        self.neverIngredients = neverIngredients
        self.preferredMealTypes = preferredMealTypes
    }

    public static let empty = ProfileEnvelope()

    public var hasAllergenConstraint: Bool {
        !allergens.isEmpty || !frameworks.isEmpty || !customExclusions.isEmpty
    }

    public static let allergenSlugs = [
        "peanut", "tree nut", "shellfish", "dairy", "egg", "wheat / gluten", "soy", "sesame", "fish",
    ]
    public static let frameworkSlugs = ["vegan", "vegetarian", "halal", "kosher"]
    public static let cuisineChips = [
        "thai", "mexican", "italian", "mediterranean", "japanese", "indian", "korean", "chinese",
        "american", "healthy bowls", "pizza", "burgers", "noodles", "bbq", "seafood",
    ]
    public static let mealChips = ["bowls", "noodles", "tacos", "burritos", "pizza"]
}

public enum BioShieldMatcher {
    public static let synonyms: [String: [String]] = [
        "peanut": ["peanut", "peanuts", "groundnut", "groundnuts", "satay"],
        "tree nut": ["almond", "cashew", "walnut", "pecan", "hazelnut", "pistachio", "tree nut"],
        "shellfish": ["shellfish", "shrimp", "prawn", "prawns", "crab", "lobster", "crawfish"],
        "dairy": ["dairy", "milk", "cheese", "mozzarella", "butter", "cream", "yogurt"],
        "egg": ["egg", "eggs"],
        "wheat / gluten": ["wheat", "gluten", "flour"],
        "soy": ["soy", "soya", "tofu", "edamame"],
        "sesame": ["sesame", "tahini"],
        "fish": ["fish", "cod", "salmon", "tuna", "anchovy"],
        "vegan": ["chicken", "beef", "pork", "fish", "egg", "cheese", "milk", "mozzarella"],
        "vegetarian": ["chicken", "beef", "pork", "fish", "shrimp", "prawn"],
        "halal": ["pork", "bacon", "ham", "wine"],
        "kosher": ["pork", "bacon", "shellfish", "shrimp"],
    ]

    public static func collisions(item: MenuItemDocument, profile: ProfileEnvelope) -> Bool {
        if profile.hasAllergenConstraint && !item.hasIngredientText {
            return true
        }
        let haystack = fold(item.searchableText)
        for slug in profile.allergens + profile.frameworks {
            if hits(slug: slug, haystack: haystack) {
                return true
            }
        }
        for custom in profile.customExclusions where !custom.isEmpty {
            if haystack.contains(fold(custom)) {
                return true
            }
        }
        return false
    }

    public static func neverHits(item: MenuItemDocument, profile: ProfileEnvelope) -> Bool {
        let haystack = fold(item.searchableText)
        return profile.neverIngredients.contains { haystack.contains(fold($0)) }
    }

    private static func hits(slug: String, haystack: String) -> Bool {
        let keys = synonyms[slug.lowercased()] ?? [slug]
        return keys.contains { haystack.contains(fold($0)) }
    }

    private static func fold(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
