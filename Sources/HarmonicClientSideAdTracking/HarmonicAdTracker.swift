//
//  HarmonicAdTracker.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation
import os

let AD_END_TRACKING_EVENT_TIME_TOLERANCE: Double = 500
let MAX_TOLERANCE_IN_SPEED: Double = 2
let MAX_TOLERANCE_EVENT_END_TIME: Double = 1_000
let KEEP_PODS_FOR_MS: Double = 1_000 * 60 * 2   // 2 minutes

enum HarmonicAdTrackerError: Error {
    case runtimeError(String)
}

@MainActor
public class HarmonicAdTracker: ClientSideAdTracker, ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.module.bundleIdentifier!,
        category: String(describing: HarmonicAdTracker.self)
    )
    
    @Published
    public private(set) var adPods: [AdBreak] = []
    
    private var lastPlayheadTime: Double = 0
    private var lastPlayheadUpdateTime: Double = 0
    
    public init(adPods: [AdBreak] = [], lastPlayheadTime: Double = 0, lastPlayheadUpdateTime: Double = 0) {
        self.adPods = adPods
        self.lastPlayheadTime = lastPlayheadTime
        self.lastPlayheadUpdateTime = lastPlayheadUpdateTime
    }
    
    public func updatePods(_ pods: [AdBreak]?) async {
        if let pods = pods {
            mergePods(pods)
        }
    }
    
    public func getPlayheadTime() async -> Double {
        return lastPlayheadTime
    }
    
    public func needSendBeacon(time: Double) async {
        let now = Date().timeIntervalSince1970 * 1_000
        if now == lastPlayheadUpdateTime {
            return
        }
        
        let speed = (time - lastPlayheadTime) / (now - lastPlayheadUpdateTime)
        if 0.nextUp...MAX_TOLERANCE_IN_SPEED ~= speed {
            await iterateTrackingEvents(time0: lastPlayheadTime, time1: time)
        }
        lastPlayheadTime = time
        lastPlayheadUpdateTime = now
    }
    
    // MARK: Private
    
    private func sendBeacon(_ trackingEvent: TrackingEvent) async {
        trackingEvent.reportingState = .connecting
        
        do {
            try await withThrowingTaskGroup(of: (String, HTTPURLResponse).self,
                                            returning: Void.self,
                                            body: { group in
                
                for urlString in trackingEvent.signalingUrls {
                    group.addTask {
                        guard let url = URL(string: urlString) else {
                            throw HarmonicAdTrackerError.runtimeError("Invalid signaling url: \(urlString)")
                        }
                        let (_, response) = try await URLSession.shared.data(from: url)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw HarmonicAdTrackerError.runtimeError("Invalid URLResponse for url: \(urlString)")
                        }
                        return (urlString, httpResponse)
                    }
                }
                
                for try await (urlString, response) in group {
                    if !(200...299 ~= response.statusCode) {
                        throw HarmonicAdTrackerError.runtimeError("Failed to send beacon to \(urlString); Status \(response.statusCode)")
                    }
                    Self.logger.trace("Sent beacon to : \(urlString, privacy: .public)")
                }
                
            })
            
            trackingEvent.reportingState = .done
        } catch HarmonicAdTrackerError.runtimeError(let errorMessage) {
            Self.logger.error("Failed to send beacon; the error message is: \(errorMessage, privacy: .public)")
            trackingEvent.reportingState = .failed
        } catch {
            Self.logger.error("Failed to send beacon; unexpected error: \(error, privacy: .public)")
            trackingEvent.reportingState = .failed
        }
    }
    
    private func iterateTrackingEvents(time0: Double?, time1: Double?) async {
        let time0 = time0 ?? lastPlayheadTime
        let time1 = time1 ?? lastPlayheadTime
        
        for pod in adPods {
            guard let podStartTime = pod.startTime, let duration = pod.duration else {
                return
            }
            
            if podStartTime <= time1
                && time0 <= podStartTime + duration + AD_END_TRACKING_EVENT_TIME_TOLERANCE {
                
                for ad in pod.ads {
                    guard let adStartTime = ad.startTime, let adDuration = ad.duration else {
                        return
                    }
                    if adStartTime <= time1
                        && time0 <= adStartTime + adDuration + AD_END_TRACKING_EVENT_TIME_TOLERANCE {
                        await withTaskGroup(of: Void.self, body: { group in
                            for trackingEvent in ad.trackingEvents {
                                guard let startTime = trackingEvent.startTime,
                                      let duration = trackingEvent.duration,
                                      let reportingState = trackingEvent.reportingState else {
                                    return
                                }
                                
                                let endTime = startTime + max(duration, MAX_TOLERANCE_EVENT_END_TIME)
                                
                                if reportingState == .idle && startTime...endTime ~= time1 {
                                    group.addTask {
                                        await self.sendBeacon(trackingEvent)
                                    }
                                }
                            }
                        })
                    }
                }
                
            }
            
        }
    }
    
    private func mergePods(_ newPods: [AdBreak]) {
        adPods.removeAll { pod in
            (pod.startTime ?? 0) + (pod.duration ?? 0) + KEEP_PODS_FOR_MS < lastPlayheadTime &&
            !newPods.contains(where: { $0.id == pod.id })
        }
        
        for pod in newPods {
            let existingIndex = adPods.firstIndex(where: { $0.id == pod.id })
            var currentIndex = adPods.count
            if let existingIndex = existingIndex {
                currentIndex = existingIndex
                adPods[existingIndex].duration = pod.duration
            } else {
                let newPod = AdBreak(id: pod.id,
                                     startTime: pod.startTime,
                                     duration: pod.duration,
                                     ads: [])
                adPods.append(newPod)
            }
            mergeAds(existingAds: &adPods[currentIndex].ads, newAds: pod.ads)
        }
        
        adPods = adPods.sorted(by: { ($0.startTime ?? 0) < ($1.startTime ?? 0) })
    }
    
    private func mergeAds(existingAds: inout [Ad], newAds: [Ad]) {
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
