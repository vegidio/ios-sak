import Foundation

public enum RESTError: Error, Sendable {
    case invalidURL
    case network(Error)
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)
}

extension RESTError: Equatable {
    public static func == (lhs: RESTError, rhs: RESTError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL):
            true
        case (.network, .network):
            true
        case let (.httpError(lCode, lData), .httpError(rCode, rData)):
            lCode == rCode && lData == rData
        case (.decodingError, .decodingError):
            true
        default:
            false
        }
    }
}
