import Foundation
import Alamofire

// MARK: - TokenRefreshCoordinator

/// Coalesces concurrent token refresh calls: only the first caller hits the network;
/// all others await the same Task and receive the same result.
actor TokenRefreshCoordinator {
    private(set) var currentToken: String?
    private var ongoingRefresh: Task<String, Error>?

    func refresh(using handler: @escaping @Sendable () async throws -> String) async throws -> String {
        if let existing = ongoingRefresh {
            return try await existing.value
        }
        let task = Task<String, Error> { try await handler() }
        ongoingRefresh = task
        do {
            let token = try await task.value
            currentToken = token
            ongoingRefresh = nil
            return token
        } catch {
            ongoingRefresh = nil
            throw error
        }
    }
}

// MARK: - Helpers

/// Wraps a non-Sendable value in an @unchecked Sendable box so it can be safely
/// captured by Task closures. Used to bridge Alamofire's callback-based APIs with
/// Swift 6 strict concurrency (Alamofire guarantees each callback is called exactly once).
private struct Box<T>: @unchecked Sendable {
    var value: T
}

// MARK: - APIInterceptor

final class APIInterceptor: RequestInterceptor, @unchecked Sendable {
    private let configuration: RESTConfiguration
    let coordinator: TokenRefreshCoordinator

    init(configuration: RESTConfiguration) {
        self.configuration = configuration
        self.coordinator = TokenRefreshCoordinator()
    }

    // MARK: RequestAdapter

    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping (Result<URLRequest, Error>) -> Void
    ) {
        var request = urlRequest

        // If skipAuth sentinel is present, strip it and skip all auth logic
        if request.value(forHTTPHeaderField: AuthSentinel.header) == AuthSentinel.value {
            request.setValue(nil, forHTTPHeaderField: AuthSentinel.header)
            for (key, value) in configuration.defaultHeaders where request.value(forHTTPHeaderField: key) == nil {
                request.setValue(value, forHTTPHeaderField: key)
            }
            completion(.success(request))
            return
        }

        // Inject default headers (per-request headers already present take priority)
        for (key, value) in configuration.defaultHeaders where request.value(forHTTPHeaderField: key) == nil {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // If no token injection configured, nothing more to do
        guard configuration.tokenProvider != nil || configuration.tokenRefresher != nil else {
            completion(.success(request))
            return
        }

        // Box the non-Sendable callback and URLRequest for safe capture in the Task
        let completionBox = Box(value: completion)
        let requestBox = Box(value: request)

        Task {
            var req = requestBox.value
            do {
                // Preemptive refresh: if token is about to expire, refresh before sending
                if let expiryProvider = configuration.tokenExpiryDate,
                   let expiry = await expiryProvider(),
                   expiry.timeIntervalSinceNow < configuration.preemptiveRefreshLeadTime,
                   let refreshHandler = configuration.tokenRefresher {
                    _ = try await coordinator.refresh(using: refreshHandler)
                }

                // Resolve the token: read `tokenProvider` live on every request (reactive), or fall
                // back to the last refreshed token in refresher-only mode. The value is written to
                // the Authorization header verbatim — the closures own the scheme (e.g. "Bearer …").
                let token: String?
                if let provider = configuration.tokenProvider {
                    token = await provider()
                } else {
                    token = await coordinator.currentToken
                }

                if let token {
                    req.setValue(token, forHTTPHeaderField: "Authorization")
                }
                completionBox.value(.success(req))
            } catch {
                completionBox.value(.failure(error))
            }
        }
    }

    // MARK: RequestRetrier

    func retry(
        _ request: Request,
        for session: Session,
        dueTo error: Error,
        completion: @escaping (RetryResult) -> Void
    ) {
        // Auth failure handling. Defaults to treating HTTP 401 as the auth failure when no
        // `isUnauthorized` predicate is supplied (mirrors the TS library's `refreshOn: [401]`).
        let isAuthFailure = configuration.authFailurePredicate
        if let httpResponse = request.response, isAuthFailure(httpResponse) {
            // Refresh + retry exactly once. A still-failing auth response is fatal — we never fall
            // through to the generic retry, so the refresh endpoint isn't hammered on a persistent
            // 401. Independent of `retryPolicy`, so auth refresh works even when retry is disabled.
            guard request.retryCount == 0, let refreshHandler = configuration.tokenRefresher else {
                completion(.doNotRetryWithError(error))
                return
            }
            let completionBox = Box(value: completion)
            Task {
                do {
                    _ = try await coordinator.refresh(using: refreshHandler)
                    completionBox.value(.retryWithDelay(configuration.retryPolicy?.delay ?? 0))
                } catch {
                    completionBox.value(.doNotRetryWithError(error))
                }
            }
            return
        }

        // Generic retry (transport/server failures) is handled by `RESTClient.send`, which owns the
        // effective per-request retry policy. The interceptor only drives the auth-refresh retry.
        completion(.doNotRetryWithError(error))
    }
}
