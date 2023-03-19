//
//  DurationTest.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-03-19.
//

import Foundation
import XCTest

class DurationTest: XCTestCase {
    func testUnitConverstion() {
        let duration1 = 1.hours
        let duration2 = 60.minutes

        XCTAssertTrue(duration1 == duration2)
    }
}
