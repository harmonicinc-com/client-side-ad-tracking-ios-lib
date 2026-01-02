//
//  InitResponse.swift
//  HarmonicClientSideAdTracking
//
//  Created by Michael Leung on 14/04/2025.
//

import Foundation

public struct InitResponse: Decodable {
    public let manifestUrl: String
    public let trackingUrl: String
    
    public init(manifestUrl: String, trackingUrl: String) {
        self.manifestUrl = manifestUrl
        self.trackingUrl = trackingUrl
    }
}
