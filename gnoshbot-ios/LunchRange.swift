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
        isWithinFiveMiles(
            latitude: latitude,
            longitude: longitude,
            centerLatitude: location.latitude,
            centerLongitude: location.longitude
        )
    }

    public static func isWithinFiveMiles(
        latitude: Double,
        longitude: Double,
        centerLatitude: Double,
        centerLongitude: Double
    ) -> Bool {
        let kitchen = CLLocation(latitude: latitude, longitude: longitude)
        let drop = CLLocation(latitude: centerLatitude, longitude: centerLongitude)
        return kitchen.distance(from: drop) <= meters
    }
}
