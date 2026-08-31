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
        x402Version: Int = 1
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

        let best = survivors.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.item.id < rhs.item.id
        }!
        return .pick(
            CachedPick(
                overtureId: best.restaurant.overtureId,
                shopPrefix: best.restaurant.shopPrefix,
                menuItemId: best.item.id,
                merchantName: best.restaurant.name,
                itemName: best.item.name,
                costUsdcGuess: best.item.costUsdcGuess
            )
        )
    }
}
