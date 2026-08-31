import Foundation
import Testing
@testable import GnoshbotData

@Suite("InquirySpeech")
struct InquirySpeechTests {
    @Test("minutes appear only when etaMinutes is set")
    func minutesAfterEta() {
        let row = sample(.settled, eta: nil)
        #expect(InquirySpeech.status(row) == InquirySpeech.organizingCourier)
        #expect(!InquirySpeech.status(row).contains("minute"))
        row.etaMinutes = 22
        #expect(InquirySpeech.status(row) == "In the kitchen. About 22 minutes.")
    }

    @Test("dispatched remaining uses eta and timestamp, not a model")
    func dispatchedRemaining() {
        let row = sample(.dispatched, eta: 20)
        row.timestamp = Date().addingTimeInterval(-5 * 60)
        #expect(InquirySpeech.status(row, now: Date()) == "On the way. 15 minutes.")
    }

    @Test("destination and SKU and cost are local fields")
    func otherIntents() {
        let row = sample(.settled, eta: nil)
        row.deliverySpokenLine = "Home, 14 Pine Street"
        row.itemName = "Burrito"
        row.merchantName = "Wrap Shop"
        row.costUsdc = 14.5
        #expect(InquirySpeech.destination(row) == "Home, 14 Pine Street")
        #expect(InquirySpeech.ordered(row) == "Burrito from Wrap Shop.")
        #expect(InquirySpeech.cost(row) == "14.50 USDC")
    }

    @Test("poll cap copy does not invent minutes")
    func pollCapCopy() {
        let row = sample(.processingLogistics, eta: nil)
        row.awaitingKitchenTime = true
        #expect(InquirySpeech.status(row) == InquirySpeech.waitingOnKitchenTime)
    }

    private func sample(_ status: SpokenStatus, eta: Int?) -> ActiveOrderCache {
        let delivery = DeliveryLocation(
            label: "Home",
            line1: "14 Pine Street",
            city: "Brooklyn",
            region: "NY",
            postalCode: "11201",
            country: "US",
            latitude: 40.6944,
            longitude: -73.9903,
            isDefault: true
        )
        let row = ActiveOrderCache(
            orderId: "o1",
            idempotencyKey: "k1",
            shopPrefix: ShopPrefix.demo,
            delivery: delivery
        )
        row.status = status
        row.etaMinutes = eta
        return row
    }
}

@Suite("PushCopy")
struct PushCopyTests {
    @Test("§1.6 strings")
    func copy() {
        #expect(PushCopy.paidKitchenOnIt.body == "Paid. Kitchen is on it.")
        #expect(PushCopy.arriving(minutes: 22).body == "Arriving in 22 minutes.")
        #expect(PushCopy.kitchenDeclinedRefundStarted.body == "Kitchen declined. Refund started.")
        #expect(PushCopy.launchAborted(reason: "Payment rejected").body == "Launch aborted. Payment rejected. Tap to retry.")
        #expect(PushCopy.emptyPayableBox.body == LaunchCopy.emptyPayableBox.spoken)
        #expect(PushCopy.bioShieldEmptiesBox.body == LaunchCopy.bioShieldEmptiesBox.spoken)
        #expect(!PushCopy.emptyPayableBox.body.contains("Tap to retry"))
    }
}

@Suite("FulfillmentPollSchedule")
struct FulfillmentPollScheduleTests {
    @Test("5s then 15s then 60s then cap")
    func cadence() {
        #expect(FulfillmentPollSchedule.delaySeconds(elapsed: 10, etaKnown: false, terminal: false, cap: 3300) == 5)
        #expect(FulfillmentPollSchedule.delaySeconds(elapsed: 90, etaKnown: false, terminal: false, cap: 3300) == 15)
        #expect(FulfillmentPollSchedule.delaySeconds(elapsed: 90, etaKnown: true, terminal: false, cap: 3300) == 60)
        #expect(FulfillmentPollSchedule.delaySeconds(elapsed: 3300, etaKnown: false, terminal: false, cap: 3300) == nil)
        #expect(FulfillmentPollSchedule.delaySeconds(elapsed: 10, etaKnown: false, terminal: true, cap: 3300) == nil)
    }
}
