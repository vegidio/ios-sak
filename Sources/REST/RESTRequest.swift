import Foundation

public struct RESTRequest: Sendable {
    public var url: String
    public var method: HTTPMethod
    public var headers: [String: String]
    public var body: Data?
    public var queryParameters: [String: String]

    public init(
        url: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        queryParameters: [String: String] = [:]
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.queryParameters = queryParameters
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

        return request
    }
}
