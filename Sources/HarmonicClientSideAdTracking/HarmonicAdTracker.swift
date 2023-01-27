//
//  HarmonicAdTracker.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

let AD_END_TRACKING_EVENT_TIME_TOLERANCE: Double = 500
let MAX_TOLERANCE_IN_SPEED: Double = 2
let MAX_TOLERANCE_EVENT_END_TIME: Double = 1000

enum AdTrackerError: Error {
    case runtimeError(String)
}

public class HarmonicAdTracker: ClientSideAdTracker {
    
    private var adPods: [AdBreak] = []
    private var delegate: HarmonicAdTrackerDelegate?
    private var lastPlayheadTime: Double = 0
    private var lastPlayheadUpdateTime: Double = 0
    
    public init(adPods: [AdBreak],
                delegate: HarmonicAdTrackerDelegate? = nil) {
        self.adPods = adPods
        self.delegate = delegate
    }
    
    public func updatePods(_ pods: [AdBreak]) {
        let updated = HarmonicAdTracker.mergePods(existingPods: &adPods, pods: pods)
        if updated {
            delegate?.receiveUpdate()
        }
    }
    
    public func getAdPods() -> [AdBreak] {
        return adPods
    }
    
    public func updatePlayheadTime(_ time: Double) async {
        // TODO: Update lastPlayheadTime here and no need to make needSendBeacon public???
        await needSendBeacon(time: time)
    }
    
    public func getPlayheadTime() -> Double {
        return lastPlayheadTime
    }
    
