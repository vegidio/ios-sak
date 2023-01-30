//
//  Inject.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-01-30.
//

import Foundation
import SwiftUI

public protocol Resolver {
    func resolve<T>(_ type: T.Type, name: String?) -> T?
}

public enum InjectSettings {
    public static var resolver: Resolver?
}

@propertyWrapper
public struct InjectObject<T>: DynamicProperty where T: ObservableObject {
    public var wrappedValue: T
    public var projectedValue: ObservedObject<T>

    public init(name: String? = nil, resolver: Resolver? = nil) {
        guard let resolver = resolver ?? InjectSettings.resolver else {
            fatalError("Make sure InjectSettings.resolver is set!")
        }

        guard let value = resolver.resolve(T.self, name: name) else {
            fatalError("Could not resolve non-optional \(T.self)")
        }

        wrappedValue = value
        projectedValue = ObservedObject(wrappedValue: value)
    }
}

@propertyWrapper
public struct Inject<T> {
    public var wrappedValue: T

    public init(name: String? = nil, resolver: Resolver? = nil) {
        guard let resolver = resolver ?? InjectSettings.resolver else {
            fatalError("Make sure InjectSettings.resolver is set!")
        }

        guard let value = resolver.resolve(T.self, name: name) else {
            fatalError("Could not resolve non-optional \(T.self)")
        }

        wrappedValue = value
    }
}
