import Foundation
import Testing
@testable import GnoshbotData

struct ScriptedHTTP: HTTPPerforming, Sendable {
    var handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try handler(request)
        return (data, response)
    }
}

enum TestHTTP {
    static func json(_ object: Any, status: Int, url: URL, headers: [String: String] = [:]) throws -> (Data, HTTPURLResponse) {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (data, response)
    }
}
