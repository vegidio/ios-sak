import Foundation

// MARK: - Parameter markers

// Swift does not allow a macro/attribute to be attached to a function parameter, so the
// per-parameter tags are transparent generic type aliases instead. `Path<Int>` is literally
// `Int` to the compiler (zero runtime cost), but `@Service` reads the written type to classify
// each parameter. The wire key for a parameter is its name.

/// Marks a parameter that substitutes a `{name}` placeholder in the request path.
public typealias Path<T> = T

/// Marks a parameter that is sent as a URL query item named after the parameter.
public typealias Query<T> = T

/// Marks the request body parameter (JSON-encoded). At most one per request.
public typealias Body<T> = T

/// Marks a parameter sent as a request header named after the parameter.
public typealias Header<T> = T

// MARK: - Service & method annotations

/// Generates a `<Protocol>Client` struct implementing the annotated protocol. Each requirement
/// must carry one HTTP-method annotation and return `RESTResponse<T>`.
@attached(peer, names: suffixed(Client))
public macro Service() = #externalMacro(module: "RESTMacros", type: "ServiceMacro")

/// Declares a GET request to `path`.
@attached(peer)
public macro Get(_ path: String) = #externalMacro(module: "RESTMacros", type: "GetMacro")

/// Declares a POST request to `path`.
@attached(peer)
public macro Post(_ path: String) = #externalMacro(module: "RESTMacros", type: "PostMacro")

/// Declares a PUT request to `path`.
@attached(peer)
public macro Put(_ path: String) = #externalMacro(module: "RESTMacros", type: "PutMacro")

/// Declares a PATCH request to `path`.
@attached(peer)
public macro Patch(_ path: String) = #externalMacro(module: "RESTMacros", type: "PatchMacro")

/// Declares a DELETE request to `path`.
@attached(peer)
public macro Delete(_ path: String) = #externalMacro(module: "RESTMacros", type: "DeleteMacro")

/// Opts the request out of automatic token injection (sets `RESTRequest.skipAuth`).
@attached(peer)
public macro SkipAuth() = #externalMacro(module: "RESTMacros", type: "SkipAuthMacro")

/// Enables in-memory response caching.
///
/// Apply it to the `@Service` protocol to cache every request by default, and/or to individual
/// methods to enable or override caching for that request.
///
/// - Parameters:
///   - ttl: How long a cached response stays valid, in seconds. When the argument is omitted the
///     entry never expires (it is kept until evicted by `maxEntries`). A method-level `@Cacheable`
///     with no `ttl` removes the TTL inherited from the service level while keeping caching on.
///   - maxEntries: Maximum number of responses kept in the shared in-memory store. Only honored on
///     the `@Service` protocol; specifying it on a method is an error.
@attached(peer)
public macro Cacheable(ttl: TimeInterval? = nil, maxEntries: Int? = nil) = #externalMacro(module: "RESTMacros", type: "CacheableMacro")

/// Opts a method out of caching when the `@Service` protocol enables it with `@Cacheable`.
@attached(peer)
public macro NoCache() = #externalMacro(module: "RESTMacros", type: "NoCacheMacro")
