//
//  Ad.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public class Ad: Codable, Identifiable {
    public var id: String?
    public var startTime: Double?
    public var duration: Double?
    public var trackingEvents: [TrackingEvent]
    
    init(id: String? = nil, startTime: Double? = nil, duration: Double? = nil, trackingEvents: [TrackingEvent]) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.trackingEvents = trackingEvents
    }
}
