//
//  Ad.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public struct Ad: Codable, Identifiable {
    public var id: String?
    public var startTime: Double?
    public var duration: Double?
    public var trackingEvents: [TrackingEvent]
}
