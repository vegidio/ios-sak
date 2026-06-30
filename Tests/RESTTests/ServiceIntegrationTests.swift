import Testing
import Foundation
@testable import REST

// MARK: - Models

private struct User: Codable, Sendable, Equatable {
    let id: Int
    let name: String
}

private struct NewUser: Encodable, Sendable {
    let name: String
}

// MARK: - Annotated service

@Service
private protocol UserService {
    @Get("users/{id}")
    func getUser(id: Path<Int>) async throws -> User

    @Get("users")
    func listUsers(page: Query<Int>) async throws -> [User]

    @Post("users")
    func createUser(user: Body<NewUser>) async throws -> User

    @Get("public/config")
    @SkipAuth
    func config() async throws -> [String: String]
}

// Service-wide caching, with one method opting out via @NoCache.
@Service
@Cacheable(ttl: 300)
private protocol CachedService {
    @Get("users/{id}")
    func getUser(id: Path<Int>) async throws -> User

    @Get("health")
    @NoCache
    func health() async throws -> [String: String]

    // Service-wide @Cacheable applies here too, but the engine only caches GET — so two POSTs
    // must both reach the network (see `cacheableNeverCachesNonGet`).
    @Post("users")
    func createUser(user: Body<NewUser>) async throws -> User
}

// For retry-idempotency tests.
@Service
private protocol RetryService {
    @Get("flaky")
    func flakyGet() async throws -> [String: String]

    @Post("submit")
    func submit(payload: Body<NewUser>) async throws -> [String: String]
}

// For empty-body (204 No Content) tests. No return type — the generated method is
// @discardableResult and returns RESTResponse<EmptyResponse>, so callers can ignore it or read
// the response metadata.
@Service
private protocol EmptyBodyService {
    @Delete("users/{id}")
    func deleteUser(id: Path<Int>) async throws
}

@Suite("@Service generated client", .serialized)
struct ServiceIntegrationTests {

    private func makeService(baseURL: String, withAuth: Bool = false) -> UserServiceClient {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]

        var tokenProvider: (@Sendable () async -> String?)?
        if withAuth {
            tokenProvider = { "Bearer tok123" }
        }

