import Foundation

public enum EnsureStatus: String, Equatable, Sendable {
    case ready
    case running
}

public struct EnsureResponse: Equatable, Sendable {
    public var status: EnsureStatus
    public var restaurants: Int?

    public init(status: EnsureStatus, restaurants: Int? = nil) {
        self.status = status
        self.restaurants = restaurants
    }

    public var mappingCopy: String? {
        status == .running ? AddressCopy.mappingKitchens : nil
    }
}

public protocol HTTPPerforming: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPPerforming {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

public struct RegionEnsureClient: Sendable {
    public var settings: ControlPlaneSettings
    public var http: any HTTPPerforming
    public var opaqueUser: String

    public init(settings: ControlPlaneSettings, http: any HTTPPerforming, opaqueUser: String) {
        self.settings = settings
        self.http = http
        self.opaqueUser = opaqueUser
    }

    public func ensureSavedAddress(latitude: Double, longitude: Double) async throws -> EnsureResponse {
        let bbox = RegionBBox.fiveMilesAround(latitude: latitude, longitude: longitude)
        precondition(
            bbox.minLat.isFinite && bbox.minLon.isFinite && bbox.maxLat.isFinite && bbox.maxLon.isFinite
        )
        let geohash5 = bbox.geohash5
        let key = IdempotencyKey.make(
            opaqueUser: opaqueUser,
            geohash5: geohash5,
            release: settings.overtureRelease
        )
        var request = URLRequest(url: settings.baseURL.appending(path: "regions/ensure"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = bbox.jsonBody
        body["reason"] = EnsureReason.savedAddress.rawValue
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await http.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let statusRaw = parsed?["status"] as? String
        if statusCode == 202 || statusRaw == "running" {
            return EnsureResponse(status: .running)
        }
        let count = parsed?["restaurants"] as? Int
        return EnsureResponse(status: .ready, restaurants: count)
    }
}
