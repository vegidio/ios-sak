import Foundation

/// A placeholder response body for endpoints that return no content (e.g. `204 No Content`,
/// `205`, or any successful empty body — common for `DELETE`/`PUT`).
///
/// Usually you don't reference this type directly: declare a `@Service` method with **no return
/// type** and the generated `@discardableResult` method returns `RESTResponse<EmptyResponse>`:
/// ```swift
/// @Delete("/users/{id}")
/// func deleteUser(id: Path<Int>) async throws
/// ```
/// Writing `-> EmptyResponse` explicitly is also accepted (non-discardable). `RESTClient.send`
/// returns an `EmptyResponse` for empty bodies instead of failing the JSON decoder on empty input.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