        return UserServiceClient(
            baseURL: baseURL,
            tokenProvider: tokenProvider,
            sessionConfiguration: sessionConfig
        )
    }

    private func makeCachedService(baseURL: String) -> CachedServiceClient {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]
        return CachedServiceClient(baseURL: baseURL, sessionConfiguration: sessionConfig)
    }

    private func makeRetryService(baseURL: String) -> RetryServiceClient {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]
        // delay 0 keeps the test fast; maxAttempts 2 → one initial try + two retries = 3 requests.
        return RetryServiceClient(
            baseURL: baseURL,
            retryPolicy: RetryPolicy(maxAttempts: 2, delay: 0),
            sessionConfiguration: sessionConfig
        )
    }

    private func makeEmptyBodyService(baseURL: String) -> EmptyBodyServiceClient {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]
        return EmptyBodyServiceClient(baseURL: baseURL, sessionConfiguration: sessionConfig)
    }

    @Test("GET with a Path parameter hits the substituted URL")
    func getWithPath() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(User(id: 7, name: "Alice"))) }

        let service = makeService(baseURL: "https://api.example.com")
        let response = try await service.getUser(id: 7)

        #expect(StubURLProtocol.captured?.url == "https://api.example.com/users/7")
        #expect(StubURLProtocol.captured?.method == "GET")
        #expect(response.statusCode == 200)
        #expect(response.body == User(id: 7, name: "Alice"))
    }

    @Test("GET with a Query parameter appends the query item")
    func getWithQuery() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode([User(id: 1, name: "Bob")])) }

        let service = makeService(baseURL: "https://api.example.com/")
        let response = try await service.listUsers(page: 2)

        #expect(StubURLProtocol.captured?.url == "https://api.example.com/users?page=2")
        #expect(response.body.count == 1)
    }

    @Test("POST with a Body parameter sends the JSON-encoded payload")
    func postWithBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (201, try! JSONEncoder().encode(User(id: 9, name: "Carol"))) }

        let service = makeService(baseURL: "https://api.example.com")
        let response = try await service.createUser(user: NewUser(name: "Carol"))

        #expect(StubURLProtocol.captured?.method == "POST")
        let sentBody = StubURLProtocol.captured?.body ?? Data()
        let decoded = try JSONDecoder().decode([String: String].self, from: sentBody)
        #expect(decoded["name"] == "Carol")
        #expect(response.statusCode == 201)
        #expect(response.body == User(id: 9, name: "Carol"))
    }

    @Test("a non-skipped request has the Authorization header applied")
    func authorizationApplied() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(User(id: 1, name: "Dao"))) }

        let service = makeService(baseURL: "https://api.example.com", withAuth: true)
        _ = try await service.getUser(id: 1)

        #expect(StubURLProtocol.captured?.headers["Authorization"] == "Bearer tok123")
    }

    @Test("@SkipAuth omits the Authorization header")
    func skipAuthOmitsAuthorization() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(["env": "prod"])) }

        let service = makeService(baseURL: "https://api.example.com", withAuth: true)
        let response = try await service.config()

        #expect(StubURLProtocol.captured?.url == "https://api.example.com/public/config")
        #expect(StubURLProtocol.captured?.headers["Authorization"] == nil)
        #expect(response.body["env"] == "prod")
    }

    @Test("a @Cacheable request serves the second call from cache")
    func cacheableServesSecondCallFromCache() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(User(id: 7, name: "Alice"))) }

        let service = makeCachedService(baseURL: "https://api.example.com")
        let first = try await service.getUser(id: 7)
        let second = try await service.getUser(id: 7)

        #expect(StubURLProtocol.requestCount == 1)
        #expect(first.body == User(id: 7, name: "Alice"))
        #expect(second.body == first.body)
    }

    @Test("a @NoCache request always hits the network")
    func noCacheAlwaysHitsNetwork() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(["status": "ok"])) }

        let service = makeCachedService(baseURL: "https://api.example.com")
        _ = try await service.health()
        _ = try await service.health()

        #expect(StubURLProtocol.requestCount == 2)
    }

    @Test("caching never applies to non-GET requests even under a service-wide @Cacheable")
    func cacheableNeverCachesNonGet() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(User(id: 9, name: "Carol"))) }

        let service = makeCachedService(baseURL: "https://api.example.com")
        _ = try await service.createUser(user: NewUser(name: "Carol"))
        _ = try await service.createUser(user: NewUser(name: "Carol"))

        // Both POSTs must reach the network — a non-GET response is never served from cache.
        #expect(StubURLProtocol.requestCount == 2)
    }

    // MARK: - Retry idempotency

    @Test("a failing GET is retried up to the retry policy limit")
    func failingGetIsRetried() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (500, Data()) }

        let service = makeRetryService(baseURL: "https://api.example.com")
        await #expect(throws: RESTError.self) {
            _ = try await service.flakyGet()
        }

        // initial attempt + 2 retries (maxAttempts: 2)
        #expect(StubURLProtocol.requestCount == 3)
    }

    @Test("a failing POST is not retried (non-idempotent)")
    func failingPostIsNotRetried() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (500, Data()) }

        let service = makeRetryService(baseURL: "https://api.example.com")
        await #expect(throws: RESTError.self) {
            _ = try await service.submit(payload: NewUser(name: "Eve"))
        }

        // Exactly one request — POST must not be retried on a server/network failure.
        #expect(StubURLProtocol.requestCount == 1)
    }

    // MARK: - Empty body

    @Test("a void method exposes the 204 response metadata with an empty body")
    func voidMethodExposesResponseMetadata() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (204, Data()) }

        let service = makeEmptyBodyService(baseURL: "https://api.example.com")
        let response = try await service.deleteUser(id: 7)

        #expect(StubURLProtocol.captured?.method == "DELETE")
        #expect(response.statusCode == 204)
        _ = response.body as EmptyResponse
    }

    @Test("a void method can be called as a discardable statement")
    func voidMethodIsDiscardable() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (204, Data()) }

        let service = makeEmptyBodyService(baseURL: "https://api.example.com")
        try await service.deleteUser(id: 7)

        #expect(StubURLProtocol.requestCount == 1)
    }

    // MARK: - Token provider / refresher

    @Test("tokenProvider value is written to the Authorization header verbatim")
    func providerWritesVerbatimHeader() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(User(id: 1, name: "Eve"))) }

        let service = UserServiceClient(
            baseURL: "https://api.example.com",
            tokenProvider: { "Token raw-credential" },
            sessionConfiguration: stubSessionConfig()
        )
        _ = try await service.getUser(id: 1)

        // No "Bearer " is prepended — the closure owns the scheme.
        #expect(StubURLProtocol.captured?.headers["Authorization"] == "Token raw-credential")
    }

    @Test("tokenProvider is read live on every request")
    func providerReadLivePerRequest() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(User(id: 1, name: "Eve"))) }

        let box = TokenBox()
        await box.set("Bearer A")
        let service = UserServiceClient(
            baseURL: "https://api.example.com",
            tokenProvider: { await box.get() },
            sessionConfiguration: stubSessionConfig()
        )

        _ = try await service.getUser(id: 1)
        #expect(StubURLProtocol.captured?.headers["Authorization"] == "Bearer A")

        // Change the underlying source — the next request must reflect it without rebuilding the client.
        await box.set("Bearer B")
        _ = try await service.getUser(id: 1)
        #expect(StubURLProtocol.captured?.headers["Authorization"] == "Bearer B")
    }

    @Test("refresher-only: a 401 refreshes and the retried request carries the new token")
    func refresherOnlyAppliesRefreshedTokenOnRetry() async throws {
        StubURLProtocol.reset()
        // First request → 401, retried request → 200.
        StubURLProtocol.respond { _ in
            StubURLProtocol.requestCount == 1
                ? (401, Data())
                : (200, try! JSONEncoder().encode(User(id: 1, name: "Eve")))
        }

        let refreshCount = Counter()
        let service = UserServiceClient(
            baseURL: "https://api.example.com",
            retryPolicy: RetryPolicy(maxAttempts: 2, delay: 0),
            tokenRefresher: { await refreshCount.increment(); return "Bearer refreshed" },
            sessionConfiguration: stubSessionConfig()
        )

        _ = try await service.getUser(id: 1)

        #expect(await refreshCount.value == 1)
        #expect(StubURLProtocol.requestCount == 2)
        #expect(StubURLProtocol.captured?.headers["Authorization"] == "Bearer refreshed")
    }

    @Test("a 401 triggers a refresh by default with no isUnauthorized supplied")
    func default401TriggersRefresh() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in
            StubURLProtocol.requestCount == 1
                ? (401, Data())
                : (200, try! JSONEncoder().encode(User(id: 1, name: "Eve")))
        }

        let refreshCount = Counter()
        let service = UserServiceClient(
            baseURL: "https://api.example.com",
            retryPolicy: RetryPolicy(maxAttempts: 2, delay: 0),
            // No isUnauthorized — engine defaults to treating 401 as the auth failure.
            tokenRefresher: { await refreshCount.increment(); return "Bearer refreshed" },
            sessionConfiguration: stubSessionConfig()
        )

        _ = try await service.getUser(id: 1)

        #expect(await refreshCount.value == 1)
        #expect(StubURLProtocol.requestCount == 2)
    }

    @Test("a persistently-401 endpoint refreshes and retries exactly once, then fails")
    func authRefreshRetriesOnce() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (401, Data()) }   // never recovers

        let refreshCount = Counter()
        let service = UserServiceClient(
            baseURL: "https://api.example.com",
            retryPolicy: RetryPolicy(maxAttempts: 3, delay: 0),
            tokenRefresher: { await refreshCount.increment(); return "Bearer refreshed" },
            sessionConfiguration: stubSessionConfig()
        )

        await #expect(throws: (any Error).self) {
            _ = try await service.getUser(id: 1)
        }

        // Exactly one refresh and one retry (initial + one retry = 2 requests), despite maxAttempts 3.
        #expect(await refreshCount.value == 1)
        #expect(StubURLProtocol.requestCount == 2)
    }

    @Test("logging traces both the request and the response blocks")
    func loggingTracesRequestAndResponse() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(User(id: 7, name: "Alice"))) }

        let logs = LogCollector()
        let service = UserServiceClient(
            baseURL: "https://api.example.com",
            tokenProvider: { "Bearer tok123" },
            sessionConfiguration: stubSessionConfig(),
            logging: { logs.append($0) }
        )

        _ = try await service.getUser(id: 7)

        // The response block is emitted on Alamofire's monitor queue, which may settle slightly
        // after `send` returns — poll briefly until the closing response marker arrives.
        var combined = ""
        for _ in 0..<100 {
            combined = logs.all.joined(separator: "\n")
            if combined.contains("<-- END HTTP") { break }
            try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }

        // Request block: includes the injected Authorization header.
        #expect(combined.contains("--> GET https://api.example.com/users/7"))
        #expect(combined.contains("Authorization: Bearer tok123"))
        #expect(combined.contains("--> END GET"))
        // Response block: status line + body + closing marker.
        #expect(combined.contains("<-- 200 "))
        #expect(combined.contains("\"name\":\"Alice\""))
        #expect(combined.contains("<-- END HTTP"))
    }
}

