import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import RESTMacros

final class ServiceMacroTests: XCTestCase {
    private let macros: [String: any Macro.Type] = [
        "Service": ServiceMacro.self,
        "Get": GetMacro.self,
        "Post": PostMacro.self,
        "Put": PutMacro.self,
        "Patch": PatchMacro.self,
        "Delete": DeleteMacro.self,
        "SkipAuth": SkipAuthMacro.self,
        "Cacheable": CacheableMacro.self,
        "NoCache": NoCacheMacro.self,
    ]

    func testGetWithPath() {
        assertMacroExpansion(
            """
            @Service
            protocol UserService {
                @Get("users/{id}")
                func getUser(id: Path<Int>) async throws -> User
            }
            """,
            expandedSource: """
            protocol UserService {
                func getUser(id: Path<Int>) async throws -> User
            }

            struct UserServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }
                func getUser(id: Int) async throws -> RESTResponse<User> {
                    let request = RESTRequest(
                        url: "users/\\(id)",
                        method: .get
                    )
                    return try await client.send(request)
                }
            }
            """,
            macros: macros
        )
    }

    func testGetWithQuery() {
        assertMacroExpansion(
            """
            @Service
            public protocol UserService {
                @Get("users")
                func listUsers(page: Query<Int>) async throws -> [User]
            }
            """,
            expandedSource: """
            public protocol UserService {
                func listUsers(page: Query<Int>) async throws -> [User]
            }

            public struct UserServiceClient {
                private let client: RESTClient
                public init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }
                public func listUsers(page: Int) async throws -> RESTResponse<[User]> {
                    let request = RESTRequest(
                        url: "users",
                        method: .get,
                        queryParameters: ["page": "\\(page)"]
                    )
                    return try await client.send(request)
                }
            }
            """,
            macros: macros
        )
    }

    func testPostWithBody() {
        assertMacroExpansion(
            """
            @Service
            protocol UserService {
                @Post("users")
                func createUser(user: Body<NewUser>) async throws -> User
            }
            """,
            expandedSource: """
            protocol UserService {
                func createUser(user: Body<NewUser>) async throws -> User
            }

            struct UserServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }
                func createUser(user: NewUser) async throws -> RESTResponse<User> {
                    let request = try RESTRequest(
                        url: "users",
                        method: .post,
                        body: user
                    )
                    return try await client.send(request)
                }
            }
            """,
            macros: macros
        )
    }

    func testSkipAuth() {
        assertMacroExpansion(
            """
            @Service
            protocol ConfigService {
                @Get("public/config")
                @SkipAuth
                func config() async throws -> Config
            }
            """,
            expandedSource: """
            protocol ConfigService {
                func config() async throws -> Config
            }

            struct ConfigServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }
                func config() async throws -> RESTResponse<Config> {
                    let request = RESTRequest(
                        url: "public/config",
                        method: .get,
                        skipAuth: true
                    )
                    return try await client.send(request)
                }
            }
            """,
            macros: macros
        )
    }

    func testMissingHTTPMethodEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @Service
            protocol UserService {
                func getUser(id: Path<Int>) async throws -> User
            }
            """,
            expandedSource: """
            protocol UserService {
                func getUser(id: Path<Int>) async throws -> User
            }

