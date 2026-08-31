import Foundation

/// Precision-5 geohash matching `ngeohash.encode(lat, lon, 5)` on the control plane.
public enum GeoHash5 {
    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    public static func encode(latitude: Double, longitude: Double) -> String {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bit = 0
        var ch = 0
        var even = true
        while hash.count < 5 {
            if even {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid {
                    ch = ch * 2 + 1
                    lonRange.0 = mid
                } else {
                    ch = ch * 2
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid {
                    ch = ch * 2 + 1
                    latRange.0 = mid
                } else {
                    ch = ch * 2
                    latRange.1 = mid
                }
            }
            even.toggle()
            bit += 1
            if bit == 5 {
                hash.append(alphabet[ch])
                bit = 0
                ch = 0
            }
        }
        return hash
    }

    /// Approximate tile center (ngeohash decode). Used when GET /regions omits POI coordinates.
    public static func decodeCenter(_ hash: String) -> (latitude: Double, longitude: Double) {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var even = true
        for character in hash.lowercased() {
            guard let idx = alphabet.firstIndex(of: character) else { continue }
            for shift in stride(from: 4, through: 0, by: -1) {
                let bitOn = (idx >> shift) & 1 == 1
                if even {
                    let mid = (lonRange.0 + lonRange.1) / 2
                    if bitOn { lonRange.0 = mid } else { lonRange.1 = mid }
                } else {
                    let mid = (latRange.0 + latRange.1) / 2
                    if bitOn { latRange.0 = mid } else { latRange.1 = mid }
                }
                even.toggle()
            }
        }
        return ((latRange.0 + latRange.1) / 2, (lonRange.0 + lonRange.1) / 2)
    }
}