// MARK: - Test support

/// A `URLProtocol`-stubbed ephemeral session configuration.
private func stubSessionConfig() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return config
}

/// Mutable token source for the live-read test (stands in for a reactive store).
private actor TokenBox {
    private var token: String?
    func set(_ value: String?) { token = value }
    func get() -> String? { token }
}

/// Counts how many times the refresher closure runs.
private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// Thread-safe sink for `logging` output. The closure may be invoked from Alamofire's monitor
/// queue, so appends are guarded by a lock.
private final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ message: String) { lock.lock(); entries.append(message); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return entries }
}

// MARK: - URLProtocol stub

/// Synchronous `URLProtocol` stub. The suite is `.serialized`, so the static state is only
/// touched by one test at a time. The observed request is captured for post-call assertions.
private final class StubURLProtocol: URLProtocol {
    struct Captured: Sendable {
        let url: String?
        let method: String?
        let headers: [String: String]
        let body: Data?
    }

    typealias Responder = @Sendable (URLRequest) -> (status: Int, body: Data)

    nonisolated(unsafe) private static var responder: Responder?
    nonisolated(unsafe) private static var capturedBox: Captured?
    nonisolated(unsafe) private static var requestCountBox = 0
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responder = nil
        capturedBox = nil
        requestCountBox = 0
    }

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requestCountBox
    }

    static func respond(_ responder: @escaping Responder) {
        lock.lock(); defer { lock.unlock() }
        self.responder = responder
    }

    static var captured: Captured? {
        lock.lock(); defer { lock.unlock() }
        return capturedBox
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let captured = Captured(
            url: request.url?.absoluteString,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.bodyData
        )
        let responder: Responder?
        StubURLProtocol.lock.lock()
        StubURLProtocol.capturedBox = captured
        StubURLProtocol.requestCountBox += 1
        responder = StubURLProtocol.responder
        StubURLProtocol.lock.unlock()

        guard let responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = responder(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Reading the request body inside a URLProtocol

private extension URLRequest {
    /// `URLSession` converts `httpBody` into an `httpBodyStream` by the time a `URLProtocol`
    /// sees the request, so read whichever is present.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
