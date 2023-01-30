//
//  HarmonicAdTracker+Utilities.swift
//  
//
//  Created by Michael on 27/1/2023.
//

import Foundation

extension HarmonicAdTracker {
    
    static func mergePods(existingPods: inout [AdBreak], pods: [AdBreak]) -> Bool {
        var updated = false
        
        let originalLength = existingPods.count
        existingPods.removeAll { pod in
            !pods.contains(where: { $0.id == pod.id })
        }
        updated = originalLength != existingPods.count
        
        for pod in pods {
            let existingIndex = existingPods.firstIndex(where: { $0.id == pod.id })
            var currentIndex = existingPods.count
            if let existingIndex = existingIndex {
                currentIndex = existingIndex
                if existingPods[existingIndex].duration != pod.duration {
                    existingPods[existingIndex].duration = pod.duration
                    updated = true
                }
            } else {
                let newPod = AdBreak(id: pod.id,
                                     startTime: pod.startTime,
                                     duration: pod.duration,
                                     ads: [])
                existingPods.append(newPod)
                updated = true
            }
            updated = mergeAds(existingAds: &existingPods[currentIndex].ads, ads: pod.ads) || updated
        }
        
        return updated
    }
    
    static func mergeAds(existingAds: inout [Ad], ads: [Ad]) -> Bool {
        var updated = false
            
        let originalLength = existingAds.count
        existingAds.removeAll { ad in
            !ads.contains(where: { $0.id == ad.id })
        }
        updated = originalLength != existingAds.count
        
        for ad in ads {
            let existingIndex = existingAds.firstIndex(where: { $0.id == ad.id })
            if let existingIndex = existingIndex {
                if existingAds[existingIndex].duration != ad.duration {
                    existingAds[existingIndex].duration = ad.duration
                    updated = true
                }
            } else {
                let newAd = Ad(id: ad.id,
                               startTime: ad.startTime,
                               duration: ad.duration,
                               trackingEvents: ad.trackingEvents.map({ trackingEvent in
                    return TrackingEvent(event: trackingEvent.event,
                                         startTime: trackingEvent.startTime,
                                         duration: trackingEvent.duration,
                                         signalingUrls: trackingEvent.signalingUrls,
                                         reportingState: .idle)})
                )
                existingAds.append(newAd)
                updated = true
            }
        }

        return updated
    }
    
}
