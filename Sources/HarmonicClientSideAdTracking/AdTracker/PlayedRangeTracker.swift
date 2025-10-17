//
//  PlayedRangeTracker.swift
//  
//
//  Created by Michael on 16/10/2025.
//

import Foundation
import Combine

private let POSITION_TRACKING_INTERVAL: TimeInterval = 0.5  // 500ms tolerance for continuity
private let TRACKING_TIMER_INTERVAL: TimeInterval = 0.5
private let NORMAL_PLAYBACK_SPEED_RANGE = 0.95...1.05

@MainActor
class PlayedRangeTracker {
    
    private let session: AdBeaconingSession
    private var playedRanges: [DataRange] = []
    private var trackingTimer: AnyCancellable?
    
    init(session: AdBeaconingSession) {
        self.session = session
    }
    
    func start() {
        setTrackingTimer()
    }
    
    func stop() {
        trackingTimer?.cancel()
        clearRanges()
    }
    
    private func setTrackingTimer() {
        trackingTimer = Timer.publish(every: TRACKING_TIMER_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                guard NORMAL_PLAYBACK_SPEED_RANGE ~= Double(self.session.player.rate) else { return }
                Task {
                    guard let playhead = self.session.playerObserver.playhead else { return }
                    self.trackPosition(playhead)
                }
            }
    }
    
    // Track a played position and merge ranges
    func trackPosition(_ position: Double) {
        guard position >= 0 else { return }
        
        if playedRanges.isEmpty {
            // First range
            playedRanges.append(DataRange(start: position, end: position))
            return
        }
        
        // Check if this position continues from or overlaps with any existing range
        var merged = false
        for range in playedRanges {
            if isPositionNearRange(position, range: range) {
                // Extend the range
                if position < range.start ?? Double.infinity {
                    range.start = position
                } else if position > range.end ?? -Double.infinity {
                    range.end = position
                }
                merged = true
                
                // After extending, check if we can merge with adjacent ranges
                mergeAdjacentRanges()
                break
            }
        }
        
        if !merged {
            // Position doesn't connect to any existing range - create new range
            playedRanges.append(DataRange(start: position, end: position))
            // Sort ranges by start time
            sortRanges()
            // Try to merge any adjacent ranges
            mergeAdjacentRanges()
        }
    }
    
    // Check if a position is near enough to a range to extend it
    private func isPositionNearRange(_ position: Double, range: DataRange) -> Bool {
        guard let start = range.start, let end = range.end else { return false }
        
        // Position is near if it's within the range or within tolerance of the edges
        let tolerance = POSITION_TRACKING_INTERVAL * 2 * 1_000  // Convert to milliseconds
        return position >= start - tolerance && position <= end + tolerance
    }
    
    // Merge overlapping or adjacent ranges
    private func mergeAdjacentRanges() {
        guard playedRanges.count > 1 else { return }
        
        var merged: [DataRange] = []
        var current = playedRanges[0]
        
        for i in 1..<playedRanges.count {
            let nextRange = playedRanges[i]
            
            guard let currentStart = current.start,
                  let currentEnd = current.end,
                  let nextStart = nextRange.start,
                  let nextEnd = nextRange.end else { continue }
            
            // Check if ranges overlap or are adjacent (within tolerance)
            let tolerance = POSITION_TRACKING_INTERVAL * 2 * 1_000  // Convert to milliseconds
            if currentEnd + tolerance >= nextStart {
                // Merge ranges
                current.end = max(currentEnd, nextEnd)
                current.start = min(currentStart, nextStart)
            } else {
                // No overlap, save current and move to next
                merged.append(current)
                current = nextRange
            }
        }
        
        // Add the last range
        merged.append(current)
        playedRanges = merged
    }
    
    // Sort ranges by start time
    private func sortRanges() {
        playedRanges.sort { ($0.start ?? 0) < ($1.start ?? 0) }
    }
    
    // Check if a time point was played
    func wasTimePlayed(_ time: Double) -> Bool {
        return playedRanges.contains { range in
            range.contains(time)
        }
    }
    
    // Clean up old ranges beyond retention time
    func cleanupOldRanges(currentPosition: Double, retentionMs: Double) {
        playedRanges = playedRanges.filter { range in
            guard let end = range.end else { return true }
            return currentPosition - end < retentionMs
        }
    }
    
    // Get all played ranges
    func getRanges() -> [DataRange] {
        return playedRanges
    }
    
    // Clear all ranges
    func clearRanges() {
        playedRanges.removeAll()
    }
    
    // Get count of ranges
    func getRangeCount() -> Int {
        return playedRanges.count
    }
}
