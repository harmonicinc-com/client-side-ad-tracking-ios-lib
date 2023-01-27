//
//  AdBreak.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public struct AdBreak: Codable, Identifiable {
    public var id: String?
    public var startTime: Double?
    public var duration: Double?
    public var ads: [Ad]
}
