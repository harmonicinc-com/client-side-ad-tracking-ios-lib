//
//  AdBreak.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public class AdBreak: Codable, Identifiable {
    public var id: String?
    public var startTime: Double?
    public var duration: Double?
    public var ads: [Ad]
    
    init(id: String? = nil, startTime: Double? = nil, duration: Double? = nil, ads: [Ad]) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.ads = ads
    }
}
