//
//  HarmonicAdTracker.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import AVFoundation
import Combine
import os

let AD_END_TRACKING_EVENT_TIME_TOLERANCE: Double = 500
let MAX_TOLERANCE_EVENT_END_TIME: Double = 1_000
let RESET_AD_PODS_IF_TIMEJUMP_EXCEEDS: TimeInterval = 60
let AD_START_TOLERANCE_FOR_TIMEJUMP_RESET: Double = 4_000

enum HarmonicAdTrackerError: Error {
    case runtimeError(String)
}

@MainActor
public class HarmonicAdTracker: ClientSideAdTracker, ObservableObject {
    static let logger = Logger(
        subsystem: Bundle.module.bundleIdentifier!,
        category: String(describing: HarmonicAdTracker.self)
    )
    static let dateFormatter = DateFormatter()
    
    @Published
    public internal(set) var adPods: [AdBreak] = []
    
    @Published
    public var session = Session()
    
    @Published
    public var lastDataRange: DataRange?
    
    @Published
    public var playedTimeOutsideDataRange: [DataRange] = []
    
    var lastPlayheadTime: Double = 0
    var lastPlayheadUpdateTime: Double = 0
    var shouldCheckBeacon = true
    
    let decoder = JSONDecoder()
    var timeJumpObservation: AnyCancellable?
    var refreshMetadatTimer: AnyCancellable?
    var checkPlayheadIsInDataRangeTimer: AnyCancellable?
    
    public init(adPods: [AdBreak] = [], lastPlayheadTime: Double = 0, lastPlayheadUpdateTime: Double = 0) {
        self.adPods = adPods
        self.lastPlayheadTime = lastPlayheadTime
        self.lastPlayheadUpdateTime = lastPlayheadUpdateTime
    }
    
    public func start() async {
        setRefreshMetadataTimer()
        setCheckPlayheadIsInDataRangeTimer()
        setTimeJumpObservation()
    }
    
    public func stop() async {
        await resetAdPods()
        refreshMetadatTimer?.cancel()
        checkPlayheadIsInDataRangeTimer?.cancel()
        timeJumpObservation?.cancel()
    }
    
    public func setMediaUrl(_ urlString: String) async {
        guard !urlString.isEmpty else { return }
        var manifestUrl, adTrackingMetadataUrl: String
        do {
            guard let (_, httpResponse) = try await HarmonicAdTracker.makeRequestTo(urlString) else {
                return
            }
            
            if let redirectedUrl = httpResponse.url {
                manifestUrl = redirectedUrl.absoluteString
                adTrackingMetadataUrl = HarmonicAdTracker.rewriteUrlToMetadataUrl(redirectedUrl.absoluteString)
            } else {
                manifestUrl = urlString
                adTrackingMetadataUrl = HarmonicAdTracker.rewriteUrlToMetadataUrl(urlString)
            }
            
            session.sessionInfo = SessionInfo(localSessionId: Date().ISO8601Format(),
                                              mediaUrl: urlString,
                                              manifestUrl: manifestUrl,
                                              adTrackingMetadataUrl: adTrackingMetadataUrl)
            
            _ = await refreshMetadata(urlString: adTrackingMetadataUrl, time: nil)
        } catch {
            let errorMessage = "Error loading media with URL: \(urlString); Error: \(error)"
            Self.logger.error("\(errorMessage, privacy: .public)")
        }
    }
    
    // MARK: Internal
    
    func setPlayheadTime(_ time: Double, shouldCheckBeacon: Bool) async {
        self.lastPlayheadTime = time
        self.shouldCheckBeacon = shouldCheckBeacon
    }
    
    func getPlayheadTime() async -> Double {
        return lastPlayheadTime
    }
    
    func updatePods(_ pods: [AdBreak]?) async {
        if let pods = pods {
            mergePods(pods)
        }
    }
    
    func resetAdPods() async {
        self.adPods.removeAll()
    }
    
    func playheadIsIncludedInStoredAdPods(playhead: Double? = nil) -> Bool {
        let playhead = playhead ?? self.lastPlayheadTime
        for adPod in adPods {
            if let start = adPod.startTime, let duration = adPod.duration {
                let startWithTolerance = start - AD_START_TOLERANCE_FOR_TIMEJUMP_RESET
                let endWithTolerance = start + duration + AD_END_TRACKING_EVENT_TIME_TOLERANCE
                if startWithTolerance...endWithTolerance ~= playhead {
                    return true
                }
            }
        }
        
        return false
    }
    
    func playheadIsInAd(_ ad: Ad, playhead: Double? = nil) -> Bool {
        let playhead = playhead ?? self.lastPlayheadTime
        if let start = ad.startTime, let duration = ad.duration {
            if start...(start + duration + AD_END_TRACKING_EVENT_TIME_TOLERANCE) ~= playhead {
                return true
            }
        }
        return false
    }
    
    private func setTimeJumpObservation() {
        timeJumpObservation = NotificationCenter.default
            .publisher(for: AVPlayerItem.timeJumpedNotification)
            .sink(receiveValue: { [weak self] notification in
                guard let self = self else { return }
                guard !self.adPods.isEmpty else { return }
                guard let item = notification.object as? AVPlayerItem else { return }
                guard let currentPlayhead = item.currentDate() else { return }
                
                let lastPlayhead = Date(timeIntervalSince1970: (self.lastPlayheadTime / 1_000))
                if !self.playheadIsIncludedInStoredAdPods(playhead: self.lastPlayheadTime),
                   abs(lastPlayhead.timeIntervalSince(currentPlayhead)) > RESET_AD_PODS_IF_TIMEJUMP_EXCEEDS {
                    let adPodIDs = self.adPods.map { $0.id ?? "nil" }
                    Self.logger.trace("Detected time jump (current playhead: \(HarmonicAdTracker.getFormattedString(from: currentPlayhead)) (last playhead: \(HarmonicAdTracker.getFormattedString(from: lastPlayhead))), resetting ad pods (\(adPodIDs))")
                    Task {
                        await self.resetAdPods()
                        await self.checkNeedUpdate()
                    }
                }
            })
    }
}
