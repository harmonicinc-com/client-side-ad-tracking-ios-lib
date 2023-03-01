//
//  HarmonicAdTracker+Beacon.swift
//  
//
//  Created by Michael on 1/3/2023.
//

import Foundation

private let MAX_TOLERANCE_IN_SPEED: Double = 2.5

extension HarmonicAdTracker {
    func needSendBeacon(time: Double) async {
        let now = Date().timeIntervalSince1970 * 1_000
        if now == lastPlayheadUpdateTime {
            return
        }
        
        let speed = (time - lastPlayheadTime) / (now - lastPlayheadUpdateTime)
        if 0.nextUp...MAX_TOLERANCE_IN_SPEED ~= speed {
            await iterateTrackingEvents(time0: lastPlayheadTime, time1: time)
        }
        lastPlayheadUpdateTime = now
    }
    
    func sendBeacon(_ trackingEvent: TrackingEvent) async {
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
    
    func iterateTrackingEvents(time0: Double?, time1: Double?) async {
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
                                
                                // if time1 is within event start plus 1s (or duration for impression event)
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
