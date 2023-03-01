//
//  HarmonicAdTracker+PlayedTime.swift
//  
//
//  Created by Michael on 1/3/2023.
//

import Foundation

private let CHECK_PLAYHEAD_IS_IN_DATARANGE_INTERVAL: TimeInterval = 1
private let PLAYHEAD_TIME_END_TOLERANCE: Double = 1_000
private let UPDATE_STORED_TIME_TOLERANCE: Double = 500

extension HarmonicAdTracker {
    func setCheckPlayheadIsInDataRangeTimer() {
        checkPlayheadIsInDataRangeTimer = Timer.publish(every: CHECK_PLAYHEAD_IS_IN_DATARANGE_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                Task {
                    let playhead = await self.getPlayheadTime()
                    if self.shouldCheckBeacon && !(self.lastDataRange?.contains(playhead) ?? false) {
                        self.updatePlayedTimeOutsideDataRange(playhead)
                    }
                }
            })
    }
    
    func checkNeedSendBeaconsForPlayedTime() async {
        let timeRangesToCheck = getIntersectionsWithLastDataRange()
        await withTaskGroup(of: Void.self, body: { group in
            for pod in adPods {
                for ad in pod.ads {
                    for trackingEvent in ad.trackingEvents {
                        guard let reportingState = trackingEvent.reportingState else {
                            return
                        }
                        
                        if reportingState == .idle && eventIsInRanges(timeRangesToCheck, trackingEvent: trackingEvent) {
                            group.addTask {
                                await self.sendBeacon(trackingEvent)
                            }
                        }
                    }
                }
            }
        })
    }
    
    func updatePlayedTimeOutsideDataRange(_ time: Double) {
        guard time != 0 else { return }
        var canUpdateExistingDataRanges = false
        for dataRange in playedTimeOutsideDataRange {
            if dataRange.contains(time - UPDATE_STORED_TIME_TOLERANCE) || dataRange.contains(time) {
                canUpdateExistingDataRanges = true
                dataRange.end = time + PLAYHEAD_TIME_END_TOLERANCE
                break
            }
        }
        if !canUpdateExistingDataRanges {
            let newPlayedTimeOutsideDataRange = DataRange(start: time, end: time + PLAYHEAD_TIME_END_TOLERANCE)
            playedTimeOutsideDataRange.append(newPlayedTimeOutsideDataRange)
            Self.logger.trace("Added new time range played outside lastDataRange: \(self.playedTimeOutsideDataRange)")
        }
    }
    
    func getIntersectionsWithLastDataRange() -> [DataRange] {
        guard let lastDataRange = lastDataRange,
              let lastStart = lastDataRange.start,
              let lastEnd = lastDataRange.end else {
            return []
        }
        
        var intersections: [DataRange] = []
        
        for playedDataRange in playedTimeOutsideDataRange {
            guard let start = playedDataRange.start,
                  let end = playedDataRange.end else { continue }
            guard playedDataRange.overlaps(lastDataRange) else { continue }
            
            if playedDataRange.isWithin(lastDataRange) {
                intersections.append(playedDataRange)
                playedTimeOutsideDataRange.removeAll(where: { $0 == playedDataRange })
            } else {
                let intersection = DataRange(start: max(start, lastStart), end: min(end, lastEnd))
                intersections.append(intersection)
                playedDataRange.start = intersection.contains(start) ? intersection.end! : start
                playedDataRange.end = intersection.contains(end) ? intersection.start! : end
            }
        }
        
        return intersections
    }
    
    func eventIsInRanges(_ ranges: [DataRange], trackingEvent: TrackingEvent) -> Bool {
        guard let startTime = trackingEvent.startTime,
              let duration = trackingEvent.duration else {
            return false
        }
        let trackingEventRange = DataRange(start: startTime, end: startTime + max(duration, MAX_TOLERANCE_EVENT_END_TIME))
        for range in ranges {
            if trackingEventRange.isWithin(range) {
                return true
            }
        }
        return false
    }
}
