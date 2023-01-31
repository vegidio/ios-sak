//
//  NetworkState.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-01-31.
//

import Foundation

public enum NetworkState {
    case idle
    case loading
    case error(Error?)
}
