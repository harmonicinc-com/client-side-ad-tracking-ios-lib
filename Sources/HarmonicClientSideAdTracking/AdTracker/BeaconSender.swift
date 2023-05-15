//
//  BeaconSender.swift
//  
//
//  Created by Michael on 10/5/2023.
//

import Foundation
import Combine
import os

private let BEACON_UPDATE_INTERVAL: TimeInterval = 0.5
private let INTERSTITIAL_BEACON_SEND_TOLERANCE: Double = 1_500
private let MAX_TOLERANCE_IN_SPEED: Double = 2.5
private let AD_END_TRACKING_EVENT_TIME_TOLERANCE: Double = 500
private let MAX_TOLERANCE_EVENT_END_TIME: Double = 1_000

@MainActor
class BeaconSender {
    private static let logger = Logger(
        subsystem: Bundle.module.bundleIdentifier!,
        category: String(describing: BeaconSender.self)
    )
    
    private let session: AdBeaconingSession
    private let playedRangeChecker: PlayedRangeChecker

    private var lastPlayheadChecked: Double = 0
    private var lastPlayheadCheckTime: Double = 0
    private var shouldCheckBeacon = true
    
    private var checkNeedSendBeaconTimer: AnyCancellable?
    
    init(session: AdBeaconingSession) {
        self.session = session
        self.playedRangeChecker = PlayedRangeChecker(session: session)
    }
    
    func start() {
        setCheckNeedSendBeaconTimer()
        playedRangeChecker.start()
    }
    
    func stop() {
        checkNeedSendBeaconTimer?.cancel()
        playedRangeChecker.stop()
    }
    
    func checkNeedSendBeaconsForPlayedRange() async {
        let timeRangesToCheck = getIntersectionsWithLastDataRange()
        Utility.log("timeRangesToCheck for played ranges: \(timeRangesToCheck)",
                    to: session, level: .debug, with: Self.logger)
        
        await withTaskGroup(of: Void.self, body: { group in
            for pod in session.adPods {
                for ad in pod.ads {
                    for trackingEvent in ad.trackingEvents {
                        guard let reportingState = trackingEvent.reportingState else {
                            return
                        }
                        
                        if reportingState == .idle
                            && Utility.trackingEventIsIn(timeRangesToCheck, for: trackingEvent, with: MAX_TOLERANCE_EVENT_END_TIME) {
                            group.addTask {
                                await self.sendBeacon(trackingEvent)
                            }
                            Utility.log("Sending beacon for missed event: \(trackingEvent.signalingUrls)",
                                        to: session, level: .debug, with: Self.logger)
                        }
                    }
                }
            }
        })
    }
    
