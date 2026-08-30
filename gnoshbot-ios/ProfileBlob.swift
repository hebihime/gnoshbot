import Foundation
import SwiftData

/// SE-wrapped Bio-Shield + flavor + remaining allowance. Delivery addresses are not stored here.
@Model
public final class ProfileBlob {
    public var ciphertext: Data
    public var nonce: Data
    public var wrappedKey: Data

    public init(ciphertext: Data, nonce: Data, wrappedKey: Data) {
        self.ciphertext = ciphertext
        self.nonce = nonce
        self.wrappedKey = wrappedKey
    }
}
