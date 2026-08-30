import Foundation
import SwiftData

@Model
public final class MenuCache {
    @Attribute(.unique) public var shopPrefix: String
    public var json: Data
    public var sha256: String
    public var fetchedAt: Date

    public init(shopPrefix: String, json: Data, sha256: String, fetchedAt: Date = Date()) {
        self.shopPrefix = shopPrefix
        self.json = json
        self.sha256 = sha256
        self.fetchedAt = fetchedAt
    }
}
