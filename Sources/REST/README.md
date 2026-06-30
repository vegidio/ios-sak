# rest

A high-level HTTP client for REST APIs built on [Alamofire](https://github.com/Alamofire/Alamofire). You describe your API as a Swift `protocol` and the `@Service` macro generates a fully type-safe client for you. Handles retry, caching, default headers, and automatic token refresh so you only write request logic.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vegidio/ios-sak.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "REST", package: "ios-sak"),
        ]
    ),
]
```

Then import it where needed:

```swift
import REST
```

## Quick start

Describe your API as a `protocol` annotated with `@Service`. Each method declares the **decoded body type directly** (e.g. `-> User`) — the generated client method returns a `RESTResponse<User>` wrapping it.

```swift
import REST

struct User: Decodable, Sendable {
    let id: Int
    let name: String
}

@Service
protocol UserService {
    @Get("users/{id}")
    func getUser(id: Path<Int>) async throws -> User
}

let service = UserServiceClient(baseURL: "https://api.example.com")

let response = try await service.getUser(id: 1)
print(response.body.name)    // "Alice"
print(response.statusCode)   // 200
```

`@Service protocol UserService` generates a `UserServiceClient` struct. The parameter markers (`Path`, `Query`, `Body`, `Header`) are transparent aliases — `Path<Int>` is just an `Int` at runtime — that tell the macro how to map each parameter onto the request. The **wire key is the parameter name** (so `id` fills the `{id}` placeholder).

## Sending requests

### GET with query parameters

Mark a parameter with `Query<T>` to send it as a URL query item named after the parameter:

```swift
@Service
protocol UserService {
    @Get("users")
    func listUsers(page: Query<Int>, limit: Query<Int>) async throws -> [User]
}

let response = try await service.listUsers(page: 1, limit: 20)
// GET /users?page=1&limit=20
```

### POST with auto-encoded body

Mark a parameter with `Body<T>` (any `Encodable` value) — it is JSON-encoded automatically and `Content-Type: application/json` is set for you:

```swift
struct NewUser: Encodable, Sendable {
    let name: String
}

@Service
protocol UserService {
    @Post("users")
    func createUser(user: Body<NewUser>) async throws -> User
}

let response = try await service.createUser(user: NewUser(name: "Alice"))
```

At most one `Body` parameter is allowed per method.

### Custom per-request headers

Mark a parameter with `Header<T>` to send it as a request header named after the parameter. Per-request headers always take priority over `defaultHeaders`:

```swift
@Service
protocol UserService {
    @Get("users/{id}")
    func getUser(id: Path<Int>, requestId: Header<String>) async throws -> User
}

let response = try await service.getUser(id: 1, requestId: UUID().uuidString)
// Sends header  requestId: <uuid>
```

### Endpoints with no response body

A method declared **without a return value** targets endpoints that return no content (e.g. `204 No Content`). The generated call is discardable, so you can ignore the result:

```swift
@Service
protocol UserService {
    @Delete("users/{id}")
    func deleteUser(id: Path<Int>) async throws
}

try await service.deleteUser(id: 1)              // result discarded
let response = try await service.deleteUser(id: 1)
print(response.statusCode)                       // 204
```

All five HTTP verbs are available as macros: `@Get`, `@Post`, `@Put`, `@Patch`, `@Delete`.

## Error handling

All failures are thrown as a case of `RESTError`:

| Case | When |
|------|------|
| `.invalidURL` | The URL string could not be parsed |
| `.network(Error)` | A transport-level failure (no connection, timeout, etc.) |
| `.httpError(statusCode: Int, data: Data)` | Server returned a non-2xx status after all retries; `data` is the raw response body |
| `.decodingError(Error)` | Response body could not be decoded into the expected type |

```swift
do {
    let response = try await service.getUser(id: 1)
    print(response.body)
} catch let error as RESTError {
    switch error {
    case let .httpError(statusCode, data):
        let body = String(data: data, encoding: .utf8) ?? ""
        print("Server error \(statusCode): \(body)")
    case let .network(cause):
        print("Network failure: \(cause)")
    case let .decodingError(cause):
        print("Could not decode response: \(cause)")
    case .invalidURL:
        print("Invalid URL")
    }
}
```

## Configuration

All behaviour is configured through the generated client's initializer and the macro annotations on your service.

### Default headers

Headers added to every request. A header already present on an individual request (via `Header<T>`) takes priority.

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    defaultHeaders: [
        "Accept": "application/json",
        "X-API-Version": "2",
    ]
)
```

### Retry

