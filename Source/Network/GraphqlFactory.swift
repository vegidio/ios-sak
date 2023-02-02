//
//  GraphqlFactory.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-01-30.
//

import Apollo
import ApolloAPI
import Combine
import Foundation

open class GraphqlFactory {
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var client: ApolloClient!
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue.global(qos: .background)
    private let headerInterceptor = GraphqlHeaderInterceptor()

    private let store: ApolloStore = {
        let cache = InMemoryNormalizedCache()
        return ApolloStore(cache: cache)
    }()

    public var headers: [String: String] {
        get { headerInterceptor.headers }
        set(value) { headerInterceptor.headers = value }
    }

    public init(url: String) {
        guard let url = URL(string: url) else {
            fatalError("The GraphQL URL is invalid.")
        }

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601Complete
        client = createClient(url: url)
    }

    public func sendQuery<T: Codable>(
        query: some GraphQLQuery,
        headers: [String: String] = [:]
    ) -> AnyPublisher<T, ApiError> {
        Future<T, ApiError> { [weak self] promise in
            guard let self else { return }
            let name = "\(query)"
            self.headerInterceptor.requestHeaders[name] = headers

            self.client.fetch(query: query, queue: self.queue) { result in
                switch result {
                case let .success(response):
                    let json = response.data?.__data._data
                    let value: T? = self.jsonToCodable(json: json)

                    guard let value else {
                        let error = response.errors?.first
                        promise(.failure(ApiError.unknown(error?.message ?? "Unknown")))
                        return
                    }

                    promise(.success(value))

                case let .failure(error):
                    promise(.failure(.unknown(error.localizedDescription)))
                }
            }
        }.eraseToAnyPublisher()
    }

    public func sendMutation<T: Codable>(
        mutation: some GraphQLMutation,
        headers: [String: String] = [:]
    ) -> AnyPublisher<T, ApiError> {
        Future<T, ApiError> { [weak self] promise in
            guard let self else { return }
            let name = "\(mutation)"
            self.headerInterceptor.requestHeaders[name] = headers

            self.client.perform(mutation: mutation, queue: self.queue) { result in
                switch result {
                case let .success(response):
                    let json = response.data?.__data._data
                    let value: T? = self.jsonToCodable(json: json)

                    guard let value else {
                        let error = response.errors?.first
                        promise(.failure(ApiError.unknown(error?.message ?? "Unknown")))
                        return
                    }

                    promise(.success(value))

                case let .failure(error):
                    promise(.failure(.unknown(error.localizedDescription)))
                }
            }
        }.eraseToAnyPublisher()
    }

    public func clearCache() {
        store.clearCache()
    }

    // MARK: - Private methods

    private func createClient(url: URL) -> ApolloClient {
        let provider = CustomInterceptorProvider(store: store, customInterceptors: [headerInterceptor])
        let requestChainTransport = RequestChainNetworkTransport(
            interceptorProvider: provider,
            endpointURL: url
        )

        return ApolloClient(networkTransport: requestChainTransport, store: store)
    }

    private func jsonToCodable<T: Codable>(json: JSONObject?) -> T? {
        guard
            let key = json?.first?.key,
            let data = json?[key]
        else {
            return nil
        }

        let newJson: JSONObject = ["data": data]

        guard
            let jsonData = try? JSONSerialization.data(withJSONObject: newJson),
            let value = try? decoder.decode(T.self, from: jsonData)
        else {
            return nil
        }

        return value
    }
}
