//
//  MaterialColorScheme.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-03-20.
//

import Foundation
import SwiftUI

public protocol MaterialColorScheme {
    var primary: Color { get }
    var onPrimary: Color { get }
    var primaryContainer: Color { get }
    var onPrimaryContainer: Color { get }
    var secondary: Color { get }
    var onSecondary: Color { get }
    var secondaryContainer: Color { get }
    var onSecondaryContainer: Color { get }
    var tertiary: Color { get }
    var onTertiary: Color { get }
    var tertiaryContainer: Color { get }
    var onTertiaryContainer: Color { get }
    var error: Color { get }
    var errorContainer: Color { get }
    var onError: Color { get }
    var onErrorContainer: Color { get }
    var background: Color { get }
    var onBackground: Color { get }
    var surface: Color { get }
    var onSurface: Color { get }
    var surfaceVariant: Color { get }
    var onSurfaceVariant: Color { get }
    var outline: Color { get }
    var inverseOnSurface: Color { get }
    var inverseSurface: Color { get }
    var inversePrimary: Color { get }
    var surfaceTint: Color { get }
}
