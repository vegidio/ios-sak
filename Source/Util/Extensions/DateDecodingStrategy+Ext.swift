// swiftlint:disable:this file_name
//
//  DateDecodingStrategy+Ext.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-01-30.
//

import Foundation

public extension JSONDecoder.DateDecodingStrategy {
    /// A complete implementation of the ISO8601 date decoding that supports dates with time with and without fractions.
    static let iso8601Complete = custom { decoder in
        let container = try! decoder.singleValueContainer()
        let dateStr = try! container.decode(String.self)
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        var temp = dateFormatter.date(from: dateStr)

        if temp == nil {
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            temp = dateFormatter.date(from: dateStr)
        }

        guard let date = temp else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateStr)"
            )
        }

        return date
    }
}
