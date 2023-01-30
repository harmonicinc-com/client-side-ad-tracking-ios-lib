//
//  HarmonicAdTracker+Utilities.swift
//  
//
//  Created by Michael on 27/1/2023.
//

import Foundation

extension HarmonicAdTracker {
    
    static func mergePods(existingPods: inout [AdBreak], pods: [AdBreak]) {
        existingPods.removeAll { pod in
            !pods.contains(where: { $0.id == pod.id })
        }
        
        for pod in pods {
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
            mergeAds(existingAds: &existingPods[currentIndex].ads, ads: pod.ads)
        }
    }
    
    static func mergeAds(existingAds: inout [Ad], ads: [Ad]) {
        existingAds.removeAll { ad in
            !ads.contains(where: { $0.id == ad.id })
        }
        
        for ad in ads {
            if let existingIndex = existingAds.firstIndex(where: { $0.id == ad.id }) {
                existingAds[existingIndex].duration = ad.duration
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
            }
        }
    }
    
}
