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
    func getUser(id: Path<Int>) async throws -> User

    @Get("users")
    func listUsers(page: Query<Int>) async throws -> [User]

    @Post("users")
    func createUser(user: Body<NewUser>) async throws -> User

    @Get("public/config")
    @SkipAuth
    func config() async throws -> [String: String]
}

// `baseURL` lets the endpoint paths be relative. Each service owns its own configuration.
let service = UserServiceClient(baseURL: "https://api.example.com")

let user = try await service.getUser(id: 1).body   // "Alice"
let users = try await service.listUsers(page: 1).body
let created = try await service.createUser(user: NewUser(name: "Bob")).body
```

The macro emits a standalone `struct UserServiceClient` that builds each `RESTRequest` and runs it for you. Every method must be `async throws` and declare its decoded body type `T` directly (e.g. `-> User`); the generated client method returns `RESTResponse<T>`, so call sites use `.body`, `.statusCode`, etc. on the result.

For endpoints with no response body (e.g. a `DELETE` returning `204 No Content`), **omit the return type**:

```swift
@Delete("users/{id}")
func deleteUser(id: Path<Int>) async throws
```

The generated method is `@discardableResult` and returns `RESTResponse<EmptyResponse>`, so you can ignore the result (`try await service.deleteUser(id: 7)`) or capture it to read `.statusCode`/`.headers` — only the `body` is the empty placeholder.

## Annotations

| Annotation | Applies to | Effect |
|---|---|---|
| `@Service` | protocol | Generates the `<ProtocolName>Client` implementation |
| `@Get` / `@Post` / `@Put` / `@Patch` / `@Delete` | method | HTTP method + path (relative to `baseURL`) |
| `@SkipAuth` | method | Opts the request out of token injection |
| `@Cacheable(ttl:maxEntries:)` | protocol / method | Caches responses in memory (see [Caching](#caching)) |
| `@NoCache` | method | Opts a method out when the service caches by default |
| `@Retry(maxAttempts:delay:)` | protocol / method | Sets / overrides the retry policy (see [Retry](#retry)) |
| `@NoRetry` | protocol / method | Disables retry for the service or a method |
| `Path<T>` | parameter | Substitutes a `{name}` placeholder in the path |
| `Query<T>` | parameter | Sent as a URL query item |
| `Body<T>` | parameter | JSON-encoded request body (max one per request) |
| `Header<T>` | parameter | Sent as a request header |

```swift
@Service
protocol ArticleService {
    @Get("articles/{id}")
    func article(id: Path<Int>, fields: Query<String>) async throws -> Article

