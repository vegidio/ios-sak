//
//  Lazy.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-01-30.
//

import Foundation
import SwiftUI

/// Lazily initialize a view, allocation its dependencies when a view is presented for the first time. Useful with
/// NavigationStack.
public struct Lazy<Content: View>: View {
    private let build: () -> Content

    public var body: Content {
        build()
    }

    public init(@ViewBuilder _ build: @escaping () -> Content) {
        self.build = build
    }
}
