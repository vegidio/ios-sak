//
//  File.swift
//
//
//  Created by Vinicius Egidio on 2023-02-01.
//

import Foundation
import SAKUtil
import XCTest

class StringExtTest: XCTestCase {
    func testLeftOfString() {
        let test = "Vinicius de Oliveira Egidio"
        XCTAssertTrue(test.leftOf(substring: " de Oliveira") == "Vinicius")
    }

    func testRightOfString() {
        let test = "Vinicius de Oliveira Egidio"
        XCTAssertTrue(test.rightOf(substring: "Oliveira ") == "Egidio")
    }
}
