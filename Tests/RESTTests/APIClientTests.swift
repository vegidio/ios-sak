import Testing
import Foundation
@testable import REST

@Suite("APIClient")
struct APIClientTests {

    // MARK: - makeCacheKey

    @Test("makeCacheKey is deterministic regardless of dictionary ordering")
    func cacheKeyIsDeterministic() {
        let key1 = makeCacheKey(url: "https://api.example.com/users", queryParams: ["page": "1", "limit": "20"])
        let key2 = makeCacheKey(url: "https://api.example.com/users", queryParams: ["limit": "20", "page": "1"])
        #expect(key1 == key2)
        #expect(key1 == "https://api.example.com/users?limit=20&page=1")
    }

    @Test("makeCacheKey with no query params returns bare URL")
    func cacheKeyNoParams() {
        let key = makeCacheKey(url: "https://api.example.com/users", queryParams: [:])
        #expect(key == "https://api.example.com/users")
    }

    // MARK: - CacheEntry expiry

    @Test("CacheEntry is not expired when TTL has not elapsed")
    func cacheEntryNotExpired() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let entry = CacheEntry(
            data: Data(),
            httpResponse: response,
            expiresAt: Date().addingTimeInterval(300)
        )
        #expect(!entry.isExpired)
    }

    @Test("CacheEntry is expired when TTL has elapsed")
    func cacheEntryExpired() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let entry = CacheEntry(
            data: Data(),
            httpResponse: response,
            expiresAt: Date().addingTimeInterval(-1)
        )
        #expect(entry.isExpired)
    }

    // MARK: - ResponseCache

    @Test("ResponseCache returns stored entry before TTL expires")
    func responseCacheHit() async {
        let cache = ResponseCache()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let data = "hello".data(using: .utf8)!
        await cache.store(data, httpResponse: response, forKey: "key1", ttl: 300)
        let retrieved = await cache.retrieve(forKey: "key1")
        #expect(retrieved != nil)
        #expect(retrieved?.data == data)
    }

    @Test("ResponseCache returns nil after TTL expires")
    func responseCacheMiss() async {
        let cache = ResponseCache()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        // Store with a negative TTL so it's immediately expired
        await cache.store(Data(), httpResponse: response, forKey: "key2", ttl: -1)
        let retrieved = await cache.retrieve(forKey: "key2")
        #expect(retrieved == nil)
    }

    // MARK: - TokenRefreshCoordinator

    @Test("TokenRefreshCoordinator calls handler only once for concurrent refresh calls")
    func coordinatorCoalescesConcurrentRefreshes() async throws {
        let coordinator = TokenRefreshCoordinator()
        let callCount = ActorCounter()

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await coordinator.refresh {
                        await callCount.increment()
                        // Simulate a small delay for the refresh network call
                        try await Task.sleep(nanoseconds: 10_000_000)
                        return "new-token"
                    }
                }
            }
            var tokens: [String] = []
            for try await token in group {
                tokens.append(token)
            }
            return tokens
        }

        let count = await callCount.value
        #expect(count == 1)
        #expect(results.allSatisfy { $0 == "new-token" })
    }

    @Test("TokenRefreshCoordinator stores the token after successful refresh")
    func coordinatorStoresToken() async throws {
        let coordinator = TokenRefreshCoordinator()
        _ = try await coordinator.refresh { "stored-token" }
        let token = await coordinator.currentToken
        #expect(token == "stored-token")
    }

    // MARK: - jwtExpiryDate

    @Test("jwtExpiryDate extracts expiry from a valid JWT")
    func jwtExpiryDateValid() {
        // Payload: {"exp": 9999999999} — a date far in the future
        // base64url of {"exp":9999999999} = eyJleHAiOjk5OTk5OTk5OTl9
        let header = "eyJhbGciOiJIUzI1NiJ9"
        let payload = "eyJleHAiOjk5OTk5OTk5OTl9"
        let signature = "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let token = "\(header).\(payload).\(signature)"

        let date = jwtExpiryDate(from: token)
        #expect(date != nil)
        #expect(date == Date(timeIntervalSince1970: 9_999_999_999))
    }

    @Test("jwtExpiryDate returns nil for a malformed token")
    func jwtExpiryDateMalformed() {
        #expect(jwtExpiryDate(from: "not.a.jwt.at.all.extra") == nil)
        #expect(jwtExpiryDate(from: "onlytwoparts") == nil)
        #expect(jwtExpiryDate(from: "") == nil)
    }

    // MARK: - RESTRequest convenience init

    @Test("RESTRequest Encodable init encodes body and sets Content-Type")
    func requestEncodableInit() throws {
        struct Payload: Codable { let name: String }
        let request = try RESTRequest(
            url: "https://api.example.com/users",
            method: .post,
            body: Payload(name: "Alice")
        )
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.body != nil)
        let decoded = try JSONDecoder().decode(Payload.self, from: request.body!)
        #expect(decoded.name == "Alice")
    }

    @Test("RESTRequest Encodable init does not override existing Content-Type")
    func requestEncodableInitPreservesContentType() throws {
        struct Payload: Encodable { let value: Int }
        let request = try RESTRequest(
            url: "https://api.example.com/items",
            method: .post,
            headers: ["Content-Type": "application/vnd.api+json"],
            body: Payload(value: 42)
        )
        #expect(request.headers["Content-Type"] == "application/vnd.api+json")
    }

    // MARK: - RESTRequest skipAuth sentinel

    @Test("RESTRequest with skipAuth sets X-Skip-Auth header in URLRequest")
    func requestSkipAuthSetsHeader() throws {
        let request = RESTRequest(url: "https://api.example.com/public", skipAuth: true)
        let urlRequest = try request.buildURLRequest()
        #expect(urlRequest.value(forHTTPHeaderField: "X-Skip-Auth") == "1")
    }

    @Test("RESTRequest without skipAuth does not set X-Skip-Auth header")
    func requestNoSkipAuthHeader() throws {
        let request = RESTRequest(url: "https://api.example.com/private")
        let urlRequest = try request.buildURLRequest()
        #expect(urlRequest.value(forHTTPHeaderField: "X-Skip-Auth") == nil)
    }

    // MARK: - APIConfiguration defaults

    @Test("APIConfiguration default retryPolicy has maxAttempts 3 and delay 1.0")
    func configurationDefaultRetryPolicy() {
        let config = APIConfiguration()
        #expect(config.retryPolicy?.maxAttempts == 3)
        #expect(config.retryPolicy?.delay == 1.0)
    }

    @Test("APIConfiguration default cachePolicy is nil")
    func configurationDefaultCachePolicy() {
        let config = APIConfiguration()
        #expect(config.cachePolicy == nil)
    }
}

// MARK: - Helpers

private actor ActorCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
