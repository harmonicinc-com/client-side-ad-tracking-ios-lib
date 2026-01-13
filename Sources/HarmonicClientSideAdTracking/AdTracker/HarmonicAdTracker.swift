//
//  HarmonicAdTracker.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import AVFoundation
import Combine
import os

private let RESET_AD_PODS_IF_TIMEJUMP_EXCEEDS: TimeInterval = 60
private let AD_START_TOLERANCE_FOR_TIMEJUMP_RESET: Double = 4_000
private let AD_END_TOLERANCE_FOR_TIMEJUMP_RESET: Double = 500

@MainActor
public class HarmonicAdTracker {
    private static let logger = Logger(
        subsystem: Bundle.module.bundleIdentifier!,
        category: String(describing: HarmonicAdTracker.self)
    )
    
    private let session: AdBeaconingSession
    private let beaconSender: BeaconSender
    
    private var refreshMetadataTimer: AnyCancellable?
    private var timeJumpObservation: AnyCancellable?
    
    public init(session: AdBeaconingSession) {
        self.session = session
        self.beaconSender = BeaconSender(session: session)
    }
    
    public func start() {
        setRefreshMetadataTimer(updateInterval: session.metadataUpdateInterval)
        setTimeJumpObservation()
        beaconSender.start()
    }
    
    public func stop() {
        resetAdPods()
        refreshMetadataTimer?.cancel()
        timeJumpObservation?.cancel()
        beaconSender.stop()
    }
    
    // MARK: - User-Triggered Beacon Methods
    
    /// Reports that the player was muted. Call this method when the user mutes the player.
    /// The SDK will send mute beacons if an ad is currently playing and has mute tracking events.
    /// - Returns: True if the beacon was sent, false if no ad is currently playing or no mute tracking event exists
    @discardableResult
    public func reportMute() async -> Bool {
        Utility.log("User reported mute event", to: session, level: .debug, with: Self.logger)
        return await beaconSender.sendUserTriggeredBeacon(eventType: .mute)
    }
    
    /// Reports that the player was unmuted. Call this method when the user unmutes the player.
    /// The SDK will send unmute beacons if an ad is currently playing and has unmute tracking events.
    /// - Returns: True if the beacon was sent, false if no ad is currently playing or no unmute tracking event exists
    @discardableResult
    public func reportUnmute() async -> Bool {
        Utility.log("User reported unmute event", to: session, level: .debug, with: Self.logger)
        return await beaconSender.sendUserTriggeredBeacon(eventType: .unmute)
    }
    
    /// Reports that the player was paused. Call this method when the user pauses the player.
    /// The SDK will send pause beacons if an ad is currently playing and has pause tracking events.
    /// - Returns: True if the beacon was sent, false if no ad is currently playing or no pause tracking event exists
    @discardableResult
    public func reportPause() async -> Bool {
        Utility.log("User reported pause event", to: session, level: .debug, with: Self.logger)
        return await beaconSender.sendUserTriggeredBeacon(eventType: .pause)
    }
    
    /// Reports that the player was resumed. Call this method when the user resumes the player.
    /// The SDK will send resume beacons if an ad is currently playing and has resume tracking events.
    /// - Returns: True if the beacon was sent, false if no ad is currently playing or no resume tracking event exists
    @discardableResult
    public func reportResume() async -> Bool {
        Utility.log("User reported resume event", to: session, level: .debug, with: Self.logger)
        return await beaconSender.sendUserTriggeredBeacon(eventType: .resume)
    }
    
    /// Reports that the user rewound the player. Call this method when the user rewinds during ad playback.
    /// The SDK will send rewind beacons if an ad is currently playing and has rewind tracking events.
    /// - Returns: True if the beacon was sent, false if no ad is currently playing or no rewind tracking event exists
    @discardableResult
    public func reportRewind() async -> Bool {
        Utility.log("User reported rewind event", to: session, level: .debug, with: Self.logger)
        return await beaconSender.sendUserTriggeredBeacon(eventType: .rewind)
    }
    
    /// Reports that the user skipped the ad. Call this method when the user skips during ad playback.
    /// The SDK will send skip beacons if an ad is currently playing and has skip tracking events.
    /// - Returns: True if the beacon was sent, false if no ad is currently playing or no skip tracking event exists
    @discardableResult
    public func reportSkip() async -> Bool {
        Utility.log("User reported skip event", to: session, level: .debug, with: Self.logger)
        return await beaconSender.sendUserTriggeredBeacon(eventType: .skip)
    }
    
    /// Reports that the player was expanded to a larger size. Call this method when the user expands the player.
    /// The SDK will send playerExpand beacons if an ad is currently playing and has playerExpand tracking events.
    /// - Returns: True if the beacon was sent, false if no ad is currently playing or no playerExpand tracking event exists
    @discardableResult
    public func reportPlayerExpand() async -> Bool {
        Utility.log("User reported playerExpand event", to: session, level: .debug, with: Self.logger)
        return await beaconSender.sendUserTriggeredBeacon(eventType: .playerExpand)
    }
    
