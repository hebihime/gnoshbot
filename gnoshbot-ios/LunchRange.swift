import CoreLocation
import Foundation

public enum LunchRange {
    /// 5 miles in meters (`plans/ios.md` I7).
    public static let meters: CLLocationDistance = 8046.72

    public static func isWithinFiveMiles(
        latitude: Double,
        longitude: Double,
        of location: DeliveryLocation
    ) -> Bool {
        let kitchen = CLLocation(latitude: latitude, longitude: longitude)
        let drop = CLLocation(latitude: location.latitude, longitude: location.longitude)
        return kitchen.distance(from: drop) <= meters
    }
}
