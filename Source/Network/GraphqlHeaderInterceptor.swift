//
//  GraphqlHeaderInterceptor.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-02-01.
//

import Apollo
import ApolloAPI
import Foundation

internal class GraphqlHeaderInterceptor: ApolloInterceptor {
    internal var headers: [String: String] = [:]
    internal var requestHeaders: [String: [String: String]] = [:]

    internal func interceptAsync<Operation: ApolloAPI.GraphQLOperation>(
        chain: Apollo.RequestChain,
        request: Apollo.HTTPRequest<Operation>,
        response: Apollo.HTTPResponse<Operation>?,
        completion: @escaping (Result<Apollo.GraphQLResult<Operation.Data>, Error>) -> Void
    ) {
        // Adding permanent headers
        request.additionalHeaders.merge(headers) { _, new in new }

        // Adding temporary headers
        let name = "\(request.operation)"
        let tempHeaders = requestHeaders[name] ?? [:]
        tempHeaders.forEach { key, value in
            request.additionalHeaders[key] = value
        }

        chain.proceedAsync(request: request, response: response, completion: completion)

        // Removing temporary headers
        requestHeaders.removeValue(forKey: name)
        tempHeaders.forEach { key, _ in
            request.additionalHeaders.removeValue(forKey: key)
        }
    }
}