    private func setCheckNeedSendBeaconTimer() {
        checkNeedSendBeaconTimer = Timer.publish(every: BEACON_UPDATE_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                guard let playhead = session.playerObserver.playhead else { return }
                
                self.shouldCheckBeacon = self.shouldCheckBeaconForInterstitials(playhead: playhead)
                self.playedRangeChecker.setShouldCheckBeacon(self.shouldCheckBeacon)
                
                Task {
                    if self.shouldCheckBeacon {
                        await self.needSendBeacon(for: playhead)
                    }
                    await self.setLastPlayheadChecked(playhead)
                }
            })
    }
    
    private func setLastPlayheadChecked(_ playhead: Double) async {
        lastPlayheadChecked = playhead
        session.latestPlayhead = playhead
    }
    
    private func shouldCheckBeaconForInterstitials(playhead: Double, debugReason: Bool = false) -> Bool {
        var shouldCheckBeacon = true
        
        var isTrueReason = 0
        var isFalseReason = 0
        
        if session.playerObserver.hasInterstitialEvents,
           let interstitialStatus = session.playerObserver.interstitialStatus,
           interstitialStatus != .playing {
            // There are interstitial events but the interstitialPlayer is not playing
            shouldCheckBeacon = false
            
            if Utility.playheadIsIncludedIn(session.adPods, for: playhead, startTolerance: 0, endTolerance: AD_END_TRACKING_EVENT_TIME_TOLERANCE) {
                if let interstitialDate = session.playerObserver.interstitialDate,
                   let interstitialStop = session.playerObserver.interstitialStoppedDate,
                   let duration = session.playerObserver.currentInterstitialDuration {
                    // The interstitialPlayer status may change to .paused (and the interstitalStoppedDate set) before the "complete" signal is sent.
                    // So we should still check beacon if the stop date is not too far from the calculated one (interstitialDate + duration)
                    // and it has just stopped playing the interstitial.
                    if abs(interstitialStop - (interstitialDate + duration)) <= INTERSTITIAL_BEACON_SEND_TOLERANCE &&
                        abs(interstitialStop - playhead) <= INTERSTITIAL_BEACON_SEND_TOLERANCE {
                        shouldCheckBeacon = true
                        isTrueReason = 1
                    } else {
                        shouldCheckBeacon = false
                        isFalseReason = 1
                        Utility.log("shouldCheckBeacon is false; interstitial date: \(Utility.getFormattedString(from: interstitialDate)); stopped: \(Utility.getFormattedString(from: interstitialStop)); duration: \(duration / 1_000)",
                                    to: session, level: .debug, with: Self.logger)
                    }
                }
            }
            
        }
        
        if debugReason {
            let debugMessage = "Should check beacon with playhead: \(Utility.getFormattedString(from: playhead)) "
            + "is \(shouldCheckBeacon) with reason (\(shouldCheckBeacon ? isTrueReason : isFalseReason)); "
            + "hasEvents: \(self.session.playerObserver.hasInterstitialEvents); "
            + "status: \(self.session.playerObserver.interstitialStatus?.rawValue ?? -1); "
            + "playheadIsInStoredAdPods: \(Utility.playheadIsIncludedIn(self.session.adPods, for: playhead, startTolerance: 0, endTolerance: AD_END_TRACKING_EVENT_TIME_TOLERANCE))"
            Utility.log(debugMessage, to: session, level: .debug, with: Self.logger)
        }
        
        return shouldCheckBeacon
    }
    
    private func needSendBeacon(for playheadToCheck: Double) async {
        let now = Date().timeIntervalSince1970 * 1_000
        if now == lastPlayheadCheckTime {
            return
        }
        
        let speed = (playheadToCheck - lastPlayheadChecked) / (now - lastPlayheadCheckTime)
        if 0.nextUp...MAX_TOLERANCE_IN_SPEED ~= speed {
            await iterateTrackingEvents(time0: lastPlayheadChecked, time1: playheadToCheck)
        }
        lastPlayheadCheckTime = now
    }
    
    private func iterateTrackingEvents(time0: Double, time1: Double) async {
        for pod in session.adPods {
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
    
    private func sendBeacon(_ trackingEvent: TrackingEvent) async {
        trackingEvent.reportingState = .connecting
        
        do {
            try await withThrowingTaskGroup(of: (String, HTTPURLResponse).self,
                                            returning: Void.self,
                                            body: { group in
                
                for urlString in trackingEvent.signalingUrls {
                    group.addTask {
                        guard let url = URL(string: urlString) else {
                            throw HarmonicAdTrackerError.beaconError("Invalid signaling url: \(urlString)")
                        }
                        let (_, response) = try await URLSession.shared.data(from: url)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw HarmonicAdTrackerError.beaconError("Invalid URLResponse for url: \(urlString)")
                        }
                        return (urlString, httpResponse)
                    }
                }
                
                for try await (urlString, response) in group {
                    if !(200...299 ~= response.statusCode) {
                        throw HarmonicAdTrackerError.beaconError("Failed to send beacon to \(urlString); Status \(response.statusCode)")
                    }
                    Utility.log("Sent beacon to : \(urlString)", to: session, level: .debug, with: Self.logger)
                }
                
            })
            
            trackingEvent.reportingState = .done
        } catch HarmonicAdTrackerError.beaconError(let errorMessage) {
            Utility.log("Failed to send beacon; the error message is: \(errorMessage)", to: session, level: .error, with: Self.logger)
            trackingEvent.reportingState = .failed
        } catch {
            Utility.log("Failed to send beacon; unexpected error: \(error)", to: session, level: .error, with: Self.logger)
            trackingEvent.reportingState = .failed
        }
    }
    
    private func getIntersectionsWithLastDataRange() -> [DataRange] {
        guard let lastDataRange = session.latestDataRange,
              let lastStart = lastDataRange.start,
              let lastEnd = lastDataRange.end else {
            return []
        }
        
        var intersections: [DataRange] = []
        
        for playedDataRange in session.playedTimeOutsideDataRange {
            guard let start = playedDataRange.start,
                  let end = playedDataRange.end else { continue }
            guard playedDataRange.overlaps(lastDataRange) else { continue }
            
            if playedDataRange.isWithin(lastDataRange) {
                intersections.append(playedDataRange)
                session.playedTimeOutsideDataRange.removeAll(where: { $0 == playedDataRange })
            } else {
                let intersection = DataRange(start: max(start, lastStart), end: min(end, lastEnd))
                intersections.append(intersection)
                playedDataRange.start = intersection.contains(start) ? intersection.end! : start
                playedDataRange.end = intersection.contains(end) ? intersection.start! : end
            }
        }
        
        return intersections
    }
    
}
