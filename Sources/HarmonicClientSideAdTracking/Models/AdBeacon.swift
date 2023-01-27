//
//  AdBeacon.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public struct AdBeacon: Codable {
    public var adBreaks: [AdBreak]
    public var dataRange: DataRange?
}
