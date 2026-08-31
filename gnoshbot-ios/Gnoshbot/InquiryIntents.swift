import AppIntents
import GnoshbotData

struct CheckOrderStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check order status"
    static var openAppWhenRun: Bool { false }
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let row = try GnoshbotStore.shared.latestOrder()
        guard let row else {
            return .result(dialog: IntentDialog(stringLiteral: InquirySpeech.noActiveOrder))
        }
        return .result(dialog: IntentDialog(stringLiteral: InquirySpeech.status(row)))
    }
}

struct WhereIsItGoingIntent: AppIntent {
    static let title: LocalizedStringResource = "Where is it going"
    static var openAppWhenRun: Bool { false }
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let row = try GnoshbotStore.shared.latestOrder()
        guard let row else {
            return .result(dialog: IntentDialog(stringLiteral: InquirySpeech.noActiveOrder))
        }
        return .result(dialog: IntentDialog(stringLiteral: InquirySpeech.destination(row)))
    }
}

struct WhatDidYouOrderIntent: AppIntent {
    static let title: LocalizedStringResource = "What did you order"
    static var openAppWhenRun: Bool { false }
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let row = try GnoshbotStore.shared.latestOrder()
        guard let row else {
            return .result(dialog: IntentDialog(stringLiteral: InquirySpeech.noActiveOrder))
        }
        return .result(dialog: IntentDialog(stringLiteral: InquirySpeech.ordered(row)))
    }
}

struct WhatDidItCostIntent: AppIntent {
    static let title: LocalizedStringResource = "What did it cost"
    static var openAppWhenRun: Bool { false }
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let row = try GnoshbotStore.shared.latestOrder()
        guard let row else {
            return .result(dialog: IntentDialog(stringLiteral: InquirySpeech.noActiveOrder))
        }
        return .result(dialog: IntentDialog(stringLiteral: InquirySpeech.cost(row)))
    }
}
