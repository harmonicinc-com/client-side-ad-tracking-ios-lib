//
//  HarmonicAdTracker.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import AVFoundation
import Combine
import os

private let AD_START_TOLERANCE_FOR_TIMEJUMP_RESET: Double = 3_000
private let AD_END_TRACKING_EVENT_TIME_TOLERANCE: Double = 500
private let MAX_TOLERANCE_IN_SPEED: Double = 2.5
private let MAX_TOLERANCE_EVENT_END_TIME: Double = 1_000
private let KEEP_PODS_FOR_MS: Double = 1_000 * 60 * 2   // 2 minutes
private let METADATA_UPDATE_INTERVAL: TimeInterval = 2

enum HarmonicAdTrackerError: Error {
    case runtimeError(String)
}

@MainActor
public class HarmonicAdTracker: ClientSideAdTracker, ObservableObject {
    static let logger = Logger(
        subsystem: Bundle.module.bundleIdentifier!,
        category: String(describing: HarmonicAdTracker.self)
    )
    
    @Published
    public private(set) var adPods: [AdBreak] = []
    
    @Published
    public var session = Session()
    
    private var lastPlayheadTime: Double = 0
    private var lastPlayheadUpdateTime: Double = 0
    private var lastDataRange: DataRange?
    
    private let decoder = JSONDecoder()
    private var refreshMetadatTimer: AnyCancellable?
    private var timeJumpObservation: AnyCancellable?
    
    public init(adPods: [AdBreak] = [], lastPlayheadTime: Double = 0, lastPlayheadUpdateTime: Double = 0) {
        self.adPods = adPods
        self.lastPlayheadTime = lastPlayheadTime
        self.lastPlayheadUpdateTime = lastPlayheadUpdateTime
        
        self.setRefreshMetadataTimer()
        self.setTimeJumpObservation()
    }
    
