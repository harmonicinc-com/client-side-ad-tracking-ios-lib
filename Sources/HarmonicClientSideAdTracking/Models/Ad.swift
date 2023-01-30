//
//  Ad.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public class Ad: Decodable, Identifiable, ObservableObject {
    public var id: String?
    public var startTime: Double?
    public var duration: Double?
    
    @Published
    public var trackingEvents: [TrackingEvent]
    
    public init(id: String? = nil, startTime: Double? = nil, duration: Double? = nil, trackingEvents: [TrackingEvent] = []) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.trackingEvents = trackingEvents
    }
    
    enum CodingKeys: CodingKey {
        case id, startTime, duration, trackingEvents
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        self.trackingEvents = try container.decode([TrackingEvent].self, forKey: .trackingEvents)
    }
}
