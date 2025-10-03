//
//  AdMetadataHelper.swift
//  
//
//  Created by Michael on 9/5/2023.
//

import Foundation
import Combine

struct AdMetadataHelper {
    private static let EARLY_FETCH_MS: Double = 5_000
    
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
    
    static func requestAdMetadata(with metadataUrl: String) async throws -> AdBeacon {
        guard !metadataUrl.isEmpty else {
            throw HarmonicAdTrackerError.metadataError("The metadata URL is empty.")
        }
        
        let (data, _) = try await Utility.makeRequest(to: metadataUrl)        
        let adBeacon = try Self.decoder.decode(AdBeacon.self, from: data)
        
        guard let latestDataRange = adBeacon.dataRange,
              latestDataRange.start != nil,
              latestDataRange.end != nil else {
            throw HarmonicAdTrackerError.metadataError("No DataRange returned in metadata.")
        }
        
        return adBeacon
    }
    
    static func mergePods(_ existingPods: [AdBreak], with newPods: [AdBreak], playhead: Double, keepPodsForMs: Double) -> [AdBreak] {
        var existingPods = existingPods
        existingPods.removeAll { pod in
            (pod.startTime ?? 0) + (pod.duration ?? 0) + keepPodsForMs < playhead &&
            !newPods.contains(where: { $0.id == pod.id })
        }
        
        for pod in newPods {
            let existingIndex = existingPods.firstIndex(where: { $0.id == pod.id })
            var currentIndex = existingPods.count
            if let existingIndex = existingIndex {
                currentIndex = existingIndex
                existingPods[existingIndex].duration = pod.duration
            } else {
                let newPod = AdBreak(id: pod.id,
                                     startTime: pod.startTime,
                                     duration: pod.duration,
                                     ads: [])
                existingPods.append(newPod)
            }
            mergeAds(&existingPods[currentIndex].ads, with: pod.ads)
        }
        
        return existingPods.sorted(by: { ($0.startTime ?? 0) < ($1.startTime ?? 0) })
    }
    
    private static func mergeAds(_ existingAds: inout [Ad], with newAds: [Ad]) {
        existingAds.removeAll { ad in
            !newAds.contains(where: { $0.id == ad.id })
        }
        
        for ad in newAds {
            if let existingIndex = existingAds.firstIndex(where: { $0.id == ad.id }) {
                existingAds[existingIndex].duration = ad.duration
            } else {
                let newAd = Ad(id: ad.id,
                               startTime: ad.startTime,
                               duration: ad.duration,
                               trackingEvents: ad.trackingEvents.filter( { $0.event != .unknown } ).map({ trackingEvent in
                    return TrackingEvent(event: trackingEvent.event,
                                         startTime: trackingEvent.startTime,
                                         duration: trackingEvent.duration,
                                         signalingUrls: trackingEvent.signalingUrls,
                                         reportingState: .idle)})
                )
                existingAds.append(newAd)
            }
        }
        
        existingAds = existingAds.sorted(by: { ($0.startTime ?? 0) < ($1.startTime ?? 0) })
    }
    
}
