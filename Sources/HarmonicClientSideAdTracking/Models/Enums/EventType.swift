//
//  EventType.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public enum EventType: String, Decodable {
    case start
    case impression
    case firstQuartile
    case midpoint
    case thirdQuartile
    case complete
    case unknown
    
    public init(from decoder: Decoder) throws {
        self = try EventType(rawValue: decoder.singleValueContainer().decode(RawValue.self)) ?? .unknown
    }
}
