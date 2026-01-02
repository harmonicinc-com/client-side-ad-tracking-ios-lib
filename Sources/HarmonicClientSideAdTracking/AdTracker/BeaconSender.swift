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
private let MAX_TOLERANCE_EVENT_START_TIME: Double = 500
private let MAX_TOLERANCE_EVENT_END_TIME: Double = 1_000

@MainActor
class BeaconSender {
    private static let logger = Logger(
        subsystem: Bundle.module.bundleIdentifier!,
        category: String(describing: BeaconSender.self)
    )
    
    private let session: AdBeaconingSession
    private let playedRangeTracker: PlayedRangeTracker
    private let httpClient: HTTPClientProtocol

    private var lastPlayheadChecked: Double = 0
    private var lastPlayheadCheckTime: Double = 0
    private var shouldCheckBeacon = true
    
    private var checkNeedSendBeaconTimer: AnyCancellable?
    
    init(session: AdBeaconingSession, httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.session = session
        self.playedRangeTracker = PlayedRangeTracker(session: session)
        self.httpClient = httpClient
    }
    
    func start() {
        setCheckNeedSendBeaconTimer()
        playedRangeTracker.start()
    }
    
    func stop() {
        checkNeedSendBeaconTimer?.cancel()
        playedRangeTracker.stop()
    }
    
    func checkNeedSendBeaconsForPlayedRange() async {
        guard let playhead = session.playerObserver.playhead else { return }
        
        Utility.log("Checking played ranges for late beacons: \(playedRangeTracker.getRanges())",
                    to: session, level: .debug, with: Self.logger)
        
        await withTaskGroup(of: Void.self, body: { group in
            for pod in session.adPods {
                for ad in pod.ads {
                    for trackingEvent in ad.trackingEvents {
                        guard let reportingState = trackingEvent.reportingState else {
                            return
                        }

                        // Skip player-initiated events - these should only be sent manually
                        if trackingEvent.event?.isPlayerInitiated == true {
                            continue
                        }
                        
                        if reportingState == .idle {
                            // Check if the tracking event time was played
                            if let eventTime = trackingEvent.startTime,
                               playedRangeTracker.wasTimePlayed(eventTime) {
                                group.addTask {
                                    await self.sendBeacon(trackingEvent)
                                }
                                Utility.log("Sending beacon for missed event: \(trackingEvent.signalingUrls)",
                                            to: session, level: .debug, with: Self.logger)
                            }
                        }
                    }
                }
            }
        })
        
        // Clean up old ranges
        playedRangeTracker.cleanupOldRanges(currentPosition: playhead, retentionMs: session.keepPodsForMs)
    }
    
    private func setCheckNeedSendBeaconTimer() {
        checkNeedSendBeaconTimer = Timer.publish(every: BEACON_UPDATE_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                guard let playhead = self.session.playerObserver.playhead else { return }
                
                self.shouldCheckBeacon = self.shouldCheckBeaconForInterstitials(playhead: playhead)
                
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
    
    func iterateTrackingEvents(time0: Double, time1: Double) async {
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

                                // Skip player-initiated events - these should only be sent manually
                                if trackingEvent.event?.isPlayerInitiated == true {
                                    continue
                                }
                                
                                // if time1 is within event start plus 1s (or duration for impression event)
                                let endTime = startTime + max(duration, MAX_TOLERANCE_EVENT_END_TIME)
                                
                                if reportingState == .idle && (startTime - MAX_TOLERANCE_EVENT_START_TIME)...endTime ~= time1 {
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
                        let (_, response) = try await self.httpClient.data(from: url)
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
        } catch let beaconError as HarmonicAdTrackerError {
            let errorMessage = switch beaconError {
            case .beaconError(let msg): msg
            default: "Unexpected error type"
            }
            Utility.log("Failed to send beacon; the error message is: \(errorMessage)", to: session, level: .error, with: Self.logger, error: beaconError)
            trackingEvent.reportingState = .failed
        } catch {
            let trackerError = HarmonicAdTrackerError.beaconError("Unexpected error: \(error)")
            Utility.log("Failed to send beacon; unexpected error: \(error)", to: session, level: .error, with: Self.logger, error: trackerError)
            trackingEvent.reportingState = .failed
        }
    }
    
    /// Sends a user-triggered beacon for the currently playing ad.
    /// - Parameter eventType: The type of user-triggered event to send
    /// - Returns: True if the beacon was sent or queued, false if no ad is currently playing or no matching tracking event exists
    func sendUserTriggeredBeacon(eventType: EventType) async -> Bool {
        guard let playhead = session.playerObserver.playhead else {
            Utility.log("Cannot send \(eventType) beacon: playhead is nil",
                        to: session, level: .warning, with: Self.logger)
            return false
        }
        
        // Find the currently playing ad
        for pod in session.adPods {
            guard let podStartTime = pod.startTime, let podDuration = pod.duration else { continue }
            
            // Check if playhead is within this pod
            if playhead >= podStartTime && playhead <= podStartTime + podDuration {
                for ad in pod.ads {
                    guard let adStartTime = ad.startTime, let adDuration = ad.duration else { continue }
                    
                    // Check if playhead is within this ad
                    if playhead >= adStartTime && playhead <= adStartTime + adDuration {
                        // Find tracking event matching the event type
                        for trackingEvent in ad.trackingEvents {
                            if trackingEvent.event == eventType {
                                let adId = ad.id ?? UUID().uuidString
                                
                                // Always send if the player operation is triggered
                                await sendBeacon(trackingEvent)
                                
                                Utility.log("Sent \(eventType) beacon for ad \(adId)",
                                            to: session, level: .info, with: Self.logger)
                                return true
                            }
                        }
                        
                        // No matching tracking event found for this ad
                        Utility.log("No \(eventType) tracking event found for current ad",
                                    to: session, level: .debug, with: Self.logger)
                        return false
                    }
                }
            }
        }
        
        Utility.log("Cannot send \(eventType) beacon: no ad is currently playing",
                    to: session, level: .debug, with: Self.logger)
        return false
    }
    
}
