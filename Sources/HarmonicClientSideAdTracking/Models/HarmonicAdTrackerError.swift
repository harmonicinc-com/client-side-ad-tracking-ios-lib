//
//  HarmonicAdTrackerError.swift
//  
//
//  Created by Michael on 9/5/2023.
//

import Foundation

enum HarmonicAdTrackerError: Error {
    case networkError(String)
    case metadataError(String)
    case beaconError(String)
}