    public func stop() async {
        await resetAdPods()
        refreshMetadatTimer?.cancel()
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
    
    public func getPlayheadTime() async -> Double {
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
    
    // MARK: Internal
    
    func playheadIsIncludedInStoredAdPods(playhead: Double? = nil) -> Bool {
        let playhead = playhead ?? self.lastPlayheadTime
        for adPod in adPods {
            if let start = adPod.startTime, let duration = adPod.duration {
                if (start - AD_START_TOLERANCE_FOR_TIMEJUMP_RESET)...(start + duration + AD_END_TRACKING_EVENT_TIME_TOLERANCE) ~= playhead {
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
    
    // MARK: Private
    
    private func setRefreshMetadataTimer() {
        refreshMetadatTimer = Timer.publish(every: METADATA_UPDATE_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.checkNeedUpdate()
                }
            })
    }
    
    private func setTimeJumpObservation() {
        timeJumpObservation = NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                if !self.playheadIsIncludedInStoredAdPods(playhead: self.lastPlayheadTime) {
                    let adPodIDs = self.adPods.map { $0.id ?? "nil" }
                    Self.logger.trace("Detected time jump (playhead: \(Date(timeIntervalSince1970: (self.lastPlayheadTime / 1_000)))), resetting ad pods (\(adPodIDs))")
                    Task {
                        await self.resetAdPods()
                    }
                }
            })
    }
    
    private func updatePods(_ pods: [AdBreak]?) async {
        if let pods = pods {
            mergePods(pods)
        }
    }
    
    private func resetAdPods() async {
        self.adPods.removeAll()
    }
    
    private func checkNeedUpdate() async {
        var url = session.sessionInfo.adTrackingMetadataUrl
        let lastPlayheadTime = await getPlayheadTime()
        Self.logger.trace("Calling refreshMetadata without start; playhead is \(Date(timeIntervalSince1970: lastPlayheadTime/1_000), privacy: .public)")
        let result = await refreshMetadata(urlString: url, time: lastPlayheadTime)
        if let lastDataRange = lastDataRange {
            if !HarmonicAdTracker.isInRange(time: lastPlayheadTime, range: lastDataRange) && !result {
                url += "&start=\(Int(lastPlayheadTime))"
                Self.logger.trace("Calling refreshMetadata with start: \(Date(timeIntervalSince1970: lastPlayheadTime/1_000), privacy: .public) with url: \(url, privacy: .public)")
                if await !refreshMetadata(urlString: url, time: nil) {
                    Self.logger.warning("refreshMetadata for url with start: \(url, privacy: .public) returned false.")
                }
            }
        }
    }
    
    private func refreshMetadata(urlString: String, time: Double?) async -> Bool {
        guard !urlString.isEmpty else { return false }
        
        do {
            guard let (data, _) = try await HarmonicAdTracker.makeRequestTo(urlString) else {
                return false
            }
            
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let adBeacon = try decoder.decode(AdBeacon.self, from: data)
            
            let adPodIDs = adBeacon.adBreaks.map { $0.id ?? "nil" }
            var startDate: Date = .distantPast
            var endDate: Date = .distantPast
            
            if let lastDataRange = adBeacon.dataRange {
                self.lastDataRange = lastDataRange
                startDate = Date(timeIntervalSince1970: (lastDataRange.start ?? 0) / 1_000)
                endDate = Date(timeIntervalSince1970: (lastDataRange.end ?? 0) / 1_000)
                if !HarmonicAdTracker.isInRange(time: time, range: lastDataRange) {
                    let timeDate = Date(timeIntervalSince1970: (time ?? 0) / 1_000)
                    Self.logger.warning("Invalid metadata (with ad pods: \(adPodIDs, privacy: .public)):  Time (\(timeDate, privacy: .public)) not in range (start: \(startDate, privacy: .public), end: \(endDate, privacy: .public))")
                    return false
                }
            } else {
                Self.logger.warning("No DataRange returned in metadata.")
                return false
            }
            
            Self.logger.trace("Going to update \(adBeacon.adBreaks.count) ad pods: \(adPodIDs, privacy: .public) with DataRange: \(startDate) to \(endDate)")
            await updatePods(adBeacon.adBreaks)
            
            return true
        } catch {
            let errorMessage = "Error refreshing metadata with URL: \(urlString); Error: \(error)"
            Self.logger.error("\(errorMessage, privacy: .public)")
            return false
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
    
    private func mergePods(_ newPods: [AdBreak]) {
        adPods.removeAll { pod in
            (pod.startTime ?? 0) + (pod.duration ?? 0) + KEEP_PODS_FOR_MS < lastPlayheadTime &&
            !newPods.contains(where: { $0.id == pod.id })
        }
        
        for pod in newPods {
            let existingIndex = adPods.firstIndex(where: { $0.id == pod.id })
            var currentIndex = adPods.count
            if let existingIndex = existingIndex {
                currentIndex = existingIndex
                adPods[existingIndex].duration = pod.duration
            } else {
                let newPod = AdBreak(id: pod.id,
                                     startTime: pod.startTime,
                                     duration: pod.duration,
                                     ads: [])
                adPods.append(newPod)
            }
            mergeAds(existingAds: &adPods[currentIndex].ads, newAds: pod.ads)
        }
        
        adPods = adPods.sorted(by: { ($0.startTime ?? 0) < ($1.startTime ?? 0) })
    }
    
    private func mergeAds(existingAds: inout [Ad], newAds: [Ad]) {
        existingAds.removeAll { ad in
            !newAds.contains(where: { $0.id == ad.id })
        }
        
        for ad in newAds {
            if let existingIndex = existingAds.firstIndex(where: { $0.id == ad.id }) {
                existingAds[existingIndex].duration = ad.duration
            } else {
                let newAd = Ad(id: ad.id,
                               startTime: ad.startTime,
                               duration: ad.duration,
                               trackingEvents: ad.trackingEvents.filter( { $0.event != .unknown } ).map({ trackingEvent in
                    return TrackingEvent(event: trackingEvent.event,
                                         startTime: trackingEvent.startTime,
                                         duration: trackingEvent.duration,
                                         signalingUrls: trackingEvent.signalingUrls,
                                         reportingState: .idle)})
                )
                existingAds.append(newAd)
            }
        }
        
        existingAds = existingAds.sorted(by: { ($0.startTime ?? 0) < ($1.startTime ?? 0) })
    }
    
}
