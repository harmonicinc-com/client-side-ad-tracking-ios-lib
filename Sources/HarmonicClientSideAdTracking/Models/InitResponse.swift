//
//  InitResponse.swift
//  HarmonicClientSideAdTracking
//
//  Created by Michael Leung on 14/04/2025.
//

import Foundation

struct InitResponse: Decodable {
    let manifestUrl: String
    let trackingUrl: String
}