            struct UserServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }

            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'getUser' must be annotated with one of @Get, @Post, @Put, @Patch or @Delete",
                    line: 3,
                    column: 5
                )
            ],
            macros: macros
        )
    }

    func testDuplicateBodyEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @Service
            protocol UserService {
                @Post("users")
                func createUser(a: Body<NewUser>, b: Body<NewUser>) async throws -> User
            }
            """,
            expandedSource: """
            protocol UserService {
                func createUser(a: Body<NewUser>, b: Body<NewUser>) async throws -> User
            }

            struct UserServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }

            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'createUser' has more than one Body parameter",
                    line: 3,
                    column: 5
                )
            ],
            macros: macros
        )
    }

    func testServiceLevelCacheable() {
        assertMacroExpansion(
            """
            @Service
            @Cacheable(ttl: 300, maxEntries: 100)
            protocol UserService {
                @Get("users/{id}")
                func getUser(id: Path<Int>) async throws -> User
            }
            """,
            expandedSource: """
            protocol UserService {
                func getUser(id: Path<Int>) async throws -> User
            }

            struct UserServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        maxEntries: 100,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }
                func getUser(id: Int) async throws -> RESTResponse<User> {
                    let request = RESTRequest(
                        url: "users/\\(id)",
                        method: .get
                    )
                    return try await client.send(request, cacheable: true, ttl: 300)
                }
            }
            """,
            macros: macros
        )
    }

    func testMethodCacheableOverridesTTL() {
        assertMacroExpansion(
            """
            @Service
            protocol UserService {
                @Get("users")
                @Cacheable(ttl: 60)
                func listUsers() async throws -> [User]
            }
            """,
            expandedSource: """
            protocol UserService {
                func listUsers() async throws -> [User]
            }

            struct UserServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }
                func listUsers() async throws -> RESTResponse<[User]> {
                    let request = RESTRequest(
                        url: "users",
                        method: .get
                    )
                    return try await client.send(request, cacheable: true, ttl: 60)
                }
            }
            """,
            macros: macros
        )
    }

    func testMethodCacheableRemovesTTL() {
        assertMacroExpansion(
            """
            @Service
            @Cacheable(ttl: 300)
            protocol UserService {
                @Get("users")
                @Cacheable
                func listUsers() async throws -> [User]
            }
            """,
            expandedSource: """
            protocol UserService {
                func listUsers() async throws -> [User]
            }

            struct UserServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }
                func listUsers() async throws -> RESTResponse<[User]> {
                    let request = RESTRequest(
                        url: "users",
                        method: .get
                    )
                    return try await client.send(request, cacheable: true, ttl: nil)
                }
            }
            """,
            macros: macros
        )
    }

    func testNoCacheOptOut() {
        assertMacroExpansion(
            """
            @Service
            @Cacheable(ttl: 300)
            protocol UserService {
                @Get("users")
                func listUsers() async throws -> [User]
                @Get("health")
                @NoCache
                func health() async throws -> Status
            }
            """,
            expandedSource: """
            protocol UserService {
                func listUsers() async throws -> [User]
                func health() async throws -> Status
            }

            struct UserServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }
                func listUsers() async throws -> RESTResponse<[User]> {
                    let request = RESTRequest(
                        url: "users",
                        method: .get
                    )
                    return try await client.send(request, cacheable: true, ttl: 300)
                }
                func health() async throws -> RESTResponse<Status> {
                    let request = RESTRequest(
                        url: "health",
                        method: .get
                    )
                    return try await client.send(request)
                }
            }
            """,
            macros: macros
        )
    }

    func testMaxEntriesOnMethodEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @Service
            protocol UserService {
                @Get("users")
                @Cacheable(maxEntries: 100)
                func listUsers() async throws -> [User]
            }
            """,
            expandedSource: """
            protocol UserService {
                func listUsers() async throws -> [User]
            }

            struct UserServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }

            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "maxEntries is only valid on the @Service protocol, not on a method",
                    line: 3,
                    column: 5
                )
            ],
            macros: macros
        )
    }

    func testExplicitRESTResponseEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @Service
            protocol UserService {
                @Get("users/{id}")
                func getUser(id: Path<Int>) async throws -> RESTResponse<User>
            }
            """,
            expandedSource: """
            protocol UserService {
                func getUser(id: Path<Int>) async throws -> RESTResponse<User>
            }

            struct UserServiceClient {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    tokenExpiryDate: (@Sendable () -> Date?)? = nil,
                    preemptiveRefreshLeadTime: TimeInterval = 60,
                    isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
                    refreshToken: (@Sendable () async throws -> String)? = nil,
                    applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
                    getToken: (@Sendable () -> String?)? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    sessionConfiguration: URLSessionConfiguration? = nil
                ) {
                    self.client = RESTClient(
                        baseURL: baseURL,
                        defaultHeaders: defaultHeaders,
                        retryPolicy: retryPolicy,
                        tokenExpiryDate: tokenExpiryDate,
                        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
                        isUnauthorized: isUnauthorized,
                        refreshToken: refreshToken,
                        applyToken: applyToken,
                        getToken: getToken,
                        decoder: decoder,
                        sessionConfiguration: sessionConfiguration
                    )
                }

            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'getUser' must declare the response body type directly (e.g. 'User'), not 'RESTResponse<…>'",
                    line: 3,
                    column: 5
                )
            ],
            macros: macros
        )
    }
}
