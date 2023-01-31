//
//  AdBreak.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public class AdBreak: Decodable, Identifiable, ObservableObject {
    public var id: String?
    public var startTime: Double?
    public var duration: Double?
    public var expanded: Bool?
    
    @Published
    public var ads: [Ad]
    
    public init(id: String? = nil, startTime: Double? = nil, duration: Double? = nil, ads: [Ad] = []) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.ads = ads
    }
    
    enum CodingKeys: CodingKey {
        case id, startTime, duration, ads
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        self.ads = try container.decode([Ad].self, forKey: .ads)
    }
}
