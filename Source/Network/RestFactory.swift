//
//  RestFactory.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-01-16.
//

import Alamofire
import Combine
import Foundation
import SAKUtil

open class RestFactory {
    private let baseUrl: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue.global(qos: .background)

    public var headers: [String: String] = [:]

    public init(baseUrl: String) {
        guard let url = URL(string: baseUrl) else {
            fatalError("The REST base URL is invalid.")
        }

        self.baseUrl = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601Complete
    }

    /// Sends a request that doesn't expect a response body
    public func sendRequest(
        _ method: HTTPMethod,
        _ uri: String,
        params: (some Encodable) = ["": ""],
        headers: HTTPHeaders = HTTPHeaders()
    ) -> AnyPublisher<Void, ApiError> {
        let (url, paramEncoder, mergedHeaders) = normalizeParameters(.get, uri, headers)

        return AF.request(
            url,
            method: method,
            parameters: params,
            encoder: paramEncoder,
            headers: mergedHeaders
        )
        .publishUnserialized(queue: queue)
        .value()
        .map { _ in }
        .mapError { ApiError.unknown($0.localizedDescription) }
        .eraseToAnyPublisher()
    }

    /// Sends a requests that expects a response body
    public func sendRequest<T: Codable>(
        _ method: HTTPMethod,
        _ uri: String,
        params: (some Encodable) = ["": ""],
        headers: HTTPHeaders = HTTPHeaders()
    ) -> AnyPublisher<T, ApiError> {
        let (url, paramEncoder, mergedHeaders) = normalizeParameters(.get, uri, headers)

        return AF.request(
            url,
            method: method,
            parameters: params,
            encoder: paramEncoder,
            headers: mergedHeaders
        )
        .publishDecodable(type: T.self, queue: queue, decoder: decoder)
        .value()
        .mapError { ApiError.unknown($0.localizedDescription) }
        .eraseToAnyPublisher()
    }

    // MARK: - Private methods

    private func normalizeParameters(
        _ method: HTTPMethod,
        _ uri: String,
        _ headers: HTTPHeaders
    ) -> (URL, ParameterEncoder, HTTPHeaders) {
        let url = baseUrl.appendingPathComponent(uri)
        let paramEncoder: ParameterEncoder = method == .get ? URLEncodedFormParameterEncoder
            .default : JSONParameterEncoder.default
        let mergedHeaders = HTTPHeaders(self.headers.merging(headers.dictionary) { _, new in new })

        return (url, paramEncoder, mergedHeaders)
    }
}