    public func needSendBeacon(time: Double) async {
        let now = Date().timeIntervalSince1970 * 1000
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
    
    private func iterateTrackingEvents(for ad: Ad, time0: Double, time1: Double) async -> Ad {
        var ad = ad
        
        if let adStartTime = ad.startTime, let adDuration = ad.duration,
           adStartTime <= time1 && time0 <= adStartTime + adDuration + AD_END_TRACKING_EVENT_TIME_TOLERANCE {
            
            let events = await withTaskGroup(of: TrackingEvent.self, body: { group -> [TrackingEvent] in
                for trackingEvent in ad.trackingEvents {
                    if let startTime = trackingEvent.startTime, let duration = trackingEvent.duration {
                        let endTime = startTime + max(duration, MAX_TOLERANCE_EVENT_END_TIME)
                        
                        if let reportingState = trackingEvent.reportingState,
                           reportingState == .idle &&
                            startTime <= time1 && time1 <= endTime {
                            group.addTask {
                                return await self.sendBeacon(trackingEvent)
                            }
                        } else {
                            group.addTask {
                                return trackingEvent
                            }
                        }
                    }
                }
                
                return await group.reduce(into: [TrackingEvent]()) { partialResult, trackingEvent in
                    partialResult.append(trackingEvent)
                }
            })
            
            ad.trackingEvents = events
            
        }
        
        return ad
    }
    
    private func iterateTrackingEvents(time0: Double?,
                                       time1: Double?) async {
        let time0 = time0 ?? lastPlayheadTime
        let time1 = time1 ?? lastPlayheadTime
        
        adPods = await withTaskGroup(of: AdBreak.self, body: { group -> [AdBreak] in
            for pod in adPods {
                
                group.addTask {
                    var pod = pod
                    
                    if let podStartTime = pod.startTime, let duration = pod.duration,
                       podStartTime <= time1 && time0 <= podStartTime + duration + AD_END_TRACKING_EVENT_TIME_TOLERANCE {
                        
                        let newAds = await withTaskGroup(of: Ad.self, body: { group -> [Ad] in
                            for ad in pod.ads {
                                group.addTask {
                                    return await self.iterateTrackingEvents(for: ad, time0: time0, time1: time1)
                                }
                            }
                            
                            return await group.reduce(into: [Ad](), { partialResult, ad in
                                partialResult.append(ad)
                            })
                        })
//                        print("newAds: \(newAds)")
                        pod.ads = newAds
                        
                    }
                    
                    return pod
                }
                
                
            }
            
            return await group.reduce(into: [AdBreak](), { partialResult, pod in
                partialResult.append(pod)
            })
        })
                                           
//        for pod in adPods {
////            print("iterateTrackingEvents: pod: \(pod)")
//            if let podStartTime = pod.startTime, let duration = pod.duration,
//               podStartTime <= time1 && time0 <= podStartTime + duration + AD_END_TRACKING_EVENT_TIME_TOLERANCE {
//
//                for var ad in pod.ads {
////                    print("iterateTrackingEvents: ad: \(ad)")
//                    if let adStartTime = ad.startTime, let adDuration = ad.duration,
//                       adStartTime <= time1 && time0 <= adStartTime + adDuration + AD_END_TRACKING_EVENT_TIME_TOLERANCE {
////                        var newEvents = [TrackingEvent]()
//
//                        for var trackingEvent in ad.trackingEvents {
//                            print("iterateTrackingEvents: trackingEvent: \(trackingEvent)")
////                            let newTrackingEvent = await handler(trackingEvent)
////                            newEvents.append(newTrackingEvent)
//
////                            { trackingEvent in
////                                var trackingEvent = trackingEvent
//                                if let startTime = trackingEvent.startTime, let duration = trackingEvent.duration {
//                                    let endTime = startTime + max(duration, MAX_TOLERANCE_EVENT_END_TIME)
//        //                            print("needSendBeacon: startTime: \(startTime)")
//        //                            print("needSendBeacon: duration: \(duration)")
//        //                            print("needSendBeacon: time: \(time)")
//        //                            print("needSendBeacon: endTime: \(endTime)")
//                                    if let reportingState = trackingEvent.reportingState,
//                                       reportingState == .idle &&
//                                        startTime <= time1 && time1 <= endTime {
//                                        await self.sendBeacon(trackingEvent)
//                                    }
//                                }
//                            print(trackingEvent)
////                                return trackingEvent
////                            },
//
//                        }
////                        ad.trackingEvents = newEvents
//                        print(ad)
//                    }
//                }
//            }
//        }
    }
    
    private func sendBeacon(_ trackingEvent: TrackingEvent) async -> TrackingEvent {
        var trackingEvent = trackingEvent
        
        trackingEvent.reportingState = .connecting
        // TODO: when connecting how to notify player??
        
        delegate?.receiveUpdate()
        
        do {
            try await withThrowingTaskGroup(of: (String, HTTPURLResponse).self,
                                            returning: Void.self,
                                            body: { group in
//                if let signalingUrls = trackingEvent.signalingUrls {
                    for urlString in trackingEvent.signalingUrls {
                        print("sendBeacon signalingUrls: \(urlString)")
                        group.addTask {
                            guard let url = URL(string: urlString) else {
                                throw AdTrackerError.runtimeError("Invalid signaling url: \(urlString)")
                            }
                            let (_, response) = try await URLSession.shared.data(from: url)
                            guard let httpResponse = response as? HTTPURLResponse else {
                                throw AdTrackerError.runtimeError("Invalid URLResponse for url: \(urlString)")
                            }
                            return (urlString, httpResponse)
                        }
                    }
//                }
                
                for try await (urlString, response) in group {
                    print("sent beacon to :\(urlString)")
                    if response.statusCode < 200 || response.statusCode > 299 {
                        throw AdTrackerError.runtimeError("Failed to send beacon to \(urlString); Status \(response.statusCode)")
                    }
                }
            })
            
            trackingEvent.reportingState = .done
            return trackingEvent
        } catch AdTrackerError.runtimeError(let errorMessage) {
            print("Failed to send beacon; the error message is: \(errorMessage)")
            trackingEvent.reportingState = .failed
            return trackingEvent
        } catch {
            print("Failed to send beacon; unexpected error: \(error)")
            trackingEvent.reportingState = .failed
            return trackingEvent
        }

        delegate?.receiveUpdate()
    }
    
}
