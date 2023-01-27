//
//  DataRange.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public struct DataRange: Codable {
    public var start: Double?
    public var end: Double?
    
    public init(start: Double?, end: Double?) {
        self.start = start
        self.end = end
    }
}
