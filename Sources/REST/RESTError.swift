import Foundation

public enum RESTError: Error, Sendable {
    case invalidURL
    case network(Error)
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)
}
