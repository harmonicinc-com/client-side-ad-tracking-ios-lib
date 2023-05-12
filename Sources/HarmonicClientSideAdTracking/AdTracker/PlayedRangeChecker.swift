//
//  PlayedRangeChecker.swift
//  
//
//  Created by Michael on 10/5/2023.
//

import Foundation
import Combine

private let CHECK_PLAYHEAD_IS_IN_DATARANGE_INTERVAL: TimeInterval = 1
private let PLAYHEAD_TIME_END_TOLERANCE: Double = CHECK_PLAYHEAD_IS_IN_DATARANGE_INTERVAL * 1_000
private let UPDATE_STORED_TIME_TOLERANCE: Double = PLAYHEAD_TIME_END_TOLERANCE / 2

@MainActor
class PlayedRangeChecker {
    
    private let session: AdBeaconingSession
    
    private var shouldCheckBeacon = true
    private var checkPlayheadIsInDataRangeTimer: AnyCancellable?
    
    init(session: AdBeaconingSession) {
        self.session = session
    }
    
    func start() {
        setCheckPlayheadIsInDataRangeTimer()
    }
    
    func stop() {
        checkPlayheadIsInDataRangeTimer?.cancel()
    }
    
    func setShouldCheckBeacon(_ shouldCheckBeacon: Bool) {
        self.shouldCheckBeacon = shouldCheckBeacon
    }
    
    private func setCheckPlayheadIsInDataRangeTimer() {
        checkPlayheadIsInDataRangeTimer = Timer.publish(every: CHECK_PLAYHEAD_IS_IN_DATARANGE_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                Task {
                    guard let playhead = self.session.playerObserver.playhead else { return }
                    if self.shouldCheckBeacon && !(self.session.latestDataRange?.contains(playhead) ?? false) {
                        self.updatePlayedRangeOutsideDataRange(playhead)
                    }
                }
            })
    }
    
    private func updatePlayedRangeOutsideDataRange(_ playhead: Double) {
        guard playhead != 0 else { return }
        
        var canUpdateExistingDataRanges = false
        for dataRange in session.playedTimeOutsideDataRange {
            if dataRange.contains(playhead - UPDATE_STORED_TIME_TOLERANCE) || dataRange.contains(playhead) {
                canUpdateExistingDataRanges = true
                dataRange.end = playhead + PLAYHEAD_TIME_END_TOLERANCE
                break
            }
        }
        
        if !canUpdateExistingDataRanges {
            let newPlayedTimeOutsideDataRange = DataRange(start: playhead, end: playhead + PLAYHEAD_TIME_END_TOLERANCE)
            session.playedTimeOutsideDataRange.append(newPlayedTimeOutsideDataRange)
        }
    }
    
}
