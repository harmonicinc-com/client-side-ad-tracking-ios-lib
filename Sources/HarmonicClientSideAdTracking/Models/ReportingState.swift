//
//  File.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public enum ReportingState: String, Codable {
    case idle
    case connecting
    case done
    case failed
}
