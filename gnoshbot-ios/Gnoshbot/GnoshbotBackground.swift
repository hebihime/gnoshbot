import Foundation
import GnoshbotData
import UIKit

/// `beginBackgroundTask` + background `URLSession`. Not `Task.detached`.
final class GnoshbotBackground: NSObject, URLSessionTaskDelegate, URLSessionDelegate {
    static let shared = GnoshbotBackground()
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    private lazy var session: URLSession = {
        URLSession(
            configuration: SettlementSession.makeBackgroundConfiguration(),
            delegate: self,
            delegateQueue: nil
        )
    }()

    func enqueueSettlement(pick: CachedPick?, delivery: DeliveryLocation) {
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "gnoshbot.settle") { [weak self] in
            self?.endBg()
        }
        Task { @MainActor in
            defer { endBg() }
            let store = GnoshbotStore.shared
            let settings = ControlPlaneSettings.fromAppBundle()
            let customer = DeviceIdentity.opaqueUser(defaults: DeviceIdentity.appGroupDefaults())
            guard let config = ShopRuntimeConfig.from(
                settings: settings,
                customerId: customer,
                remainingAllowanceAtomic: store.remainingAllowanceAtomic
            ) else {
                return
            }
            do {
                _ = try await SettlementWorker(
                    http: session,
                    store: store,
                    config: config,
                    signer: FixtureExactSigner(),
                    notifier: LocalPushSink(),
                    poller: FulfillmentPoller(capSeconds: config.pollCapSeconds)
                ).run(pick: pick, delivery: delivery)
            } catch {
                // Worker already recorded `failed` + push for `SettlementError`.
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {}

    private func endBg() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }
}
