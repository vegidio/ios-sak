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
            return true
        case (.network, .network):
            return true
        case let (.httpError(lCode, lData), .httpError(rCode, rData)):
            return lCode == rCode && lData == rData
        case (.decodingError, .decodingError):
            return true
        default:
            return false
        }
    }
}
