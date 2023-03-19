//
//  Duration.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-03-19.
//

import Foundation

public struct Duration: Equatable {
    public let milliseconds: Double
    public var seconds: Double { milliseconds / 1_000 }
    public var minutes: Double { milliseconds / 60_000 }
    public var hours: Double { milliseconds / 3_600_000 }
    public var days: Double { milliseconds / 86_400_000 }

    public var wholeMilliseconds: Int { Int(milliseconds) }
    public var wholeSeconds: Int { Int(seconds) }
    public var wholeMinutes: Int { Int(minutes) }
    public var wholeHours: Int { Int(hours) }
    public var wholeDays: Int { Int(days) }

    public static func == (lhs: Duration, rhs: Duration) -> Bool {
        lhs.milliseconds == rhs.milliseconds
    }
}

public extension Double {
    var milliseconds: Duration { Duration(milliseconds: self) }
    var seconds: Duration { Duration(milliseconds: self * 1_000) }
    var minutes: Duration { Duration(milliseconds: self * 60_000) }
    var hours: Duration { Duration(milliseconds: self * 3_600_000) }
    var days: Duration { Duration(milliseconds: self * 86_400_000) }
}
