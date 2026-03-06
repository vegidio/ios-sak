import Foundation

public actor GraphQLClient {
    private let endpoint: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private var additionalHeaders: [String: String]

    public init(
        endpoint: URL,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        headers: [String: String] = [:]
    ) {
        self.endpoint = endpoint
        self.session = session
        self.decoder = decoder
        self.additionalHeaders = headers
    }

    public func setHeader(_ value: String, forKey key: String) {
        additionalHeaders[key] = value
    }

    public func perform<T: Decodable & Sendable>(_ request: GraphQLRequest) async throws -> GraphQLResponse<T> {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in additionalHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        urlRequest.httpBody = try request.encode()

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try decoder.decode(GraphQLResponse<T>.self, from: data)
    }
}
