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
    ]

    func testGetWithPath() {
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

            struct UserServiceClient: UserService {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    cachePolicy: CachePolicy? = nil,
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
                        cachePolicy: cachePolicy,
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
                func listUsers(page: Query<Int>) async throws -> RESTResponse<[User]>
            }
            """,
            expandedSource: """
            public protocol UserService {
                func listUsers(page: Query<Int>) async throws -> RESTResponse<[User]>
            }

            public struct UserServiceClient: UserService {
                private let client: RESTClient
                public init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    cachePolicy: CachePolicy? = nil,
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
                        cachePolicy: cachePolicy,
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
                func createUser(user: Body<NewUser>) async throws -> RESTResponse<User>
            }
            """,
            expandedSource: """
            protocol UserService {
                func createUser(user: Body<NewUser>) async throws -> RESTResponse<User>
            }

            struct UserServiceClient: UserService {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    cachePolicy: CachePolicy? = nil,
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
                        cachePolicy: cachePolicy,
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
                func config() async throws -> RESTResponse<Config>
            }
            """,
            expandedSource: """
            protocol ConfigService {
                func config() async throws -> RESTResponse<Config>
            }

            struct ConfigServiceClient: ConfigService {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    cachePolicy: CachePolicy? = nil,
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
                        cachePolicy: cachePolicy,
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
                func getUser(id: Path<Int>) async throws -> RESTResponse<User>
            }
            """,
            expandedSource: """
            protocol UserService {
                func getUser(id: Path<Int>) async throws -> RESTResponse<User>
            }

            struct UserServiceClient: UserService {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    cachePolicy: CachePolicy? = nil,
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
                        cachePolicy: cachePolicy,
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
                func createUser(a: Body<NewUser>, b: Body<NewUser>) async throws -> RESTResponse<User>
            }
            """,
            expandedSource: """
            protocol UserService {
                func createUser(a: Body<NewUser>, b: Body<NewUser>) async throws -> RESTResponse<User>
            }

            struct UserServiceClient: UserService {
                private let client: RESTClient
                init(
                    baseURL: String,
                    defaultHeaders: [String: String] = [:],
                    retryPolicy: RetryPolicy? = RetryPolicy(),
                    cachePolicy: CachePolicy? = nil,
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
                        cachePolicy: cachePolicy,
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
}