Failed requests are retried automatically. The default policy retries up to 3 times with a 1-second delay, and triggers on network failures and non-2xx responses. **Only idempotent methods (GET, PUT, DELETE) are retried** — POST and PATCH are never retried, to avoid duplicating side effects. Authentication failures (401) are excluded here and handled by token refresh instead (see [Authentication](#authentication)).

Set the baseline policy for the whole service with `@Retry` on the `@Service` protocol:

```swift
@Service
@Retry(maxAttempts: 5, delay: 2.0)   // applies to every idempotent request
protocol UserService {
    @Get("users")
    func listUsers() async throws -> [User]
}
```

Override it on individual methods. `@Retry` on a method uses a different policy just for that request; `@NoRetry` disables retry for that request:

```swift
@Service
@Retry(maxAttempts: 5, delay: 2.0)
protocol UserService {
    @Get("users")
    func listUsers() async throws -> [User]            // 5 attempts (from the service)

    @Get("users/{id}")
    @Retry(maxAttempts: 2, delay: 0.5)
    func getUser(id: Path<Int>) async throws -> User   // 2 attempts

    @Get("health")
    @NoRetry
    func health() async throws -> Status               // never retried
}
```

> `@Retry` / `@NoRetry` are only valid on idempotent methods (GET/PUT/DELETE). Applying them to a POST or PATCH is a compile-time error.

### Caching

`GET` responses can be cached in memory with a configurable TTL. Annotate the `@Service` protocol with `@Cacheable` to cache **every** GET by default — the second call with the same URL returns the cached response without hitting the network:

```swift
@Service
@Cacheable(ttl: 60, maxEntries: 100)   // entries expire after 60s; evict oldest past 100
protocol UserService {
    @Get("users")
    func listUsers() async throws -> [User]
}

let first = try await service.listUsers()   // hits the network, stores the response
let second = try await service.listUsers()  // returned from cache (within TTL)
```

You can also control caching per method:

```swift
@Service
@Cacheable(ttl: 60)
protocol UserService {
    @Get("users/{id}")
    @Cacheable(ttl: 300)                     // override: cache this one for 5 minutes
    func getUser(id: Path<Int>) async throws -> User

    @Get("health")
    @NoCache                                 // opt out: always hit the network
    func health() async throws -> Status
}
```

- `ttl` is in seconds; omit it for entries that never expire (kept until evicted by `maxEntries`).
- `maxEntries` is only valid on the `@Service` protocol, not on a method.
- `@Cacheable` is only valid on GET methods.

### Logging

Pass a `logging` closure to receive OkHttp-style request/response blocks. It runs on a non-invasive Alamofire event monitor, so it never touches the request/response hot path:

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    logging: { print($0) }
)

// --> GET https://api.example.com/users/1
// Authorization: Bearer abc123
// --> END GET
// <-- 200 OK (42ms)
// Content-Type: application/json
// {"id":1,"name":"Alice"}
// <-- END HTTP
```

### Custom decoder and session configuration

Supply a custom `JSONDecoder` (e.g. for date or key-decoding strategies) and/or a custom `URLSessionConfiguration` (e.g. timeouts):

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase

let configuration = URLSessionConfiguration.default
configuration.timeoutIntervalForRequest = 30

let service = UserServiceClient(
    baseURL: "https://api.example.com",
    decoder: decoder,
    sessionConfiguration: configuration
)
```

## Authentication

### Attaching a token to every request

Use `tokenProvider` to supply the current `Authorization` header value. It is read on **every** request, so a token kept in a reactive store is always reflected — update the source and the next request uses the new value. The closure owns the scheme, so return the **verbatim** header value (e.g. `"Bearer …"`):

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    tokenProvider: { await authStore.accessToken.map { "Bearer \($0)" } }
)
```

### Skipping auth on specific endpoints

Annotate a method with `@SkipAuth` to opt out of token injection — useful for login or public endpoints:

```swift
@Service
protocol AuthService {
    @Post("auth/login")
    @SkipAuth
    func login(credentials: Body<Credentials>) async throws -> LoginResponse

    @Post("auth/logout")
    func logout() async throws   // token is injected normally
}
```

### Automatic token refresh on 401

Provide `tokenRefresher` to fetch a new token when a `401` is received. The client refreshes the token once and retries the original request automatically. Concurrent requests that all hit 401 share a single refresh call. The closure returns the **new verbatim `Authorization` header value**; when you also use `tokenProvider`, the refresher must write the new value back to the source it reads from:

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    tokenRefresher: {
        let newToken = try await authApi.refresh(authStore.refreshToken)
        await authStore.setAccessToken(newToken)   // write back for tokenProvider
        return "Bearer \(newToken)"                // applied to retry the failed request
    },
    tokenProvider: { await authStore.accessToken.map { "Bearer \($0)" } }
)
```

By default a `401` status triggers the refresh. To customize what counts as an auth failure, pass `isUnauthorized`:

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    isUnauthorized: { $0.statusCode == 401 || $0.statusCode == 419 },
    tokenRefresher: { /* ... */ "Bearer \(newToken)" }
)
```

### Preemptive JWT refresh

Avoid 401s entirely by refreshing the token before it expires. Provide `tokenExpiryDate` to report the current token's expiry, and the client refreshes automatically once the token falls within `preemptiveRefreshLeadTime` of expiring (default: 60 seconds). The bundled `jwtExpiryDate(from:)` helper reads the `exp` claim out of a JWT (decoding only — it does not verify the signature):

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    tokenExpiryDate: { await authStore.accessToken.flatMap(jwtExpiryDate(from:)) },
    preemptiveRefreshLeadTime: 60,   // refresh 60s before expiry
    tokenRefresher: {
        let newToken = try await authApi.refresh(authStore.refreshToken)
        await authStore.setAccessToken(newToken)
        return "Bearer \(newToken)"
    },
    tokenProvider: { await authStore.accessToken.map { "Bearer \($0)" } }
)
```

## Key types

| Type | Role |
|------|------|
| `@Service` | Attach to a `protocol` to generate a `<Protocol>Client` struct — the single entry point |
| `<Protocol>Client` | Generated client; create once with your `baseURL` and configuration, reuse everywhere |
| `@Get` / `@Post` / `@Put` / `@Patch` / `@Delete` | Declare a method's HTTP verb and path |
| `Path<T>` / `Query<T>` / `Body<T>` / `Header<T>` | Mark how each parameter maps onto the request (keyed by parameter name) |
| `@SkipAuth` | Skip auth injection on a single endpoint |
| `@Cacheable` / `@NoCache` | Enable / disable in-memory GET response caching (service- or method-level) |
| `@Retry` / `@NoRetry` | Set or disable the retry policy (service- or method-level; idempotent methods only) |
| `RESTResponse<T>` | Decoded `body` + `statusCode` + `headers` |
| `RESTError` | Error enum thrown on failure |
