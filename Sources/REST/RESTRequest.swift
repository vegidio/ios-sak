import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    /// Methods safe to retry after a transport/server failure without risking a duplicated side
    /// effect (per RFC 7231 idempotency). Used by `APIInterceptor` to gate automatic retries.
    static let idempotentMethods: Set<HTTPMethod> = [.get, .put, .delete]
}

/// Internal sentinel used to flag a request that should bypass automatic token injection.
/// `RESTRequest.buildURLRequest` sets the header; `APIInterceptor.adapt` reads and strips it.
/// Centralized here so the request builder and the interceptor can never drift apart.
enum AuthSentinel {
    static let header = "X-Skip-Auth"
    static let value = "1"
}

public struct RESTRequest: Sendable {
    public var url: String
    public var method: HTTPMethod
    public var headers: [String: String]
    public var body: Data?
    public var queryParameters: [String: String]
    public var skipAuth: Bool

    public init(
        url: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        queryParameters: [String: String] = [:],
        skipAuth: Bool = false
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.queryParameters = queryParameters
        self.skipAuth = skipAuth
    }

    func buildURLRequest() throws -> URLRequest {
        guard var components = URLComponents(string: url) else {
            throw RESTError.invalidURL
        }

        if !queryParameters.isEmpty {
            components.queryItems = queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let resolvedURL = components.url else {
            throw RESTError.invalidURL
        }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method.rawValue
        request.httpBody = body

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if skipAuth {
            request.setValue(AuthSentinel.value, forHTTPHeaderField: AuthSentinel.header)
        }

        return request
    }
}

public extension RESTRequest {
    /// Creates a request with an `Encodable` body, automatically JSON-encoding it
    /// and setting `Content-Type: application/json` unless already provided.
    init<B: Encodable>(
        url: String,
        method: HTTPMethod = .post,
        headers: [String: String] = [:],
        body encodable: B,
        encoder: JSONEncoder = JSONEncoder(),
        queryParameters: [String: String] = [:],
        skipAuth: Bool = false
    ) throws {
        let data = try encoder.encode(encodable)
        var merged = headers
        if merged["Content-Type"] == nil {
            merged["Content-Type"] = "application/json"
        }
        self.init(
            url: url,
            method: method,
            headers: merged,
            body: data as Data?,
            queryParameters: queryParameters,
            skipAuth: skipAuth
        )
    }
}
