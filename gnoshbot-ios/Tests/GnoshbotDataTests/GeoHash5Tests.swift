import Foundation
import Testing
@testable import GnoshbotData

@Suite("GeoHash5")
struct GeoHash5Tests {
    @Test("Brooklyn example encodes to dr5rs")
    func brooklyn() {
        #expect(GeoHash5.encode(latitude: 40.6944, longitude: -73.9903) == "dr5rs")
        let box = RegionBBox.fiveMilesAround(latitude: 40.6944, longitude: -73.9903)
        #expect(box.geohash5 == "dr5rs")
        #expect(box.minLat.isFinite && box.maxLon.isFinite)
        #expect(box.minLat < box.maxLat)
        #expect(box.minLon < box.maxLon)
    }
}
