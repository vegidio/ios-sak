//
//  String+Ext.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-02-01.
//

import Foundation

public extension String {
    func leftOf(substring: String) -> String {
        guard let range = range(of: substring) else {
            return self
        }

        return String(self[..<range.lowerBound])
    }

    func rightOf(substring: String) -> String {
        guard let range = range(of: substring) else {
            return self
        }

        return String(self[range.upperBound...])
    }
}
