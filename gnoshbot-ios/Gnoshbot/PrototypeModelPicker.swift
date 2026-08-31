import Foundation
import GnoshbotData

/// On-device Foundation Models re-rank. Never the Bio-Shield. Never the Siri 400 ms clock.
enum PrototypeModelPicker {
    static func rerank(
        restaurants: [RestaurantSnapshot],
        menus: [String: MenuDocument],
        latitude: Double,
        longitude: Double,
        profile: ProfileEnvelope,
        remainingAllowanceUSDC: Decimal
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
        if let fromModel = await foundationPick(survivors: survivors, profile: profile) {
            return fromModel
        }
        return LunchScorer.cachedPick(from: LunchScorer.argmax(survivors))
    }

    private static func foundationPick(survivors: [ScoredItem], profile: ProfileEnvelope) async -> CachedPick? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationModelsBridge.pick(survivors: survivors, profile: profile)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
private enum FoundationModelsBridge {
    static func pick(survivors: [ScoredItem], profile: ProfileEnvelope) async -> CachedPick? {
        let model = SystemLanguageModel.default
        guard model.availability == .available else { return nil }
        let legal = survivors.map(\.item.id)
        let lines = survivors.map { scored in
            "id=\(scored.item.id) restaurant=\(scored.restaurant.name) item=\(scored.item.name) cuisine=\(scored.restaurant.cuisineTags.joined(separator: ",")) spice=\(scored.item.spice ?? "") desc=\(scored.item.description)"
        }.joined(separator: "\n")
        let instructions = """
        You pick one lunch item. Medical allergens are already removed. Do not invent ids.
        Flavor only: spice=\(profile.spice); cuisines=\(profile.preferredCuisines.joined(separator: ",")); meals=\(profile.preferredMealTypes.joined(separator: ",")).
        Reply with JSON only: {"menuItemId":"<id>"}.
        """
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: "Legal items:\n\(lines)")
            let id = parseItemId(response.content) ?? parseItemId(String(describing: response))
            guard let id, legal.contains(id) else { return nil }
            return LunchScorer.pickIfLegal(itemId: id, from: survivors)
        } catch {
            return nil
        }
    }

    private static func parseItemId(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["menuItemId"] as? String
        else {
            return nil
        }
        return id
    }
}
#endif
