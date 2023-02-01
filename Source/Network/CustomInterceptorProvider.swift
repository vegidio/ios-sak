//
//  CustomInterceptorProvider.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-02-01.
//

import Apollo
import ApolloAPI
import Foundation

internal class CustomInterceptorProvider: DefaultInterceptorProvider {
    private let store: ApolloStore
    private let customInterceptors: [ApolloInterceptor]

    internal init(store: ApolloStore, customInterceptors: [ApolloInterceptor]) {
        self.store = store
        self.customInterceptors = customInterceptors

        super.init(store: store)
    }

    override internal func interceptors(for _: some GraphQLOperation) -> [ApolloInterceptor] {
        customInterceptors + [
            MaxRetryInterceptor(),
            CacheReadInterceptor(store: store),
            NetworkFetchInterceptor(client: URLSessionClient()),
            ResponseCodeInterceptor(),
            JSONResponseParsingInterceptor(),
            AutomaticPersistedQueryInterceptor(),
            CacheWriteInterceptor(store: store)
        ]
    }
}
