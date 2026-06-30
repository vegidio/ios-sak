import Alamofire
import Foundation

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

    /// Status codes for which an empty response body is allowed. Constant, so it's built once rather
    /// than per retry attempt. Empty bodies are permitted for every code so a no-content success
    /// (e.g. 204) isn't a serialization failure; empty success bodies resolve to `EmptyResponse`.
    private static let emptyResponseCodes = Set(100 ... 599)

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

        session = Session(configuration: sessionConfig, interceptor: interceptor, eventMonitors: eventMonitors)
        self.configuration = configuration
        cache = ResponseCache(maxEntries: maxEntries)
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
    ///   - retry: Per-request retry decision layered over the client-wide `retryPolicy`. Defaults to
    ///     `.inherit`. Only idempotent methods (GET/PUT/DELETE) are ever retried.
    public func send<T: Decodable & Sendable>(
        _ request: RESTRequest,
        cacheable: Bool = false,
        ttl: TimeInterval? = nil,
        retry: RetryOverride = .inherit
    ) async throws -> RESTResponse<T> {
        var request = request
        request.url = Self.resolveURL(request.url, baseURL: configuration.baseURL)

        // Only GET responses are cached. Caching non-GET requests is unsafe here because the cache
        // key is derived from URL + query parameters only (it ignores the HTTP method and body), so
        // mutating requests could return stale entries or collide on differing bodies.
        let isCacheable = cacheable && request.method == .get
        let cacheKey = isCacheable ? ResponseCache.makeKey(url: request.url, queryParams: request.queryParameters) : nil

        if let cacheKey, let cached: RESTResponse<T> = try await cachedResponse(T.self, forKey: cacheKey) {
            return cached
        }

        let urlRequest: URLRequest
        do {
            urlRequest = try request.buildURLRequest()
        } catch {
            throw RESTError.invalidURL
        }

        let retryPolicy = effectiveRetryPolicy(for: retry)

        // Generic retry loop for transport/server failures, bounded by the effective policy and
        // limited to idempotent methods (retrying POST/PATCH could duplicate a side effect). Auth
        // (401) failures are excluded here: the interceptor already refreshes + retries them once,
        // so a still-failing auth response is fatal rather than hammered by the generic loop.
        var attempt = 0
        while true {
            // Use Alamofire but manage validation manually to capture raw Data on errors. The raw
            // `response.data` is still captured for error reporting (see `emptyResponseCodes`).
            let response = await session.request(urlRequest)
                .validate()
                .serializingData(emptyResponseCodes: Self.emptyResponseCodes)
                .response

            if let afError = response.error {
                if shouldRetry(method: request.method, http: response.response, attempt: attempt, policy: retryPolicy) {
                    attempt += 1
                    let nanoseconds = UInt64(max(0, retryPolicy?.delay ?? 0) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    continue
                }
                throw translateAFError(afError, data: response.data ?? Data())
            }

            return try await finalize(T.self, response: response, cacheKey: cacheKey, ttl: ttl)
        }
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

    /// Returns the decoded cached response for `cacheKey`, or `nil` when nothing is cached.
    private func cachedResponse<T: Decodable & Sendable>(
        _: T.Type,
        forKey cacheKey: String
    ) async throws -> RESTResponse<T>? {
        guard let entry = await cache.retrieve(forKey: cacheKey) else { return nil }
        let body = try decodeBody(T.self, from: entry.data)
        return RESTResponse(body: body, urlResponse: entry.httpResponse)
    }

    /// Resolves the effective retry policy: a per-request override wins over the client-wide one.
    private func effectiveRetryPolicy(for retry: RetryOverride) -> RetryPolicy? {
        switch retry {
        case .inherit: configuration.retryPolicy
        case .disabled: nil
        case let .override(policy): policy
        }
    }

    /// Whether a failed attempt should be retried: policy allows another attempt, the method is
    /// idempotent, and the failure is not an auth (401) failure (those are handled by the interceptor).
    private func shouldRetry(
        method: HTTPMethod,
        http: HTTPURLResponse?,
        attempt: Int,
        policy: RetryPolicy?
    ) -> Bool {
        guard let policy, attempt < policy.maxAttempts else { return false }
        guard HTTPMethod.idempotentMethods.contains(method) else { return false }
        let isAuth = http.map(configuration.authFailurePredicate) ?? false
        return !isAuth
    }

    /// Validates a successful response, decodes its body as `T`, and caches it when `cacheKey` is set.
    private func finalize<T: Decodable & Sendable>(
        _: T.Type,
        response: AFDataResponse<Data>,
        cacheKey: String?,
        ttl: TimeInterval?
    ) async throws -> RESTResponse<T> {
        guard let httpResponse = response.response else {
            throw RESTError.network(URLError(.badServerResponse))
        }
        let data = response.data ?? Data()
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw RESTError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
        let body = try decodeBody(T.self, from: data)
        if let cacheKey {
            await cache.store(data, httpResponse: httpResponse, forKey: cacheKey, ttl: ttl)
        }
        return RESTResponse(body: body, urlResponse: httpResponse)
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
        case let .sessionTaskFailed(underlying):
            return .network(underlying)
        case let .responseValidationFailed(reason):
            if case let .unacceptableStatusCode(code) = reason {
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
