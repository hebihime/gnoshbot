import AppIntents

struct GnoshbotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OrderLunchIntent(),
            phrases: [
                "Order lunch with \(.applicationName)",
                "I'm hungry with \(.applicationName)",
            ],
            shortTitle: "Order lunch",
            systemImageName: "fork.knife.circle.fill"
        )
        AppShortcut(
            intent: CheckOrderStatusIntent(),
            phrases: ["Where is my food with \(.applicationName)"],
            shortTitle: "Order status",
            systemImageName: "bag.fill"
        )
        AppShortcut(
            intent: WhereIsItGoingIntent(),
            phrases: ["Where is \(.applicationName) sending lunch"],
            shortTitle: "Delivery address",
            systemImageName: "mappin"
        )
        AppShortcut(
            intent: WhatDidYouOrderIntent(),
            phrases: ["What did \(.applicationName) pick"],
            shortTitle: "What was ordered",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: WhyDidYouPickIntent(),
            phrases: [
                "Why did \(.applicationName) pick that",
                "Why did \(.applicationName) order that",
            ],
            shortTitle: "Why that lunch",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: WhatDidItCostIntent(),
            phrases: ["What did \(.applicationName) spend"],
            shortTitle: "Order cost",
            systemImageName: "dollarsign.circle"
        )
    }
}
