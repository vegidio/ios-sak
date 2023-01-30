//
//  ApiError.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-01-30.
//

import Foundation

public enum ApiError: Error {
    case invalidUrl
    case codable(Codable)
    case unknown(String)
}
