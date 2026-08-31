import Foundation
import GnoshbotData
import UIKit

/// `beginBackgroundTask` + background `URLSession`. Not `Task.detached`.
@MainActor
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
        let settings = ControlPlaneSettings.fromAppBundle()
        if settings.isDemo { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "gnoshbot.settle") { [weak self] in
            self?.endBg()
        }
        Task {
            defer { endBg() }
            await settle(pick: pick, delivery: delivery)
        }
    }

    @MainActor
    private func settle(pick: CachedPick?, delivery: DeliveryLocation) async {
        let store = GnoshbotStore.shared
        let settings = ControlPlaneSettings.fromAppBundle()
        if settings.isDemo { return }
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

    func enqueueFollowThrough(delivery: DeliveryLocation) {
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "gnoshbot.follow") { [weak self] in
            self?.endBg()
        }
        Task {
            defer { endBg() }
            let store = GnoshbotStore.shared
            let settings = ControlPlaneSettings.fromAppBundle()
            let notifier = LocalPushSink()
            do {
                let outcome = try await LaunchFollowThrough.run(
                    store: store,
                    delivery: delivery,
                    notifier: notifier
                )
                switch outcome {
                case .failed:
                    return
                case .picked(let scorerPick):
                    if settings.isDemo {
                        let pick = await PrototypeModelPicker.rerank(
                            restaurants: try store.restaurantSnapshots(),
                            menus: try store.menuDocuments(),
                            latitude: delivery.latitude,
                            longitude: delivery.longitude,
                            profile: store.profile,
                            remainingAllowanceUSDC: store.remainingAllowanceUSDC,
                            prior: try store.priorLunch()
                        ) ?? scorerPick
                        try store.applyLaunchingPick(pick)
                        return
                    }
                    try store.applyLaunchingPick(scorerPick)
                    await settle(pick: scorerPick, delivery: delivery)
                }
            } catch {
                try? store.failLatestLaunch(.launchAborted(reason: "Follow-through failed"))
                await notifier.notify(.launchAborted(reason: "Follow-through failed"))
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {}

    private func endBg() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }
}
