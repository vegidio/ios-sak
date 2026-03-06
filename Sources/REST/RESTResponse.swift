import Foundation

public struct RESTResponse<T: Decodable & Sendable>: Sendable {
    public let body: T
    public let urlResponse: HTTPURLResponse

    public var statusCode: Int { urlResponse.statusCode }
    public var headers: [AnyHashable: Any] { urlResponse.allHeaderFields }
}
