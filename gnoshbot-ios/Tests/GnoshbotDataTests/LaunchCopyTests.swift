import Testing
@testable import GnoshbotData

@Suite("LaunchCopy")
struct LaunchCopyTests {
    @Test("§1.5 strings are exact and do not interpolate merchant, SKU, price, or minutes", arguments: [
        (LaunchCopy.noSavedAddresses, "Add a delivery address in Gnoshbot first."),
        (LaunchCopy.confirmationDeclined, "No order placed."),
        (LaunchCopy.unknownLabel, "I don't have that address. Open Gnoshbot to add it."),
        (LaunchCopy.allowanceZero, "Order denied. Daily allowance exceeded."),
        (LaunchCopy.unfunded, "Launch aborted. Insufficient funds. Top up in Gnoshbot."),
        (LaunchCopy.emptyPayableBox, "No payable kitchen in range of that address."),
        (LaunchCopy.bioShieldEmptiesBox, "Every nearby menu collides with your Bio-Shield. I won't guess."),
    ] as [(LaunchCopy, String)])
    func exactSpokenLine(copy: LaunchCopy, expected: String) {
        #expect(copy.spoken == expected)
        #expect(!copy.spoken.contains("$"))
        #expect(!copy.spoken.contains("USDC"))
        #expect(!copy.spoken.contains("minute"))
        #expect(!copy.spoken.contains("SKU"))
    }
}
