//
//  ReportingState.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public enum ReportingState: String, Decodable {
    case idle
    case connecting
    case done
    case failed
}
