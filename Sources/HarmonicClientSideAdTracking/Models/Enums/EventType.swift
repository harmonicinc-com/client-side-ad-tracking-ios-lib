//
//  EventType.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public enum EventType: String, Decodable {
    case pause
    case resume
    case mute
    case unmute
    case start
    case impression
    case firstQuartile
    case midpoint
    case thirdQuartile
    case complete
    case clickAbstractType
    case clickTracking
    case unknown
}
