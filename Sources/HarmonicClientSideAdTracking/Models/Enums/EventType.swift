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
    case mute
    case unmute
    case pause
    case resume
    case unknown
    
    public init(from decoder: Decoder) throws {
        self = try EventType(rawValue: decoder.singleValueContainer().decode(RawValue.self)) ?? .unknown
    }
    
    /// Returns true if this event type is triggered by user actions
    /// rather than automatically by playhead position.
    public var isPlayerInitiated: Bool {
        switch self {
        case .mute, .unmute, .pause, .resume:
            return true
        default:
            return false
        }
    }
}
