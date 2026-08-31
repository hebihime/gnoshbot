import Foundation

public struct CachedPick: Equatable, Sendable {
    public var overtureId: String
    public var shopPrefix: String
    public var menuItemId: String
    public var quantity: Int
    public var modifierIds: [String]
    public var merchantName: String
    public var itemName: String
    public var costUsdcGuess: Decimal
    /// Menu snapshot when known. 402 `accepts[0].payTo` must match place `payTo`.
    public var payTo: String
    /// 1 = shop host (`X-PAYMENT`). 2 = native nodes (`PAYMENT-SIGNATURE`).
    public var x402Version: Int
    /// `scorer` or `foundation-model`. Empty until a pick is applied.
    public var pickSource: String
    /// Why this item won. Never spoken on the launch turn.
    public var pickReason: String

    public init(
        overtureId: String,
        shopPrefix: String,
        menuItemId: String,
        quantity: Int = 1,
        modifierIds: [String] = [],
        merchantName: String,
        itemName: String,
        costUsdcGuess: Decimal,
        payTo: String = "",
        x402Version: Int = 1,
        pickSource: String = "scorer",
        pickReason: String = ""
    ) {
        self.overtureId = overtureId
        self.shopPrefix = shopPrefix
        self.menuItemId = menuItemId
        self.quantity = quantity
        self.modifierIds = modifierIds
        self.merchantName = merchantName
        self.itemName = itemName
        self.costUsdcGuess = costUsdcGuess
        self.payTo = payTo
        self.x402Version = x402Version
        self.pickSource = pickSource
        self.pickReason = pickReason
    }

    public var usesShopV1: Bool { x402Version != 2 }
}

public enum LunchScoreOutcome: Equatable, Sendable {
    case pick(CachedPick)
    case emptyPayable
    case bioShieldEmpty
}

public struct ScoredItem: Equatable, Sendable {
    public var restaurant: RestaurantSnapshot
    public var item: MenuItemDocument
    public var score: Int
}

public struct RestaurantSnapshot: Equatable, Sendable {
    public var overtureId: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var integration: String
    public var shopPrefix: String
    public var cuisineTags: [String]

    public init(
        overtureId: String,
        name: String,
        latitude: Double,
        longitude: Double,
        integration: String,
        shopPrefix: String,
        cuisineTags: [String] = []
    ) {
        self.overtureId = overtureId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.integration = integration
        self.shopPrefix = shopPrefix
        self.cuisineTags = cuisineTags
    }
}

public struct PriorLunch: Equatable, Sendable {
    public var menuItemId: String
    public var itemName: String
    public var merchantName: String
    public var pickReason: String

    public init(
        menuItemId: String = "",
        itemName: String,
        merchantName: String,
        pickReason: String = ""
    ) {
        self.menuItemId = menuItemId
        self.itemName = itemName
        self.merchantName = merchantName
        self.pickReason = pickReason
    }
}

public enum LunchScorer {
    public static let maxRestaurants = 10
    public static let maxItemsPerRestaurant = 5

    public static func score(item: MenuItemDocument, restaurantCuisines: [String], profile: ProfileEnvelope) -> Int? {
        if BioShieldMatcher.neverHits(item: item, profile: profile) {
            return nil
        }
        var score = 0
        let pref = Set(profile.preferredCuisines.map { $0.lowercased() })
        let rest = Set(restaurantCuisines.map { $0.lowercased() })
        if !pref.isEmpty && !pref.isDisjoint(with: rest) {
            score += 3
        } else if !pref.isEmpty {
            score -= 2
        }
        let meals = Set(item.mealTypes.map { $0.lowercased() })
        let wantMeals = Set(profile.preferredMealTypes.map { $0.lowercased() })
        if !wantMeals.isEmpty && !wantMeals.isDisjoint(with: meals) {
            score += 1
        }
        if let spice = item.spice, spice.lowercased() == profile.spice.lowercased() {
            score += 1
        }
        return score
    }

    public static func pick(
        restaurants: [RestaurantSnapshot],
        menus: [String: MenuDocument],
        near delivery: DeliveryLocation,
        profile: ProfileEnvelope,
        remainingAllowanceUSDC: Decimal
    ) -> LunchScoreOutcome {
        pick(
            restaurants: restaurants,
            menus: menus,
            latitude: delivery.latitude,
            longitude: delivery.longitude,
            profile: profile,
            remainingAllowanceUSDC: remainingAllowanceUSDC
        )
    }

    public static func pick(
        restaurants: [RestaurantSnapshot],
        menus: [String: MenuDocument],
        latitude: Double,
        longitude: Double,
        profile: ProfileEnvelope,
        remainingAllowanceUSDC: Decimal
    ) -> LunchScoreOutcome {
        let assembled = workingSet(
            restaurants: restaurants,
            menus: menus,
            latitude: latitude,
            longitude: longitude,
            profile: profile,
            remainingAllowanceUSDC: remainingAllowanceUSDC
        )
        switch assembled {
        case .emptyPayable:
            return .emptyPayable
        case .bioShieldEmpty:
            return .bioShieldEmpty
        case .items(let survivors):
            return .pick(cachedPick(from: argmax(survivors), profile: profile))
        }
    }

