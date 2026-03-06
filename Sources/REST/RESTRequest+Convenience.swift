import Foundation

public extension RESTRequest {
    /// Creates a request with an `Encodable` body, automatically JSON-encoding it
    /// and setting `Content-Type: application/json` unless already provided.
    init<B: Encodable>(
        url: String,
        method: HTTPMethod = .post,
        headers: [String: String] = [:],
        body encodable: B,
        encoder: JSONEncoder = JSONEncoder(),
        queryParameters: [String: String] = [:],
        skipAuth: Bool = false
    ) throws {
        let data = try encoder.encode(encodable)
        var merged = headers
        if merged["Content-Type"] == nil {
            merged["Content-Type"] = "application/json"
        }
        self.init(
            url: url,
            method: method,
            headers: merged,
            body: data as Data?,
            queryParameters: queryParameters,
            skipAuth: skipAuth
        )
    }
}
