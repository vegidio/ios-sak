import Foundation

/// Extracts the expiry date from a JWT token's payload `exp` claim.
///
/// - Important: This only base64url-decodes and reads the payload — it does **not** verify the
///   token's signature. Use the result solely for expiry-driven refresh scheduling; never treat a
///   decoded value as proof of authenticity for an authorization decision.
///
/// Usage:
/// ```swift
/// if let expiry = jwtExpiryDate(from: accessToken) {
///     authStore.expiry = expiry
/// }
/// ```
///
/// - Parameter token: A JWT string in the format `header.payload.signature`.
/// - Returns: The expiry `Date`, or `nil` if the token is malformed or has no `exp` claim.
public func jwtExpiryDate(from token: String) -> Date? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }

    // JWT uses base64url encoding (- and _ instead of + and /), without padding
    var base64 = String(parts[1])
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - base64.count % 4) % 4
    base64 += String(repeating: "=", count: padding)

    guard
        let data = Data(base64Encoded: base64),
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let exp = payload["exp"] as? TimeInterval
    else { return nil }

    return Date(timeIntervalSince1970: exp)
}