    /// Drops the last lunch when another legal item exists. Never empties the box.
    public static func withoutImmediateRepeat(
        _ survivors: [ScoredItem],
        prior: PriorLunch?
    ) -> [ScoredItem] {
        guard let prior else { return survivors }
        let filtered = survivors.filter { scored in
            if !prior.menuItemId.isEmpty {
                return scored.item.id != prior.menuItemId
            }
            let sameName = scored.item.name.caseInsensitiveCompare(prior.itemName) == .orderedSame
            let sameKitchen = scored.restaurant.name.caseInsensitiveCompare(prior.merchantName) == .orderedSame
            return !(sameName && sameKitchen)
        }
        return filtered.isEmpty ? survivors : filtered
    }

    public enum WorkingSet: Equatable, Sendable {
        case emptyPayable
        case bioShieldEmpty
        case items([ScoredItem])
    }

    /// Bio-Shield + never-ingredients + range + cap. LLM may only choose an id from `.items`.
    public static func workingSet(
        restaurants: [RestaurantSnapshot],
        menus: [String: MenuDocument],
        latitude: Double,
        longitude: Double,
        profile: ProfileEnvelope,
        remainingAllowanceUSDC: Decimal
    ) -> WorkingSet {
        let payable = restaurants.filter { kitchen in
            let kind = kitchen.integration
            let ok = kind == "native" || kind == "proxy_wrapped"
            return ok && LunchRange.isWithinFiveMiles(
                latitude: kitchen.latitude,
                longitude: kitchen.longitude,
                centerLatitude: latitude,
                centerLongitude: longitude
            ) && !ShopPrefix.isSandbox(kitchen.shopPrefix)
        }
        if payable.isEmpty {
            return .emptyPayable
        }

        var survivors: [ScoredItem] = []
        var anyPassedShield = false
        for kitchen in payable.prefix(maxRestaurants) {
            guard let menu = menus[kitchen.shopPrefix] else { continue }
            var kept = 0
            for item in menu.items {
                if BioShieldMatcher.collisions(item: item, profile: profile) {
                    continue
                }
                anyPassedShield = true
                guard let points = score(
                    item: item,
                    restaurantCuisines: kitchen.cuisineTags + menu.cuisineTags,
                    profile: profile
                ) else {
                    continue
                }
                if item.costUsdcGuess > remainingAllowanceUSDC {
                    continue
                }
                survivors.append(
                    ScoredItem(
                        restaurant: kitchen,
                        item: item,
                        score: points
                    )
                )
                kept += 1
                if kept >= maxItemsPerRestaurant { break }
            }
        }

        if survivors.isEmpty {
            if profile.hasAllergenConstraint && !anyPassedShield {
                return .bioShieldEmpty
            }
            return .emptyPayable
        }
        return .items(survivors)
    }

    public static func argmax(_ survivors: [ScoredItem]) -> ScoredItem {
        survivors.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.item.id < rhs.item.id
        }!
    }

    public static func cachedPick(from scored: ScoredItem, profile: ProfileEnvelope = .empty) -> CachedPick {
        CachedPick(
            overtureId: scored.restaurant.overtureId,
            shopPrefix: scored.restaurant.shopPrefix,
            menuItemId: scored.item.id,
            merchantName: scored.restaurant.name,
            itemName: scored.item.name,
            costUsdcGuess: scored.item.costUsdcGuess,
            pickSource: "scorer",
            pickReason: scorerReason(from: scored, profile: profile)
        )
    }

    public static func scorerReason(from scored: ScoredItem, profile: ProfileEnvelope) -> String {
        var parts = ["Local scorer chose this (score \(scored.score))."]
        let pref = Set(profile.preferredCuisines.map { $0.lowercased() })
        let rest = Set(scored.restaurant.cuisineTags.map { $0.lowercased() })
        let overlap = pref.intersection(rest)
        if !overlap.isEmpty {
            parts.append("Cuisine overlap: \(overlap.sorted().joined(separator: ", ")).")
        } else if !pref.isEmpty {
            parts.append("No preferred-cuisine match.")
        }
        if let spice = scored.item.spice, spice.lowercased() == profile.spice.lowercased() {
            parts.append("Spice \(spice) matches your setting.")
        }
        let meals = Set(scored.item.mealTypes.map { $0.lowercased() })
        let want = Set(profile.preferredMealTypes.map { $0.lowercased() })
        let mealHit = meals.intersection(want)
        if !mealHit.isEmpty {
            parts.append("Meal type: \(mealHit.sorted().joined(separator: ", ")).")
        }
        parts.append("Bio-Shield already allowed it. The on-device model did not override this pick.")
        return parts.joined(separator: " ")
    }

    /// Foundation Models (and tests) may only land on a pre-filtered survivor.
    public static func pickIfLegal(
        itemId: String,
        from survivors: [ScoredItem],
        source: String = "scorer",
        reason: String = "",
        profile: ProfileEnvelope = .empty
    ) -> CachedPick? {
        guard let hit = survivors.first(where: { $0.item.id == itemId }) else { return nil }
        if source == "foundation-model" {
            var pick = cachedPick(from: hit, profile: profile)
            pick.pickSource = source
            let trimmed = ModelPickJSON.usableReason(reason) ?? ""
            pick.pickReason = trimmed.isEmpty
                ? "On-device model chose \(hit.item.name) at \(hit.restaurant.name) from the Bio-Shield-legal set. It did not explain why."
                : trimmed
            return pick
        }
        return cachedPick(from: hit, profile: profile)
    }
}
