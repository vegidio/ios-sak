import Foundation

/// Policy for automatic retry of failed requests.
public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var delay: TimeInterval

    public init(maxAttempts: Int = 3, delay: TimeInterval = 1.0) {
        self.maxAttempts = maxAttempts
        self.delay = delay
    }
}

/// Per-request retry decision layered over the client-wide `retryPolicy`. The `@Service` macro emits
/// `.override`/`.disabled` from the `@Retry`/`@NoRetry` annotations; `.inherit` (the default) falls
/// back to the policy passed to the client init.
public enum RetryOverride: Sendable {
    /// Use the client-level `retryPolicy`.
    case inherit
    /// Disable automatic retry for this request.
    case disabled
    /// Use this policy instead of the client-level one for this request.
    case override(RetryPolicy)
}

/// Internal bundle of settings for `RESTClient`. Not part of the public API — consumers pass
/// these settings directly to a `@Service` client's (or `RESTClient`'s) init.
struct RESTConfiguration: Sendable {
    /// Base URL prepended to relative request paths (e.g. those produced by `@Service`).
    /// Requests whose URL is already absolute (`http`/`https`) are used as-is. `nil` disables it.
    var baseURL: String?

    /// Headers added to every outgoing request. Per-request headers override these.
    var defaultHeaders: [String: String]

    /// Retry policy applied to all failed requests. Set to `nil` to disable retry.
    var retryPolicy: RetryPolicy?

    /// Returns the current access token expiry date, or `nil` if not applicable.
    var tokenExpiryDate: (@Sendable () async -> Date?)?

    /// How many seconds before expiry to proactively refresh the token.
    var preemptiveRefreshLeadTime: TimeInterval

    /// Returns `true` when a response indicates an authentication failure. When `nil`, the engine
    /// falls back to treating HTTP 401 as the auth failure that triggers a refresh.
    var isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)?

    /// Performs the token refresh and returns the new verbatim `Authorization` header value (the
    /// closure owns the scheme, e.g. `"Bearer …"`). Returning the value is required: it is applied
    /// to retry the failed request. When also using `tokenProvider`, the refresher must additionally
    /// write the new value back (awaited) to the source `tokenProvider` reads from.
    var tokenRefresher: (@Sendable () async throws -> String)?

    /// Supplies the current verbatim `Authorization` header value (scheme included), or `nil` for
    /// none. Read on **every** request, so a token kept in a reactive store/variable is always
    /// reflected — update the source and the next request uses the new value.
    var tokenProvider: (@Sendable () async -> String?)?

    /// Resolved auth-failure predicate: `isUnauthorized` when supplied, otherwise the default that
    /// treats HTTP 401 as the auth failure. Single source of truth shared by `RESTClient.send`
    /// (which excludes auth failures from generic retry) and `APIInterceptor.retry` (which refreshes
    /// the token on them) — the two must agree by design.
    var authFailurePredicate: @Sendable (HTTPURLResponse) -> Bool {
        isUnauthorized ?? { $0.statusCode == 401 }
    }

    init(
        baseURL: String? = nil,
        defaultHeaders: [String: String] = [:],
        retryPolicy: RetryPolicy? = RetryPolicy(),
        tokenExpiryDate: (@Sendable () async -> Date?)? = nil,
        preemptiveRefreshLeadTime: TimeInterval = 60,
        isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
        tokenRefresher: (@Sendable () async throws -> String)? = nil,
        tokenProvider: (@Sendable () async -> String?)? = nil
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.retryPolicy = retryPolicy
        self.tokenExpiryDate = tokenExpiryDate
        self.preemptiveRefreshLeadTime = preemptiveRefreshLeadTime
        self.isUnauthorized = isUnauthorized
        self.tokenRefresher = tokenRefresher
        self.tokenProvider = tokenProvider
    }
}
