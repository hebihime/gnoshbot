import AppIntents

struct GnoshbotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OrderLunchIntent(),
            phrases: [
                "Tell \(.applicationName) I'm hungry",
                "Ask \(.applicationName) to order lunch",
                "Order lunch with \(.applicationName)",
            ],
            shortTitle: "Order lunch",
            systemImageName: "fork.knife.circle.fill"
        )
        AppShortcut(
            intent: CheckOrderStatusIntent(),
            phrases: ["Ask \(.applicationName) where my food is"],
            shortTitle: "Order status",
            systemImageName: "bag.fill"
        )
        AppShortcut(
            intent: WhereIsItGoingIntent(),
            phrases: ["Ask \(.applicationName) where it's going"],
            shortTitle: "Delivery address",
            systemImageName: "mappin"
        )
        AppShortcut(
            intent: WhatDidYouOrderIntent(),
            phrases: ["Ask \(.applicationName) what it picked"],
            shortTitle: "What was ordered",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: WhatDidItCostIntent(),
            phrases: ["Ask \(.applicationName) what the damage was"],
            shortTitle: "Order cost",
            systemImageName: "dollarsign.circle"
        )
    }
}
