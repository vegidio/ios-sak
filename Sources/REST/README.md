# REST

A high-level HTTP client for REST APIs built on [Alamofire](https://github.com/Alamofire/Alamofire). Handles retry, caching, default headers, and automatic token refresh so you only write request logic.

## Quick start

```swift
let client = RESTClient(configuration: RESTConfiguration())

struct User: Decodable, Sendable { let id: Int; let name: String }

let response: RESTResponse<User> = try await client.send(
    RESTRequest(url: "https://api.example.com/users/1")
)
print(response.body.name)   // "Alice"
print(response.statusCode)  // 200
```

## Sending requests

### GET with query parameters

```swift
let response: RESTResponse<[User]> = try await client.send(
    RESTRequest(
        url: "https://api.example.com/users",
        queryParameters: ["page": "1", "limit": "20"]
    )
)
```

### POST with auto-encoded body

Pass any `Encodable` value as `body` — it is JSON-encoded automatically and `Content-Type: application/json` is set for you:

```swift
struct NewUser: Encodable { let name: String }

let response: RESTResponse<User> = try await client.send(
    try RESTRequest(
        url: "https://api.example.com/users",
        method: .post,
        body: NewUser(name: "Alice")
    )
)
```

### Custom per-request headers

Per-request headers always win over the client's `defaultHeaders`:

```swift
let response: RESTResponse<User> = try await client.send(
    RESTRequest(
        url: "https://api.example.com/users/1",
        headers: ["X-Request-ID": UUID().uuidString]
    )
)
```

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
    let response: RESTResponse<User> = try await client.send(request)
} catch RESTError.httpError(let code, let data) {
    print("Server error \(code)")
} catch RESTError.network(let error) {
    print("Network failure: \(error)")
}
```

## Configuration

All behaviour is controlled through `RESTConfiguration`, passed once at init time.

### Default headers

Headers added to every request. A header already present on an individual request takes priority.

```swift
let client = RESTClient(configuration: RESTConfiguration(
    defaultHeaders: [
        "Accept": "application/json",
        "X-API-Version": "2"
    ]
))
```

### Retry

Failed requests are retried automatically. The default policy retries up to 3 times with a 1-second delay. Set `retryPolicy: nil` to disable.

```swift
let client = RESTClient(configuration: RESTConfiguration(
    retryPolicy: RetryPolicy(maxAttempts: 5, delay: 2.0)
))
```

### Caching

Responses can be cached in memory with a TTL. Pass `cacheable: true` when sending — the second call returns the cached data without hitting the network.

```swift
let client = RESTClient(configuration: RESTConfiguration(
    cachePolicy: CachePolicy(ttl: 3600)  // cache for 1 hour
))

// First call hits the network and stores the response.
// Subsequent calls within the TTL return the cached response.
let response: RESTResponse<[User]> = try await client.send(
    RESTRequest(url: "https://api.example.com/users"),
    cacheable: true
)
```

## Authentication

### Attaching a token to every request

Use `applyToken` to inject the token however your API expects it (Bearer header, query parameter, etc.):

```swift
let client = RESTClient(configuration: RESTConfiguration(
    applyToken: { token, request in
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
))
```

Once configured, every request automatically receives the current token.

### Skipping auth on specific requests

Pass `skipAuth: true` to opt out of token injection for a single request — useful for login or public endpoints:

```swift
let response: RESTResponse<LoginResponse> = try await client.send(
    try RESTRequest(
        url: "https://api.example.com/auth/login",
        method: .post,
        body: credentials,
        skipAuth: true      // no token attached
    )
)
```

### Automatic token refresh on 401

Provide `isUnauthorized` to detect auth failures and `refreshToken` to fetch a new token. When a request returns 401, the client refreshes the token once and retries the original request automatically. Concurrent requests that all hit 401 share a single refresh call.

```swift
let client = RESTClient(configuration: RESTConfiguration(
    isUnauthorized: { $0.statusCode == 401 },
    refreshToken: {
        // Use a separate client (no auth) just for the refresh call
        struct RefreshResponse: Decodable, Sendable { let accessToken: String }
        let r: RESTResponse<RefreshResponse> = try await bareClient.send(
            try RESTRequest(
                url: "https://api.example.com/auth/refresh",
                method: .post,
                body: ["refreshToken": authStore.refreshToken],
                skipAuth: true
            )
        )
        authStore.accessToken = r.body.accessToken
        return r.body.accessToken
    },
    applyToken: { token, request in
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
))
```

### Preemptive JWT refresh

Avoid 401 errors entirely by refreshing the token before it expires. Use `jwtExpiryDate(from:)` to extract the expiry date from the JWT and `preemptiveRefreshLeadTime` to control how far in advance to refresh (default: 60 seconds).

```swift
// After login, store the token and its expiry
authStore.accessToken = loginResponse.body.accessToken
authStore.expiry = jwtExpiryDate(from: loginResponse.body.accessToken)

let client = RESTClient(configuration: RESTConfiguration(
    tokenExpiryDate: { authStore.expiry },
    preemptiveRefreshLeadTime: 60,   // refresh 60 s before expiry
    refreshToken: { /* same as above */ },
    applyToken: { token, request in
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
))
```

## Key types

| Type | Role |
|---|---|
| `RESTClient` | Main actor — create once, reuse everywhere |
| `RESTRequest` | Describes a single HTTP request |
| `RESTResponse<T>` | Decoded response body + `HTTPURLResponse` |
| `RESTConfiguration` | All client behaviour in one place |
| `RetryPolicy` | `maxAttempts` + `delay` |
| `CachePolicy` | `ttl` (seconds) |
| `RESTError` | Typed error thrown by `send` |
| `jwtExpiryDate(from:)` | Extracts `exp` claim from a JWT as a `Date` |
