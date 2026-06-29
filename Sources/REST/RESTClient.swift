import Foundation
import Alamofire

/// The HTTP engine built on Alamofire that powers `@Service` clients, providing automatic
/// retry, TTL-based response caching, default headers, and token refresh workflows.
///
/// You normally do not construct this type directly: declare an API with `@Service` and create
/// the generated `<Name>Client`, which owns its own `RESTClient` internally.
public actor RESTClient {
    private let session: Session
    private let configuration: RESTConfiguration
    private let cache: ResponseCache?
    private let decoder: JSONDecoder

    public init(
        baseURL: String,
        defaultHeaders: [String: String] = [:],
        retryPolicy: RetryPolicy? = RetryPolicy(),
        cachePolicy: CachePolicy? = nil,
        tokenExpiryDate: (@Sendable () -> Date?)? = nil,
        preemptiveRefreshLeadTime: TimeInterval = 60,
        isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
        refreshToken: (@Sendable () async throws -> String)? = nil,
        applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
        getToken: (@Sendable () -> String?)? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        sessionConfiguration: URLSessionConfiguration? = nil
    ) {
        let configuration = RESTConfiguration(
            baseURL: baseURL,
            defaultHeaders: defaultHeaders,
            retryPolicy: retryPolicy,
            cachePolicy: cachePolicy,
            tokenExpiryDate: tokenExpiryDate,
            preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
            isUnauthorized: isUnauthorized,
            refreshToken: refreshToken,
            applyToken: applyToken,
            getToken: getToken
        )
        let sessionConfig = sessionConfiguration ?? URLSessionConfiguration.af.default
        let interceptor = APIInterceptor(configuration: configuration)
        self.session = Session(configuration: sessionConfig, interceptor: interceptor)
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
        var request = request
        request.url = Self.resolveURL(request.url, baseURL: configuration.baseURL)

        let cacheKey = ResponseCache.makeKey(url: request.url, queryParams: request.queryParameters)

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
        let dataTask = session.request(urlRequest)
            .validate()
            .serializingData(emptyResponseCodes: [])
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

    /// Resolves a request URL against a base URL. Absolute URLs (`http`/`https`) are returned
    /// as-is; relative paths are joined to the base URL, collapsing any duplicated slash at the seam.
    static func resolveURL(_ url: String, baseURL: String?) -> String {
        let lowered = url.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return url
        }
        guard let base = baseURL, !base.isEmpty else {
            return url
        }
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let trimmedPath = url.hasPrefix("/") ? String(url.dropFirst()) : url
        return "\(trimmedBase)/\(trimmedPath)"
    }

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
