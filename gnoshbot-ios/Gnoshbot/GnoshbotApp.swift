import GnoshbotData
import SwiftData
import SwiftUI

@main
struct GnoshbotApp: App {
    private let container: ModelContainer

    init() {
        do {
            let built = try GnoshbotPersistence.makeAppContainer()
            GnoshbotStore.shared.attach(built)
            let settings = ControlPlaneSettings.fromAppBundle()
            // Demo TestFlight only: not a funded CDP Smart Account (I16). Skips I17 network.
            GnoshbotStore.shared.applyDemoFundingIfNeeded(settings)
            if settings.isDemo {
                try? GnoshbotStore.shared.seedPrototypeHomeIfNeeded()
                Task { @MainActor in
                    try? await PrototypeCatalog.hydrate(into: GnoshbotStore.shared)
                }
            }
            try? SpenderKey.generateIfNeeded()
            container = built
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }

    /// SwiftData lives in the application process and `group.com.gnoshbot`.
    /// App Intents have no widget / App Intents extension target, so they run here.
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(container)
    }
}

enum GnoshbotDataLink {
    static let schemaModels = GnoshbotSchema.models
}
