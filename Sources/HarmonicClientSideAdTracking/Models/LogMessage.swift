//
//  LogMessage.swift
//  
//
//  Created by Michael on 12/5/2023.
//

import Foundation

public struct LogMessage: Identifiable {
    public let id: UUID? = UUID()
    public internal(set) var timeStamp: Double
    public internal(set) var message: String
    public internal(set) var isError: Bool
    
    public init(timeStamp: Double, message: String, isError: Bool = false) {
        self.timeStamp = timeStamp
        self.message = message
        self.isError = isError
    }
}
