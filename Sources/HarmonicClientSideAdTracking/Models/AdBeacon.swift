//
//  AdBeacon.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public class AdBeacon: Codable {
    public var adBreaks: [AdBreak]
    public var dataRange: DataRange?
    
    init(adBreaks: [AdBreak], dataRange: DataRange? = nil) {
        self.adBreaks = adBreaks
        self.dataRange = dataRange
    }
}
