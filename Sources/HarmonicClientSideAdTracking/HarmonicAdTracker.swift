//
//  HarmonicAdTracker.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

let AD_END_TRACKING_EVENT_TIME_TOLERANCE: Double = 500
let MAX_TOLERANCE_IN_SPEED: Double = 2
let MAX_TOLERANCE_EVENT_END_TIME: Double = 1_000

enum HarmonicAdTrackerError: Error {
    case runtimeError(String)
}

public class HarmonicAdTracker: ClientSideAdTracker, ObservableObject {
    @Published
    public var adPods: [AdBreak] = []
    
    private var lastPlayheadTime: Double = 0
    private var lastPlayheadUpdateTime: Double = 0
        
    public init(adPods: [AdBreak] = [], lastPlayheadTime: Double = 0, lastPlayheadUpdateTime: Double = 0) {
        self.adPods = adPods
        self.lastPlayheadTime = lastPlayheadTime
        self.lastPlayheadUpdateTime = lastPlayheadUpdateTime
    }
    
    public func updatePods(_ pods: [AdBreak]?) {
        if let pods = pods {
            HarmonicAdTracker.mergePods(existingPods: &adPods, pods: pods)
        }
    }
    
    public func getAdPods() -> [AdBreak] {
        return adPods
    }
    
    public func getPlayheadTime() -> Double {
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
        DispatchQueue.main.async {
            trackingEvent.reportingState = .connecting
        }
        
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
                }
                
            })
            
            DispatchQueue.main.async {
                trackingEvent.reportingState = .done
            }
        } catch HarmonicAdTrackerError.runtimeError(let errorMessage) {
            print("Failed to send beacon; the error message is: \(errorMessage)")
            DispatchQueue.main.async {
                trackingEvent.reportingState = .failed
            }
        } catch {
            print("Failed to send beacon; unexpected error: \(error)")
            DispatchQueue.main.async {
                trackingEvent.reportingState = .failed
            }
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
    
}
