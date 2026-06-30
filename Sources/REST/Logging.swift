import Foundation
import Alamofire

/// A sink that receives one formatted, multi-line log entry per request and per response.
///
/// Mirrors the TypeScript `rn-sak` library's `LoggingPolicy`. Wire it to `print` in development
/// (e.g. `logging: { print($0) }`) or to a custom sink. It runs on **every** request — keep it
/// cheap, and gate it behind a debug flag in production builds.
public typealias LoggingPolicy = @Sendable (String) -> Void

/// Formats requests and responses as OkHttp-style `HttpLoggingInterceptor` BODY-level blocks.
///
/// The output mirrors the TypeScript `rn-sak` library: a `--> METHOD URL` request block (headers,
/// a synthesized `Content-Length`, then the body) and a `<-- STATUS (…ms)` response block (headers,
/// then the body), with a `<-- HTTP FAILED: …` line for transport failures with no response.
enum RequestLogger {
    /// Builds the request log block for an outgoing (already adapted) `URLRequest`.
    static func formatRequest(_ urlRequest: URLRequest) -> String {
        let method = urlRequest.httpMethod ?? "GET"
        let url = urlRequest.url?.absoluteString ?? "(no url)"
        var lines = ["--> \(method) \(url)"]

        let body = urlRequest.httpBody
        var headers = urlRequest.allHTTPHeaderFields ?? [:]
        // Synthesize a Content-Length from the body when the request didn't set one itself.
        if let body, headers["Content-Length"] == nil {
            headers["Content-Length"] = String(body.count)
        }
        lines.append(contentsOf: headerLines(headers))

        if let body {
            lines.append("")
            lines.append(bodyString(body))
        }
        lines.append("--> END \(method)")
        return lines.joined(separator: "\n")
    }

    /// Builds the response log block from Alamofire's parsed response. Emits a single
    /// `<-- HTTP FAILED: …` line when the request failed before producing an HTTP response.
    /// Generic over the serializer's `Value` (we only read the response, raw data, metrics and error).
    static func formatResponse<Value>(_ response: DataResponse<Value, AFError>) -> String {
        guard let http = response.response else {
            let message = response.error?.localizedDescription ?? "unknown error"
            return "<-- HTTP FAILED: \(message)"
        }

        let status = http.statusCode
        let statusText = HTTPURLResponse.localizedString(forStatusCode: status)
        var statusLine = "<-- \(status) \(statusText)"
        if let duration = response.metrics?.taskInterval.duration {
            statusLine += " (\(Int((duration * 1000).rounded()))ms)"
        }
        var lines = [statusLine]

        let headers = Dictionary(uniqueKeysWithValues: http.allHeaderFields.map {
            (String(describing: $0.key), String(describing: $0.value))
        })
        lines.append(contentsOf: headerLines(headers))

        if let body = response.data, !body.isEmpty {
            lines.append("")
            lines.append(bodyString(body))
        }
        lines.append("<-- END HTTP")
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Renders headers as `Name: Value` lines, sorted for deterministic output.
    private static func headerLines(_ headers: [String: String]) -> [String] {
        headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
    }

    /// Decodes a body as UTF-8, falling back to a placeholder for non-UTF-8 (binary) payloads.
    private static func bodyString(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "<binary \(data.count)-byte body>"
    }
}

/// Alamofire `EventMonitor` that forwards each request and response to a `LoggingPolicy`.
///
/// A custom monitor (rather than `ClosureEventMonitor`) is required because the engine serializes
/// with `serializingData`, which fires the **generic** `request(_:didParseResponse:)` hook;
/// `ClosureEventMonitor` only exposes the non-generic `DataResponse<Data?, AFError>` variant.
final class LoggingEventMonitor: EventMonitor, @unchecked Sendable {
    let queue = DispatchQueue(label: "io.sak.rest.logging")
    private let logging: LoggingPolicy

    init(logging: @escaping LoggingPolicy) {
        self.logging = logging
    }

    /// Fires with the adapted request (Authorization header injected), once per retry attempt.
    func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        logging(RequestLogger.formatRequest(urlRequest))
    }

    /// Fires once when the response serializer parses the final response.
    func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
        logging(RequestLogger.formatResponse(response))
    }
}
