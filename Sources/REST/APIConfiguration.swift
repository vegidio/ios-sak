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

/// Policy for TTL-based in-memory response caching.
public struct CachePolicy: Sendable {
    public var ttl: TimeInterval

    public init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }
}

/// All configuration for `APIClient`.
public struct APIConfiguration: Sendable {
    /// Headers added to every outgoing request. Per-request headers override these.
    public var defaultHeaders: [String: String]

    /// Retry policy applied to all failed requests. Set to `nil` to disable retry.
    public var retryPolicy: RetryPolicy?

    /// Cache policy for responses marked `cacheable`. Set to `nil` to disable caching.
    public var cachePolicy: CachePolicy?

    /// Returns the current access token expiry date, or `nil` if not applicable.
    public var tokenExpiryDate: (@Sendable () -> Date?)?

    /// How many seconds before expiry to proactively refresh the token.
    public var preemptiveRefreshLeadTime: TimeInterval

    /// Returns `true` when a response indicates an authentication failure (e.g. 401).
    public var isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)?

    /// Performs the token refresh and returns the new access token string.
    public var refreshToken: (@Sendable () async throws -> String)?

    /// Applies the access token to an outgoing `URLRequest` (e.g. sets the Authorization header).
    public var applyToken: (@Sendable (String, inout URLRequest) -> Void)?

    public init(
        defaultHeaders: [String: String] = [:],
        retryPolicy: RetryPolicy? = RetryPolicy(),
        cachePolicy: CachePolicy? = nil,
        tokenExpiryDate: (@Sendable () -> Date?)? = nil,
        preemptiveRefreshLeadTime: TimeInterval = 60,
        isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
        refreshToken: (@Sendable () async throws -> String)? = nil,
        applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil
    ) {
        self.defaultHeaders = defaultHeaders
        self.retryPolicy = retryPolicy
        self.cachePolicy = cachePolicy
        self.tokenExpiryDate = tokenExpiryDate
        self.preemptiveRefreshLeadTime = preemptiveRefreshLeadTime
        self.isUnauthorized = isUnauthorized
        self.refreshToken = refreshToken
        self.applyToken = applyToken
    }
}
