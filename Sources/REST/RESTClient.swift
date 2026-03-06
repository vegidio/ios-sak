import Foundation

public actor RESTClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func send<T: Decodable & Sendable>(_ request: RESTRequest) async throws -> RESTResponse<T> {
        let urlRequest: URLRequest
        do {
            urlRequest = try request.buildURLRequest()
        } catch {
            throw RESTError.invalidURL
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw RESTError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RESTError.network(URLError(.badServerResponse))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RESTError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        do {
            let body = try decoder.decode(T.self, from: data)
            return RESTResponse(body: body, urlResponse: httpResponse)
        } catch {
            throw RESTError.decodingError(error)
        }
    }
}
