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
    func getUser(id: Path<Int>) async throws -> RESTResponse<User>

    @Get("users")
    func listUsers(page: Query<Int>) async throws -> RESTResponse<[User]>

    @Post("users")
    func createUser(user: Body<NewUser>) async throws -> RESTResponse<User>

    @Get("public/config")
    @SkipAuth
    func config() async throws -> RESTResponse<[String: String]>
}

@Suite("@Service generated client", .serialized)
struct ServiceIntegrationTests {

    private func makeClient(baseURL: String, withAuth: Bool = false) -> RESTClient {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]

        var applyToken: (@Sendable (String, inout URLRequest) -> Void)?
        var getToken: (@Sendable () -> String?)?
        if withAuth {
            applyToken = { token, req in req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            getToken = { "tok123" }
        }

        let config = RESTConfiguration(
            baseURL: baseURL,
            applyToken: applyToken,
            getToken: getToken
        )
        return RESTClient(configuration: config, sessionConfiguration: sessionConfig)
    }

    @Test("GET with a Path parameter hits the substituted URL")
    func getWithPath() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(User(id: 7, name: "Alice"))) }

        let service = UserServiceClient(client: makeClient(baseURL: "https://api.example.com"))
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

        let service = UserServiceClient(client: makeClient(baseURL: "https://api.example.com/"))
        let response = try await service.listUsers(page: 2)

        #expect(StubURLProtocol.captured?.url == "https://api.example.com/users?page=2")
        #expect(response.body.count == 1)
    }

    @Test("POST with a Body parameter sends the JSON-encoded payload")
    func postWithBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (201, try! JSONEncoder().encode(User(id: 9, name: "Carol"))) }

        let service = UserServiceClient(client: makeClient(baseURL: "https://api.example.com"))
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

        let service = UserServiceClient(client: makeClient(baseURL: "https://api.example.com", withAuth: true))
        _ = try await service.getUser(id: 1)

        #expect(StubURLProtocol.captured?.headers["Authorization"] == "Bearer tok123")
    }

    @Test("@SkipAuth omits the Authorization header")
    func skipAuthOmitsAuthorization() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond { _ in (200, try! JSONEncoder().encode(["env": "prod"])) }

        let service = UserServiceClient(client: makeClient(baseURL: "https://api.example.com", withAuth: true))
        let response = try await service.config()

        #expect(StubURLProtocol.captured?.url == "https://api.example.com/public/config")
        #expect(StubURLProtocol.captured?.headers["Authorization"] == nil)
        #expect(response.body["env"] == "prod")
    }
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
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responder = nil
        capturedBox = nil
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
