import Foundation

/// Background `URLSession` identity for settlement (I14). `Task.detached` is not a scheduler.
public enum SettlementSession {
    public static let identifier = "com.gnoshbot.settlement"

    public static func makeBackgroundConfiguration() -> URLSessionConfiguration {
        let cfg = URLSessionConfiguration.background(withIdentifier: identifier)
        cfg.sessionSendsLaunchEvents = true
        cfg.waitsForConnectivity = true
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        return cfg
    }
}
