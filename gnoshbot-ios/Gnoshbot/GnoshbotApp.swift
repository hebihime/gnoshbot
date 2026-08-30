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
            container = built
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }

    /// SwiftData lives in the application process and `group.bot.gnosh`.
    /// App Intents have no widget / App Intents extension target, so they run here.
    /// `ExecutionTargets` is not in the iOS 26.2 SDK; I4 must still keep intents in this target.
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

private struct ContentView: View {
    var body: some View {
        Text("Gnoshbot")
            .accessibilityIdentifier("gnoshbot.root")
    }
}

/// Forces a compile-time link to `GnoshbotData` without opening a store (I1).
enum GnoshbotDataLink {
    static let schemaModels = GnoshbotSchema.models
}
