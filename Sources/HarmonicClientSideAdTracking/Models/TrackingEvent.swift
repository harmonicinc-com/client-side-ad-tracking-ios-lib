//
//  TrackingEvent.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public class TrackingEvent: Decodable, Identifiable, Hashable, ObservableObject {
    public var id: UUID? = UUID()
    public var event: EventType?
    public var startTime: Double?
    public var duration: Double?
    public var signalingUrls: [String]
    
    @Published
    public var reportingState: ReportingState?
    
    public init(id: UUID? = nil, event: EventType? = nil, startTime: Double? = nil, duration: Double? = nil, signalingUrls: [String] = [], reportingState: ReportingState? = nil) {
        self.id = id
        self.event = event
        self.startTime = startTime
        self.duration = duration
        self.signalingUrls = signalingUrls
        self.reportingState = reportingState
    }
    
    enum CodingKeys: CodingKey {
        case event, startTime, duration, signalingUrls
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.event = try container.decodeIfPresent(EventType.self, forKey: .event)
        self.startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        self.signalingUrls = try container.decode([String].self, forKey: .signalingUrls)
    }
    
    public static func == (lhs: TrackingEvent, rhs: TrackingEvent) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
