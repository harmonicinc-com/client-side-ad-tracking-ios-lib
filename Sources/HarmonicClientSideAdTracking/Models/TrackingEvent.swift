//
//  TrackingEvent.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public class TrackingEvent: Codable, Identifiable {
    public var id: UUID? = UUID()
    public var event: EventType?
    public var startTime: Double?
    public var duration: Double?
    public var signalingUrls: [String]
    public var reportingState: ReportingState?
    
    init(id: UUID? = nil, event: EventType? = nil, startTime: Double? = nil, duration: Double? = nil, signalingUrls: [String], reportingState: ReportingState? = nil) {
        self.id = id
        self.event = event
        self.startTime = startTime
        self.duration = duration
        self.signalingUrls = signalingUrls
        self.reportingState = reportingState
    }
}
