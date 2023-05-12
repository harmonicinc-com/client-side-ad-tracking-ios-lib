//
//  HarmonicAdTracker.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import AVFoundation
import Combine
import os

private let METADATA_UPDATE_INTERVAL: TimeInterval = 4

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
        setRefreshMetadataTimer()
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
        
        var metadataUrl = session.sessionInfo.adTrackingMetadataUrl
        Self.logger.trace("Try calling AdMetadataHelper.requestAdMetadata (latest playhead is \(Utility.getFormattedString(from: playhead), privacy: .public))")
        do {
            let adBeacon = try await AdMetadataHelper.requestAdMetadata(with: metadataUrl, playhead: playhead)
            await updateLatestInfo(using: adBeacon)
        } catch {
            metadataUrl += "&start=\(Int(playhead))"
            Self.logger.trace("Last call failed with error: \(error); try calling AdMetadataHelper.requestAdMetadata with start param: \(Utility.getFormattedString(from: playhead), privacy: .public) (the new url is: \(metadataUrl, privacy: .public))")
            let adBeacon = try await AdMetadataHelper.requestAdMetadata(with: metadataUrl, playhead: nil)
            await updateLatestInfo(using: adBeacon)
        }
    }
    
    private func updateLatestInfo(using adBeacon: AdBeacon) async {
        session.latestDataRange = adBeacon.dataRange
        updatePods(adBeacon.adBreaks)
        await beaconSender.checkNeedSendBeaconsForPlayedRange()
    }

    private func updatePods(_ newPods: [AdBreak]?) {
        if let newPods = newPods,
           let playhead = session.playerObserver.playhead {
            session.adPods = AdMetadataHelper.mergePods(session.adPods, with: newPods, playhead: playhead)
        }
    }
    
    private func resetAdPods() {
        session.adPods.removeAll()
    }
    
    private func setRefreshMetadataTimer() {
        refreshMetadataTimer = Timer.publish(every: METADATA_UPDATE_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                Task {
                    do {
                        try await self.tryRefreshMetadata()
                    } catch {
                        Self.logger.warning("tryRefreshMetadata failed: \(error)")
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
                    Self.logger.trace("Detected time jump (current playhead: \(Utility.getFormattedString(from: currentPlayhead)) (last playhead: \(Utility.getFormattedString(from: lastPlayhead))), resetting ad pods (\(adPodIDs))")
                    Task {
                        self.resetAdPods()
                        do {
                            try await self.tryRefreshMetadata()
                        } catch {
                            Self.logger.warning("tryRefreshMetadata failed: \(error)")
                        }
                    }
                }
            })
    }
}
