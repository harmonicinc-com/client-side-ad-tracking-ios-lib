//
//  HarmonicAdTracker+Beacon.swift
//  
//
//  Created by Michael on 1/3/2023.
//

import Foundation

private let BEACON_UPDATE_INTERVAL: TimeInterval = 0.5
private let INTERSTITIAL_BEACON_SEND_TOLERANCE: Double = 1_500
private let MAX_TOLERANCE_IN_SPEED: Double = 2.5

extension HarmonicAdTracker {
    func setCheckNeedSendBeaconTimer() {
        checkNeedSendBeaconTimer = Timer.publish(every: BEACON_UPDATE_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                guard let playerObserver = self.playerObserver else { return }
                guard let playhead = playerObserver.playhead else { return }
                let shouldCheckBeacon = self.shouldCheckBeaconForInterstitials(playhead: playhead)
                Task {
                    if shouldCheckBeacon {
                        await self.needSendBeacon(time: playhead)
                    }
                    await self.setPlayheadTime(playhead, shouldCheckBeacon: shouldCheckBeacon)
                }
            })
    }
    
    func shouldCheckBeaconForInterstitials(playhead: Double) -> Bool {
        guard let playerObserver = playerObserver else { return false }
        
        var shouldCheckBeacon = true
//        var isTrueReason = 0
//        var isFalseReason = 0
        
        if playerObserver.hasInterstitialEvents,
           let interstitialStatus = playerObserver.interstitialStatus,
           interstitialStatus != .playing {
            // There are interstitial events but the interstitialPlayer is not playing
            shouldCheckBeacon = false
            
            if playheadIsIncludedInStoredAdPods() {
                if let interstitialDate = playerObserver.interstitialDate,
                   let interstitialStop = playerObserver.interstitialStoppedDate,
                   let duration = playerObserver.currentInterstitialDuration {
                    // The interstitialPlayer status may change to .paused (and the interstitalStoppedDate set) before the "complete" signal is sent.
                    // So we should still check beacon if the stop date is not too far from the calculated one (interstitialDate + duration)
                    // and it has just stopped playing the interstitial.
                    if abs(interstitialStop - (interstitialDate + duration)) <= INTERSTITIAL_BEACON_SEND_TOLERANCE &&
                        abs(interstitialStop - playhead) <= INTERSTITIAL_BEACON_SEND_TOLERANCE {
                        shouldCheckBeacon = true
//                        isTrueReason = 1
                    } else {
                        shouldCheckBeacon = false
//                        isFalseReason = 1
                        Self.logger.trace("shouldCheckBeacon is false; interstitial date: \(HarmonicAdTracker.getFormattedString(from: interstitialDate)); stopped: \(HarmonicAdTracker.getFormattedString(from: interstitialStop)); duration: \(duration / 1_000)")
                    }
                }
            }
            
        }
        
//        Self.logger.trace("Should check beacon with playhead: \(HarmonicAdTracker.getFormattedString(from: playhead)) is \(shouldCheckBeacon) with reason (\(shouldCheckBeacon ? isTrueReason : isFalseReason)); hasEvents: \(playerObserver.hasInterstitialEvents); status: \(playerObserver.interstitialStatus?.rawValue ?? -1); playheadIsInStoredAdPods: \(adTracker.playheadIsIncludedInStoredAdPods())")
        
        return shouldCheckBeacon
    }
    
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
