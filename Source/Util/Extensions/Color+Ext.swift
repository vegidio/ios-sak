//
//  Color+Ext.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-03-20.
//

import Foundation
import SwiftUI

public extension Color {
    /// Converts a hexadecimal value to Color
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex & 0xFF0000) >> 16) / 255.0,
            green: Double((hex & 0x00FF00) >> 8) / 255.0,
            blue: Double(hex & 0x0000FF) / 255.0,
            opacity: alpha
        )
    }
}
