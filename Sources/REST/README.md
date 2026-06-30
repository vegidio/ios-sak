# REST

A high-level HTTP client for REST APIs built on [Alamofire](https://github.com/Alamofire/Alamofire). You describe an API as an annotated protocol and the `@Service` macro generates a type-safe client that handles retry, default headers, response caching, and automatic token refresh for you — similar to Retrofit on Android.

## Quick start

Describe your API as a protocol, annotate it with `@Service`, and construct the generated client directly — only `baseURL` is required:

```swift
struct User: Decodable, Sendable { let id: Int; let name: String }
struct NewUser: Encodable, Sendable { let name: String }

@Service
protocol UserService {
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

// `baseURL` lets the endpoint paths be relative. Each service owns its own configuration.
let service = UserServiceClient(baseURL: "https://api.example.com")

let user = try await service.getUser(id: 1).body   // "Alice"
let users = try await service.listUsers(page: 1).body
let created = try await service.createUser(user: NewUser(name: "Bob")).body
```

The macro emits a `struct UserServiceClient: UserService` that builds each `RESTRequest` and runs it for you. Every method must be `async throws` and return `RESTResponse<T>`, where `T` is the decoded body type.

## Annotations

| Annotation | Applies to | Effect |
|---|---|---|
| `@Service` | protocol | Generates the `<ProtocolName>Client` implementation |
| `@Get` / `@Post` / `@Put` / `@Patch` / `@Delete` | method | HTTP method + path (relative to `baseURL`) |
| `@SkipAuth` | method | Opts the request out of token injection |
| `@Cacheable(ttl:maxEntries:)` | protocol / method | Caches responses in memory (see [Caching](#caching)) |
| `@NoCache` | method | Opts a method out when the service caches by default |
| `Path<T>` | parameter | Substitutes a `{name}` placeholder in the path |
| `Query<T>` | parameter | Sent as a URL query item |
| `Body<T>` | parameter | JSON-encoded request body (max one per request) |
| `Header<T>` | parameter | Sent as a request header |

```swift
@Service
protocol ArticleService {
    @Get("articles/{id}")
    func article(id: Path<Int>, fields: Query<String>) async throws -> RESTResponse<Article>

    @Post("articles")
    func create(article: Body<NewArticle>, idempotencyKey: Header<String>) async throws -> RESTResponse<Article>
}
```

A `Body` value is JSON-encoded automatically and `Content-Type: application/json` is set for you. Per-method `Header` values win over the configuration's `defaultHeaders`.

> **Note on parameter markers:** Swift does not allow attributes on function parameters, so the parameter tags are *transparent generic type aliases* (`Path<Int>` is literally `Int` at runtime). The **wire key is the parameter name**: a `{id}` placeholder matches the parameter named `id`, and `page: Query<Int>` sends `?page=`. Path/query/header values are interpolated as strings, so use `CustomStringConvertible` types (scalars, `String`).

## Error handling

All failures are thrown as `RESTError`:

| Case | When |
|---|---|
| `.invalidURL` | The URL string could not be parsed |
| `.network(Error)` | A transport-level failure (no connection, timeout, etc.) |
| `.httpError(statusCode:data:)` | Server returned a non-2xx status |
| `.decodingError(Error)` | Response body could not be decoded into `T` |

```swift
do {
    let user = try await service.getUser(id: 1).body
} catch RESTError.httpError(let code, let data) {
    print("Server error \(code)")
} catch RESTError.network(let error) {
    print("Network failure: \(error)")
}
```

## Configuration

All behaviour is passed as parameters when you create a service client. Only `baseURL` is required; everything else is optional with sensible defaults, and arguments can be supplied in any order.

### Base URL

Set `baseURL` so the annotated endpoint paths can be relative. Requests whose URL is already absolute (`http`/`https`) are sent unchanged.

```swift
let service = UserServiceClient(baseURL: "https://api.example.com")
// @Get("users/1") → https://api.example.com/users/1
```

### Default headers

Headers added to every request. A per-method `Header<T>` with the same name takes priority.

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    defaultHeaders: [
        "Accept": "application/json",
        "X-API-Version": "2"
    ]
)
```

### Retry

Failed requests are retried automatically. The default policy retries up to 3 times with a 1-second delay. Set `retryPolicy: nil` to disable.

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    retryPolicy: RetryPolicy(maxAttempts: 5, delay: 2.0)
)
```

## Caching

Responses are cached in memory with `@Cacheable`. It can sit on the `@Service` protocol to cache every request by default, and/or on individual methods to enable or override caching for that request. `@NoCache` opts a method out. All caching is configured by annotation — there is nothing to pass at the call site.

```swift
@Service
@Cacheable(ttl: 300, maxEntries: 100)   // default: cache every request for 5 minutes
protocol CatalogService {
    @Get("products")
    func products() async throws -> RESTResponse<[Product]>          // inherits → 300 s

    @Get("products/{id}")
    @Cacheable(ttl: 60)
    func product(id: Path<Int>) async throws -> RESTResponse<Product> // override → 60 s

    @Get("categories")
    @Cacheable
    func categories() async throws -> RESTResponse<[Category]>        // cached, never expires

    @Get("inventory")
    @NoCache
    func inventory() async throws -> RESTResponse<Inventory>          // not cached
}
```

The model is **presence-based** — the macro reads what you wrote, not a default value:

| On a method | Effect when the service has `@Cacheable(ttl: 300)` |
|---|---|
| *(nothing)* | inherits → cached for 300 s |
| `@Cacheable` | cached with **no expiry** (removes the inherited TTL) |
| `@Cacheable(ttl: 60)` | cached for **60 s** (overrides) |
| `@NoCache` | **not cached** |

- **`ttl`** — seconds a cached response stays valid. Omit it to cache with no expiry (kept until evicted by `maxEntries`).
- **`maxEntries`** — caps the size of the single shared in-memory store. It is **service-level only**; using it on a method is a compile error.

Cache entries are keyed by the resolved URL plus its query parameters, so the same call with different query values is cached separately.

## Authentication

### Attaching a token to every request

Use `applyToken` to inject the token however your API expects it (Bearer header, query parameter, etc.). Once configured, every request automatically receives the current token:

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    applyToken: { token, request in
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
)
```

### Skipping auth on specific requests

Annotate a method with `@SkipAuth` to opt it out of token injection — useful for login or public endpoints:

```swift
@Service
protocol AuthService {
    @Post("auth/login")
    @SkipAuth
    func login(credentials: Body<Credentials>) async throws -> RESTResponse<LoginResponse>
}
```

### Automatic token refresh on 401

Provide `isUnauthorized` to detect auth failures and `refreshToken` to fetch a new token. When a request returns 401, the token is refreshed once and the original request is retried automatically. Concurrent requests that all hit 401 share a single refresh call.

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    isUnauthorized: { $0.statusCode == 401 },
    refreshToken: {
        // Refresh through a dedicated, auth-free service.
        let response = try await authService.refresh(
            token: RefreshToken(value: authStore.refreshToken)
        )
        authStore.accessToken = response.body.accessToken
        return response.body.accessToken
    },
    applyToken: { token, request in
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
)
```

### Preemptive JWT refresh

Avoid 401 errors entirely by refreshing the token before it expires. Use `jwtExpiryDate(from:)` to extract the expiry date from the JWT and `preemptiveRefreshLeadTime` to control how far in advance to refresh (default: 60 seconds).

```swift
// After login, store the token and its expiry
authStore.accessToken = loginResponse.body.accessToken
authStore.expiry = jwtExpiryDate(from: loginResponse.body.accessToken)

let service = UserServiceClient(
    baseURL: "https://api.example.com",
    tokenExpiryDate: { authStore.expiry },
    preemptiveRefreshLeadTime: 60,   // refresh 60 s before expiry
    refreshToken: { /* same as above */ },
    applyToken: { token, request in
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
)
```

## Key types

| Type | Role |
|---|---|
| `@Service` + `@Get`/`@Post`/… | Generate a declarative, type-safe client from a protocol |
| `@Cacheable` / `@NoCache` | Opt requests into / out of in-memory response caching |
| `RESTResponse<T>` | Decoded response body + `HTTPURLResponse` |
| `RetryPolicy` | `maxAttempts` + `delay` |
| `RESTError` | Typed error thrown on failure |
| `jwtExpiryDate(from:)` | Extracts `exp` claim from a JWT as a `Date` |
