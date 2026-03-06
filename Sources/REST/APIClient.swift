import Foundation
import Alamofire

/// A high-level HTTP client built on Alamofire that provides automatic retry,
/// TTL-based response caching, default headers, and token refresh workflows.
///
/// Create one `APIClient` per API domain (typically at app startup) and reuse it:
/// ```swift
/// let client = APIClient(configuration: APIConfiguration(
///     defaultHeaders: ["X-API-Version": "2"],
///     retryPolicy: RetryPolicy(maxAttempts: 3),
///     cachePolicy: CachePolicy(ttl: 300),
///     isUnauthorized: { $0.statusCode == 401 },
///     refreshToken: { try await authStore.refresh() },
///     applyToken: { token, req in req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") },
///     tokenExpiryDate: { authStore.expiry }
/// ))
/// ```
public actor APIClient {
    private let session: Session
    private let configuration: APIConfiguration
    private let cache: ResponseCache?
    private let decoder: JSONDecoder

    public init(configuration: APIConfiguration, decoder: JSONDecoder = JSONDecoder()) {
        let interceptor = APIInterceptor(configuration: configuration)
        self.session = Session(interceptor: interceptor)
        self.configuration = configuration
        self.cache = configuration.cachePolicy != nil ? ResponseCache() : nil
        self.decoder = decoder
    }

    /// Sends a request and decodes the response body as `T`.
    ///
    /// - Parameters:
    ///   - request: The REST request descriptor.
    ///   - cacheable: When `true` and a `CachePolicy` is configured, the response is read from
    ///     and written to the in-memory cache. Defaults to `false`.
    public func send<T: Decodable & Sendable>(
        _ request: RESTRequest,
        cacheable: Bool = false
    ) async throws -> RESTResponse<T> {
        let cacheKey = makeCacheKey(url: request.url, queryParams: request.queryParameters)

        // Return cached response if available and not expired
        if cacheable, let cache {
            if let entry = await cache.retrieve(forKey: cacheKey) {
                let body = try decodeOrThrow(T.self, from: entry.data)
                return RESTResponse(body: body, urlResponse: entry.httpResponse)
            }
        }

        let urlRequest: URLRequest
        do {
            urlRequest = try request.buildURLRequest()
        } catch {
            throw RESTError.invalidURL
        }

        // Use Alamofire but manage validation manually to capture raw Data on errors
        let dataTask = session.request(urlRequest).serializingData(emptyResponseCodes: [])
        let response = await dataTask.response

        // Surface network-level errors
        if let afError = response.error {
            throw translateAFError(afError, data: response.data ?? Data())
        }

        guard let httpResponse = response.response else {
            throw RESTError.network(URLError(.badServerResponse))
        }

        let data = response.data ?? Data()

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RESTError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        let body = try decodeOrThrow(T.self, from: data)

        // Store successful response in cache
        if cacheable, let cache, let ttl = configuration.cachePolicy?.ttl {
            await cache.store(data, httpResponse: httpResponse, forKey: cacheKey, ttl: ttl)
        }

        return RESTResponse(body: body, urlResponse: httpResponse)
    }

    // MARK: - Private helpers

    private func decodeOrThrow<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw RESTError.decodingError(error)
        }
    }

    private func translateAFError(_ error: AFError, data: Data) -> RESTError {
        switch error {
        case .invalidURL:
            return .invalidURL
        case .sessionTaskFailed(let underlying):
            return .network(underlying)
        case .responseValidationFailed(let reason):
            if case .unacceptableStatusCode(let code) = reason {
                return .httpError(statusCode: code, data: data)
            }
            return .network(error)
        case .responseSerializationFailed:
            return .decodingError(error)
        default:
            return .network(error)
        }
    }
}
