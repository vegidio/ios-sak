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
    private let configuration: APIConfiguration
    let coordinator: TokenRefreshCoordinator

    init(configuration: APIConfiguration) {
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
        if request.value(forHTTPHeaderField: "X-Skip-Auth") == "1" {
            request.setValue(nil, forHTTPHeaderField: "X-Skip-Auth")
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
        guard let applyToken = configuration.applyToken else {
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
                   let expiry = expiryProvider(),
                   expiry.timeIntervalSinceNow < configuration.preemptiveRefreshLeadTime,
                   let refreshHandler = configuration.refreshToken {
                    _ = try await coordinator.refresh(using: refreshHandler)
                }

                if let token = await coordinator.currentToken {
                    applyToken(token, &req)
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
        guard
            let retryPolicy = configuration.retryPolicy,
            request.retryCount < retryPolicy.maxAttempts
        else {
            completion(.doNotRetryWithError(error))
            return
        }

        // Check for auth failure — refresh token then retry
        if let isUnauthorized = configuration.isUnauthorized,
           let httpResponse = request.response,
           isUnauthorized(httpResponse),
           let refreshHandler = configuration.refreshToken {
            let completionBox = Box(value: completion)
            Task {
                do {
                    _ = try await coordinator.refresh(using: refreshHandler)
                    completionBox.value(.retryWithDelay(retryPolicy.delay))
                } catch {
                    completionBox.value(.doNotRetryWithError(error))
                }
            }
            return
        }

        // Retry other failures (network errors, server errors, etc.)
        completion(.retryWithDelay(retryPolicy.delay))
    }
}