    @Post("articles")
    func create(article: Body<NewArticle>, idempotencyKey: Header<String>) async throws -> Article
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

Most behaviour is passed as parameters when you create a service client (caching and retry are configured by annotation instead — see [Caching](#caching) and [Retry](#retry)). Only `baseURL` is required; everything else is optional with sensible defaults, and arguments can be supplied in any order.

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

Failed **idempotent** requests (`GET`, `PUT`, `DELETE`) are retried automatically; `POST` and `PATCH` are never retried, to avoid duplicating a side effect. The default policy retries up to 3 times with a 1-second delay.

Retry is configured **by annotation** (there is nothing to pass at the call site). A **protocol-level** `@Retry` / `@NoRetry` sets the **client-wide** policy — `@Retry(maxAttempts:delay:)` to customize it, `@NoRetry` to disable retry entirely:

```swift
@Service
@Retry(maxAttempts: 5, delay: 2.0)   // client-wide policy (or @NoRetry to disable)
protocol UserService { /* … */ }

let service = UserServiceClient(baseURL: "https://api.example.com")
```

Override or disable retry for a **single method** by annotating the method:

```swift
@Service
@Retry(maxAttempts: 5)                  // client-wide default
protocol UserService {
    @Get("users")
    func listUsers() async throws -> [User]            // inherits → 5

    @Get("flaky")
    @Retry(maxAttempts: 10, delay: 0.5)
    func flaky() async throws -> Thing                 // overrides → 10

    @Get("health")
    @NoRetry
    func health() async throws -> Status               // retry disabled
}
```

| On a method | Effect |
|---|---|
| *(nothing)* | inherits the client-wide policy |
| `@Retry(maxAttempts: 10, delay: 0.5)` | uses this policy instead |
| `@NoRetry` | retry disabled for this method |

With no `@Retry`/`@NoRetry` anywhere, the default policy (3 retries, 1 s) applies. `@Retry` is only valid on idempotent methods — using it on a `@Post`/`@Patch` is a compile error (those are never retried). `@Retry` and `@NoRetry` cannot be combined on the same protocol or method.

> Because retry is annotation-driven, the policy values are compile-time literals — there is no `retryPolicy:` parameter on the generated client. (This mirrors caching, which is also annotation-only.)

## Caching

Responses are cached in memory with `@Cacheable`. It can sit on the `@Service` protocol to cache every request by default, and/or on individual methods to enable or override caching for that request. `@NoCache` opts a method out. All caching is configured by annotation — there is nothing to pass at the call site.

```swift
@Service
@Cacheable(ttl: 300, maxEntries: 100)   // default: cache every request for 5 minutes
protocol CatalogService {
    @Get("products")
    func products() async throws -> [Product]          // inherits → 300 s

    @Get("products/{id}")
    @Cacheable(ttl: 60)
    func product(id: Path<Int>) async throws -> Product // override → 60 s

    @Get("categories")
    @Cacheable
    func categories() async throws -> [Category]        // cached, never expires

    @Get("inventory")
    @NoCache
    func inventory() async throws -> Inventory          // not cached
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

> In the examples below, `session` is **your own** state holder — back it with an `actor`, an
> `@Observable` model, or whatever your app already uses. iOS-SAK doesn't define or require any
> particular type; the closures simply read from (and write back to) the source you provide.

### Attaching a token to every request

Provide `tokenProvider` to supply the `Authorization` header value. It is read **live on every request**, so a token kept in a reactive store or variable is always reflected — update the source and the next request uses the new value. The returned string is written to the `Authorization` header **verbatim**, so the closure owns the scheme (`"Bearer …"`, `"Token …"`, or a raw credential):

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    tokenProvider: { await session.authorizationHeader }   // e.g. "Bearer eyJ…", or nil when signed out
)
```

Because it runs on the hot path of every request, keep it quick and lightweight — ideally a plain in-memory read, not a network/disk/Keychain round-trip.

### Skipping auth on specific requests

Annotate a method with `@SkipAuth` to opt it out of token injection — useful for login or public endpoints:

```swift
@Service
protocol AuthService {
    @Post("auth/login")
    @SkipAuth
    func login(credentials: Body<Credentials>) async throws -> LoginResponse
}
```

### Automatic token refresh on 401

Provide `tokenRefresher` to fetch a new token. When a request fails with an auth error, the token is refreshed and the request is retried **exactly once**; a response that still fails is surfaced as the original error (the refresh endpoint is never hammered). Concurrent requests that all fail share a single refresh call.

By default an HTTP **401** is treated as the auth failure that triggers a refresh. Supply `isUnauthorized` only to override that (e.g. to also treat 403 as expiry).

`tokenRefresher` must **return** the new verbatim `Authorization` value — it is applied directly to the retried request. When you also use `tokenProvider`, the refresher must additionally write the new value back (awaited) to the source `tokenProvider` reads from, so the live read on the retry sees it:

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    tokenRefresher: {
        let header = try await refreshAuthorizationHeader()   // your refresh call, e.g. via a @SkipAuth service
        await session.update(header)                          // write-back (awaited)
        return header
    },
    tokenProvider: { await session.authorizationHeader }
)
```

The write-back is race-free even with an `@Observable`/`@Published` source: mutating a Swift stored property is synchronous (only UI invalidation is deferred), so the next live read returns the new token — provided the write is awaited and the read/write share an isolation domain.

### Preemptive JWT refresh

Avoid 401 errors entirely by refreshing the token before it expires. Use `jwtExpiryDate(from:)` to extract the expiry date from the JWT (store it alongside the token when you sign in) and `preemptiveRefreshLeadTime` to control how far in advance to refresh (default: 60 seconds). All three closures can read the same async source:

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    tokenExpiryDate: { await session.expiry },              // e.g. jwtExpiryDate(from: token)
    preemptiveRefreshLeadTime: 60,                           // refresh 60 s before expiry
    tokenRefresher: { /* same as above */ },
    tokenProvider: { await session.authorizationHeader }
)
```

Refresh is **lazy/inline**: the expiry is checked just before each outgoing request, so the token is fresh when it goes out. There is no background timer (an idle app simply refreshes just-in-time on its next request).

## Logging

Pass a `logging` closure to trace every request and response, mirroring OkHttp's `HttpLoggingInterceptor` at `BODY` level. It is a `LoggingPolicy` — `@Sendable (String) -> Void` — that receives one formatted, multi-line entry per request and per response. Wire it to `print` in development, or to a custom sink:

```swift
let service = UserServiceClient(
    baseURL: "https://api.example.com",
    logging: { print($0) }   // or a custom sink
)
```

Sample output for a `GET` request:

```
--> GET https://api.example.com/users/7
Authorization: Bearer tok123
--> END GET

<-- 200 OK (22ms)
Content-Type: application/json
Content-Length: 24

{"id":7,"name":"Alice"}
<-- END HTTP
```

Notes:

- The logged request block includes the injected `Authorization` header, so logging pairs with authentication.
- Requests are logged **per attempt**. A generic retry re-issues a fresh request, so each attempt logs its own request *and* response block; only the intra-attempt auth refresh-and-retry (on a 401) logs a single settled response.
- A transport failure with no HTTP response logs a single line: `<-- HTTP FAILED: <message>`.
- The closure runs on **every** request — keep it cheap, and gate it behind a debug flag (or omit `logging` entirely) in production builds.

## Key types

| Type | Role |
|---|---|
| `@Service` + `@Get`/`@Post`/… | Generate a declarative, type-safe client from a protocol |
| `@Cacheable` / `@NoCache` | Opt requests into / out of in-memory response caching |
| `@Retry` / `@NoRetry` | Override or disable automatic retry per service or method |
| `RESTResponse<T>` | Decoded response body + `HTTPURLResponse` |
| `RetryPolicy` | `maxAttempts` + `delay` |
| `RESTError` | Typed error thrown on failure |
| `LoggingPolicy` | `@Sendable (String) -> Void` sink for request/response tracing |
| `jwtExpiryDate(from:)` | Extracts `exp` claim from a JWT as a `Date` |
