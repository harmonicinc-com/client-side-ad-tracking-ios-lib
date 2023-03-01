//
//  HarmonicAdTracker+Metadata.swift
//  
//
//  Created by Michael on 1/3/2023.
//

import Foundation

private let METADATA_UPDATE_INTERVAL: TimeInterval = 4
private let KEEP_PODS_FOR_MS: Double = 1_000 * 60 * 2   // 2 minutes

extension HarmonicAdTracker {
    func setRefreshMetadataTimer() {
        refreshMetadatTimer = Timer.publish(every: METADATA_UPDATE_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.checkNeedUpdate()
                }
            })
    }
    
    func checkNeedUpdate() async {
        var url = session.sessionInfo.adTrackingMetadataUrl
        let lastPlayheadTime = await getPlayheadTime()
        Self.logger.trace("Calling refreshMetadata without start; playhead is \(HarmonicAdTracker.getFormattedString(from: lastPlayheadTime), privacy: .public)")
        let result = await refreshMetadata(urlString: url, time: lastPlayheadTime)
        if !result {
            url += "&start=\(Int(lastPlayheadTime))"
            Self.logger.trace("Calling refreshMetadata with start: \(HarmonicAdTracker.getFormattedString(from: lastPlayheadTime), privacy: .public) with url: \(url, privacy: .public)")
            if await !refreshMetadata(urlString: url, time: nil) {
                Self.logger.warning("refreshMetadata for url with start: \(url, privacy: .public) returned false.")
            }
        }
    }
    
    func refreshMetadata(urlString: String, time: Double?) async -> Bool {
        guard !urlString.isEmpty else { return false }
        
        do {
            guard let (data, _) = try await HarmonicAdTracker.makeRequestTo(urlString) else {
                return false
            }
            
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let adBeacon = try decoder.decode(AdBeacon.self, from: data)
            
            guard let lastDataRange = adBeacon.dataRange,
                  lastDataRange.start != nil,
                  lastDataRange.end != nil else {
                Self.logger.warning("No DataRange returned in metadata.")
                return false
            }
            self.lastDataRange = lastDataRange
            
            let adPodIDs = adBeacon.adBreaks.map { $0.id ?? "nil" }
            
            guard HarmonicAdTracker.isInRange(time: time, range: lastDataRange) else {
                let timeDate = Date(timeIntervalSince1970: (time ?? 0) / 1_000)
                Self.logger.warning("Invalid metadata (with ad pods: \(adPodIDs, privacy: .public)): Time (\(HarmonicAdTracker.getFormattedString(from: timeDate), privacy: .public)) not in \(lastDataRange, privacy: .public))")
                return false
            }
            
            Self.logger.trace("Going to update \(adBeacon.adBreaks.count) ad pods: \(adPodIDs, privacy: .public) with \(lastDataRange, privacy: .public)")
            await updatePods(adBeacon.adBreaks)
            await checkNeedSendBeaconsForPlayedTime()
            
            return true
        } catch {
            let errorMessage = "Error refreshing metadata with URL: \(urlString); Error: \(error)"
            Self.logger.error("\(errorMessage, privacy: .public)")
            return false
        }
    }
    
    func mergePods(_ newPods: [AdBreak]) {
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
    
    func mergeAds(existingAds: inout [Ad], newAds: [Ad]) {
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
