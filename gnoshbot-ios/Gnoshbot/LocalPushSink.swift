import GnoshbotData
import UserNotifications

struct LocalPushSink: SettlementNotifying {
    func notify(_ copy: PushCopy) async {
        let content = UNMutableNotificationContent()
        content.body = copy.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "gnoshbot." + UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
