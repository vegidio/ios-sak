//
//  TimeUnit.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-01-30.
//

import Foundation

public enum TimeUnit: Int {
    case second = 1
    case minute = 60
    case hour = 3_600
    case day = 86_400
    case week = 604_800
    case month = 2_592_000
    case year = 31_536_000

    public func toSeconds(value: Int) -> Int {
        rawValue * value
    }
}
