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
    private let cache: ResponseCache
    private let decoder: JSONDecoder

    public init(
        baseURL: String,
        defaultHeaders: [String: String] = [:],
        retryPolicy: RetryPolicy? = RetryPolicy(),
        maxEntries: Int? = nil,
        tokenExpiryDate: (@Sendable () async -> Date?)? = nil,
        preemptiveRefreshLeadTime: TimeInterval = 60,
        isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
        tokenRefresher: (@Sendable () async throws -> String)? = nil,
        tokenProvider: (@Sendable () async -> String?)? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        sessionConfiguration: URLSessionConfiguration? = nil,
        logging: LoggingPolicy? = nil
    ) {
        let configuration = RESTConfiguration(
            baseURL: baseURL,
            defaultHeaders: defaultHeaders,
            retryPolicy: retryPolicy,
            tokenExpiryDate: tokenExpiryDate,
            preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
            isUnauthorized: isUnauthorized,
            tokenRefresher: tokenRefresher,
            tokenProvider: tokenProvider
        )
        let sessionConfig = sessionConfiguration ?? URLSessionConfiguration.af.default
        let interceptor = APIInterceptor(configuration: configuration)

        // Logging is wired purely at the Session layer via an Alamofire EventMonitor, so it never
        // touches the request/response hot path. The monitor logs the adapted request (Authorization
        // header injected by APIInterceptor) once per attempt and the final parsed response.
        var eventMonitors: [any EventMonitor] = [AlamofireNotifications()]
        if let logging {
            eventMonitors.append(LoggingEventMonitor(logging: logging))
        }

        self.session = Session(configuration: sessionConfig, interceptor: interceptor, eventMonitors: eventMonitors)
        self.configuration = configuration
        self.cache = ResponseCache(maxEntries: maxEntries)
        self.decoder = decoder
    }

    /// Sends a request and decodes the response body as `T`.
    ///
    /// - Parameters:
    ///   - request: The REST request descriptor.
    ///   - cacheable: When `true`, the response is read from and written to the in-memory cache.
    ///     Defaults to `false`.
    ///   - ttl: How long a cached response stays valid, in seconds. `nil` means the entry never
    ///     expires (it is kept until evicted by the cache's `maxEntries` limit). Ignored when
    ///     `cacheable` is `false`.
    public func send<T: Decodable & Sendable>(
        _ request: RESTRequest,
        cacheable: Bool = false,
        ttl: TimeInterval? = nil
    ) async throws -> RESTResponse<T> {
        var request = request
        request.url = Self.resolveURL(request.url, baseURL: configuration.baseURL)

        // Only GET responses are cached. Caching non-GET requests is unsafe here because the cache
        // key is derived from URL + query parameters only (it ignores the HTTP method and body), so
        // mutating requests could return stale entries or collide on differing bodies.
        let isCacheable = cacheable && request.method == .get
        let cacheKey = isCacheable ? ResponseCache.makeKey(url: request.url, queryParams: request.queryParameters) : nil

        // Return cached response if available and not expired
        if isCacheable, let cacheKey {
            if let entry = await cache.retrieve(forKey: cacheKey) {
                let body = try decodeBody(T.self, from: entry.data)
                return RESTResponse(body: body, urlResponse: entry.httpResponse)
            }
        }

        let urlRequest: URLRequest
        do {
            urlRequest = try request.buildURLRequest()
        } catch {
            throw RESTError.invalidURL
        }

        // Use Alamofire but manage validation manually to capture raw Data on errors. Empty bodies
        // are allowed for every status code so a no-content success (e.g. 204) is not treated as a
        // serialization failure; the raw `response.data` is still captured for error reporting, and
        // empty success bodies resolve to `EmptyResponse` in `decodeBody`.
        let dataTask = session.request(urlRequest)
            .validate()
            .serializingData(emptyResponseCodes: Set(100...599))
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

        let body = try decodeBody(T.self, from: data)

        // Store successful response in cache
        if isCacheable, let cacheKey {
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

    /// Decodes the response body as `T`, short-circuiting empty bodies (e.g. 204/205 No Content)
    /// to `EmptyResponse` so no-body endpoints don't fail the JSON decoder on empty input.
    private func decodeBody<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }
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
