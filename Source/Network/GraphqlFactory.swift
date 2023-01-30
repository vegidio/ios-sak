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
    private let client: ApolloClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue.global(qos: .background)

    public var headers: [String: String] = [:]

    public init(url: String) {
        guard let url = URL(string: url) else {
            fatalError("The GraphQL URL is invalid.")
        }

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601Complete

        client = ApolloClient(url: url)
    }

    public func sendMutation<T: Codable>(mutation: some GraphQLMutation) -> AnyPublisher<T, ApiError> {
        Future<T, ApiError> { promise in
            self.client.perform(mutation: mutation, queue: self.queue) { result in
                switch result {
                case let .success(response):
                    let json = response.data?.__data._data
                    let value: T? = self.jsonToCodable(json: json)

                    guard let value else {
                        promise(.failure(.unknown("Empty response")))
                        return
                    }

                    promise(.success(value))

                case let .failure(error):
                    promise(.failure(.unknown(error.localizedDescription)))
                }
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - Private methods

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
