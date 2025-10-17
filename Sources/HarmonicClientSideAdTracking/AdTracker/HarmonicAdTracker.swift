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