    /// Reports that the player was collapsed to a smaller size. Call this method when the user collapses the player.
    /// The SDK will send playerCollapse beacons if an ad is currently playing and has playerCollapse tracking events.
    /// - Returns: True if the beacon was sent, false if no ad is currently playing or no playerCollapse tracking event exists
    @discardableResult
    public func reportPlayerCollapse() async -> Bool {
        Utility.log("User reported playerCollapse event", to: session, level: .debug, with: Self.logger)
        return await beaconSender.sendUserTriggeredBeacon(eventType: .playerCollapse)
    }

    private func tryRefreshMetadata() async throws {
        guard let playhead = session.playerObserver.playhead else {
            throw HarmonicAdTrackerError.metadataError("Playhead is nil.")
        }
        
        let metadataUrl = session.sessionInfo.adTrackingMetadataUrl
        Utility.log("Try calling AdMetadataHelper.requestAdMetadata (latest playhead is \(Utility.getFormattedString(from: playhead)))",
                    to: session, level: .debug, with: Self.logger)

        let adBeacon = try await AdMetadataHelper.requestAdMetadata(with: metadataUrl)
        await updateLatestInfo(using: adBeacon)
    }
    
    private func updateLatestInfo(using adBeacon: AdBeacon) async {
        guard let latestDataRange = adBeacon.dataRange else {
            Utility.log("AdBeacon has empty DataRange.",
                        to: session, level: .warning, with: Self.logger)
            return
        }
        
        let adPodIDs = adBeacon.adBreaks.map { $0.id ?? "nil" }
        Utility.log("Got \(adBeacon.adBreaks.count) ad pods: \(adPodIDs) with \(latestDataRange)",
                    to: session, level: .debug, with: Self.logger)
        
        session.latestDataRange = adBeacon.dataRange
        updatePods(adBeacon.adBreaks)
        await beaconSender.checkNeedSendBeaconsForPlayedRange()
    }

    private func updatePods(_ newPods: [AdBreak]?) {
        if let newPods = newPods,
           let playhead = session.playerObserver.playhead {
            session.adPods = AdMetadataHelper.mergePods(session.adPods, with: newPods, playhead: playhead, keepPodsForMs: session.keepPodsForMs)
        }
    }
    
    private func resetAdPods() {
        session.adPods.removeAll()
    }
    
    private func setRefreshMetadataTimer(updateInterval: TimeInterval) {
        refreshMetadataTimer = Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                Task {
                    do {
                        try await self.tryRefreshMetadata()
                    } catch let trackerError as HarmonicAdTrackerError {
                        Utility.log("tryRefreshMetadata failed: \(trackerError)",
                                    to: self.session, level: .warning, with: Self.logger, error: trackerError)
                    } catch {
                        let trackerError = HarmonicAdTrackerError.metadataError("Failed to refresh metadata: \(error.localizedDescription)")
                        Utility.log("tryRefreshMetadata failed: \(error)",
                                    to: self.session, level: .warning, with: Self.logger, error: trackerError)
                    }
                }
            })
    }
    
    private func setTimeJumpObservation() {
        timeJumpObservation = NotificationCenter.default
            .publisher(for: AVPlayerItem.timeJumpedNotification)
            .sink(receiveValue: { [weak self] notification in
                guard let self = self else { return }
                guard !self.session.adPods.isEmpty else { return }
                guard let item = notification.object as? AVPlayerItem else { return }
                guard let currentPlayhead = item.currentDate() else { return }

                let lastPlayhead = Date(timeIntervalSince1970: (self.session.latestPlayhead / 1_000))
                if !Utility.playheadIsIncludedIn(self.session.adPods,
                                                 for: self.session.latestPlayhead,
                                                 startTolerance: AD_START_TOLERANCE_FOR_TIMEJUMP_RESET,
                                                 endTolerance: AD_END_TOLERANCE_FOR_TIMEJUMP_RESET),
                   abs(lastPlayhead.timeIntervalSince(currentPlayhead)) > RESET_AD_PODS_IF_TIMEJUMP_EXCEEDS {
                    let adPodIDs = self.session.adPods.map { $0.id ?? "nil" }
                    Utility.log("Detected time jump (current playhead: \(Utility.getFormattedString(from: currentPlayhead)) (last playhead: \(Utility.getFormattedString(from: lastPlayhead))); Current ad pods (\(adPodIDs))",
                                to: self.session, level: .debug, with: Self.logger)
                    // Not resetting ad pods to preserve beacons' fired states
                }
            })
    }
}
