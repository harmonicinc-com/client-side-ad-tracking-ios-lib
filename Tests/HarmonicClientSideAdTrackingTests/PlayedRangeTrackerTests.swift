//
//  PlayedRangeTrackerTests.swift
//
//
//  Created by Michael on 2/1/2026.
//

import XCTest
import AVFoundation
@testable import HarmonicClientSideAdTracking

@MainActor
final class PlayedRangeTrackerTests: XCTestCase {
    
    var session: AdBeaconingSession!
    var tracker: PlayedRangeTracker!
    
    override func setUp() async throws {
        try await super.setUp()
        session = AdBeaconingSession()
        tracker = PlayedRangeTracker(session: session)
    }
    
    override func tearDown() async throws {
        tracker.stop()
        session.cleanup()
        tracker = nil
        session = nil
        try await super.tearDown()
    }
    
    // MARK: - trackPosition Tests
    
    func testTrackPosition_FirstPosition_CreatesNewRange() async throws {
        // Given: An empty tracker
        XCTAssertEqual(tracker.getRangeCount(), 0, "Should start with no ranges")
        
        // When: Tracking a position
        tracker.trackPosition(5000)
        
        // Then: Should create a new range
        XCTAssertEqual(tracker.getRangeCount(), 1, "Should have one range")
        
        let ranges = tracker.getRanges()
        XCTAssertEqual(ranges.first?.start, 5000, "Range start should be the tracked position")
        XCTAssertEqual(ranges.first?.end, 5000, "Range end should be the tracked position")
    }
    
    func testTrackPosition_NegativePosition_IsIgnored() async throws {
        // Given: An empty tracker
        XCTAssertEqual(tracker.getRangeCount(), 0)
        
        // When: Tracking a negative position
        tracker.trackPosition(-1000)
        
        // Then: Should not create a range
        XCTAssertEqual(tracker.getRangeCount(), 0, "Should not track negative positions")
    }
    
    func testTrackPosition_ConsecutivePositions_ExtendsRange() async throws {
        // Given: A tracker with an initial position
        tracker.trackPosition(5000)
        
        // When: Tracking consecutive positions within tolerance (500ms * 2 * 1000 = 1000ms tolerance)
        tracker.trackPosition(5500)
        tracker.trackPosition(6000)
        tracker.trackPosition(6500)
        
        // Then: Should extend the same range
        XCTAssertEqual(tracker.getRangeCount(), 1, "Should still have one range")
        
        let ranges = tracker.getRanges()
        XCTAssertEqual(ranges.first?.start, 5000, "Range start should remain the initial position")
        XCTAssertEqual(ranges.first?.end, 6500, "Range end should be the last tracked position")
    }
    
    func testTrackPosition_PositionWithinRange_DoesNotExtend() async throws {
        // Given: A tracker with an existing continuous range (positions within tolerance of each other)
        // Tolerance is 1000ms (POSITION_TRACKING_INTERVAL * 2 * 1000)
        tracker.trackPosition(5000)
        tracker.trackPosition(5500)
        tracker.trackPosition(6000)
        
        XCTAssertEqual(tracker.getRangeCount(), 1, "Should have one range")
        
        // When: Tracking a position within the existing range
        tracker.trackPosition(5500)
        
        // Then: Range should remain the same
        XCTAssertEqual(tracker.getRangeCount(), 1, "Should still have one range")
        
        let ranges = tracker.getRanges()
        XCTAssertEqual(ranges.first?.start, 5000, "Range start should not change")
        XCTAssertEqual(ranges.first?.end, 6000, "Range end should not change")
    }
    
    func testTrackPosition_DisconnectedPosition_CreatesNewRange() async throws {
        // Given: A tracker with an existing range
        tracker.trackPosition(5000)
        tracker.trackPosition(6000)
        
        // When: Tracking a position far from the existing range (beyond tolerance)
        tracker.trackPosition(20000)
        
        // Then: Should create a new separate range
        XCTAssertEqual(tracker.getRangeCount(), 2, "Should have two separate ranges")
        
        let ranges = tracker.getRanges()
        // Ranges should be sorted by start time
        XCTAssertEqual(ranges[0].start, 5000, "First range start")
        XCTAssertEqual(ranges[0].end, 6000, "First range end")
        XCTAssertEqual(ranges[1].start, 20000, "Second range start")
        XCTAssertEqual(ranges[1].end, 20000, "Second range end")
    }
    
    func testTrackPosition_PositionBeforeRange_ExtendsRangeBackward() async throws {
        // Given: A tracker with an existing range
        tracker.trackPosition(10000)
        
        // When: Tracking a position just before the range (within tolerance)
        tracker.trackPosition(9500)
        
        // Then: Should extend the range backward
        XCTAssertEqual(tracker.getRangeCount(), 1, "Should still have one range")
        
        let ranges = tracker.getRanges()
        XCTAssertEqual(ranges.first?.start, 9500, "Range start should be extended backward")
        XCTAssertEqual(ranges.first?.end, 10000, "Range end should remain the same")
    }
    
    func testTrackPosition_MergesAdjacentRanges() async throws {
        // Given: Two separate ranges
        tracker.trackPosition(5000)
        tracker.trackPosition(6000)
        // Create a gap
        tracker.trackPosition(10000)
        tracker.trackPosition(11000)
        
        XCTAssertEqual(tracker.getRangeCount(), 2, "Should have two separate ranges initially")
        
        // When: Tracking positions that bridge the gap (within tolerance of both ranges)
        // Tolerance is 1000ms, so position 7000 should connect to range ending at 6000
        // and position 9000 should connect to range starting at 10000
        tracker.trackPosition(7000)
        tracker.trackPosition(8000)
        tracker.trackPosition(9000)
        
        // Then: Ranges should be merged
        XCTAssertEqual(tracker.getRangeCount(), 1, "Ranges should be merged into one")
        
        let ranges = tracker.getRanges()
        XCTAssertEqual(ranges.first?.start, 5000, "Merged range should start at first range's start")
        XCTAssertEqual(ranges.first?.end, 11000, "Merged range should end at second range's end")
    }
    
    func testTrackPosition_ZeroPosition_IsTracked() async throws {
        // Given: An empty tracker
        XCTAssertEqual(tracker.getRangeCount(), 0)
        
        // When: Tracking position 0
        tracker.trackPosition(0)
        
        // Then: Should create a range at 0
        XCTAssertEqual(tracker.getRangeCount(), 1, "Should track position 0")
        
        let ranges = tracker.getRanges()
        XCTAssertEqual(ranges.first?.start, 0, "Range should start at 0")
        XCTAssertEqual(ranges.first?.end, 0, "Range should end at 0")
    }
    
    func testTrackPosition_MultipleDisconnectedRanges() async throws {
        // Given/When: Creating multiple disconnected ranges
        tracker.trackPosition(0)
        tracker.trackPosition(1000)
        
        tracker.trackPosition(10000)
        tracker.trackPosition(11000)
        
        tracker.trackPosition(20000)
        tracker.trackPosition(21000)
        
        // Then: Should have three separate ranges
        XCTAssertEqual(tracker.getRangeCount(), 3, "Should have three separate ranges")
        
        let ranges = tracker.getRanges()
        XCTAssertEqual(ranges[0].start, 0)
        XCTAssertEqual(ranges[0].end, 1000)
        XCTAssertEqual(ranges[1].start, 10000)
        XCTAssertEqual(ranges[1].end, 11000)
        XCTAssertEqual(ranges[2].start, 20000)
        XCTAssertEqual(ranges[2].end, 21000)
    }
    
    // MARK: - wasTimePlayed Tests
    
    func testWasTimePlayed_EmptyTracker_ReturnsFalse() async throws {
        // Given: An empty tracker
        XCTAssertEqual(tracker.getRangeCount(), 0)
        
        // When/Then: Checking any time should return false
        XCTAssertFalse(tracker.wasTimePlayed(5000), "Should return false when no positions tracked")
        XCTAssertFalse(tracker.wasTimePlayed(0), "Should return false for zero")
        XCTAssertFalse(tracker.wasTimePlayed(100000), "Should return false for any time")
    }
    
    func testWasTimePlayed_TimeWithinRange_ReturnsTrue() async throws {
        // Given: A tracker with a continuous range from 5000 to 6000
        // (positions must be within tolerance to form a single range)
        tracker.trackPosition(5000)
        tracker.trackPosition(5500)
        tracker.trackPosition(6000)
        
        // When/Then: Checking times within the range should return true
        XCTAssertTrue(tracker.wasTimePlayed(5000), "Should return true for start of range")
        XCTAssertTrue(tracker.wasTimePlayed(5500), "Should return true for middle of range")
        XCTAssertTrue(tracker.wasTimePlayed(6000), "Should return true for end of range")
    }
    
    func testWasTimePlayed_TimeOutsideRange_ReturnsFalse() async throws {
        // Given: A tracker with a continuous range from 5000 to 6000
        tracker.trackPosition(5000)
        tracker.trackPosition(5500)
        tracker.trackPosition(6000)
        
        // When/Then: Checking times outside the range should return false
        XCTAssertFalse(tracker.wasTimePlayed(4999), "Should return false for time before range")
        XCTAssertFalse(tracker.wasTimePlayed(6001), "Should return false for time after range")
        XCTAssertFalse(tracker.wasTimePlayed(0), "Should return false for zero")
        XCTAssertFalse(tracker.wasTimePlayed(20000), "Should return false for far outside range")
    }
    
    func testWasTimePlayed_TimeInOneOfMultipleRanges_ReturnsTrue() async throws {
        // Given: Multiple disconnected ranges
        tracker.trackPosition(0)
        tracker.trackPosition(1000)
        
        tracker.trackPosition(10000)
        tracker.trackPosition(11000)
        
        tracker.trackPosition(20000)
        tracker.trackPosition(21000)
        
        // When/Then: Checking times within any range should return true
        XCTAssertTrue(tracker.wasTimePlayed(500), "Should return true for time in first range")
        XCTAssertTrue(tracker.wasTimePlayed(10500), "Should return true for time in second range")
        XCTAssertTrue(tracker.wasTimePlayed(20500), "Should return true for time in third range")
    }
    
    func testWasTimePlayed_TimeBetweenRanges_ReturnsFalse() async throws {
        // Given: Two disconnected ranges
        tracker.trackPosition(0)
        tracker.trackPosition(1000)
        
        tracker.trackPosition(10000)
        tracker.trackPosition(11000)
        
        // When/Then: Checking times between ranges should return false
        XCTAssertFalse(tracker.wasTimePlayed(5000), "Should return false for time between ranges")
        XCTAssertFalse(tracker.wasTimePlayed(1001), "Should return false just after first range")
        XCTAssertFalse(tracker.wasTimePlayed(9999), "Should return false just before second range")
    }
    
    // MARK: - clearRanges Tests
    
    func testClearRanges_RemovesAllRanges() async throws {
        // Given: A tracker with multiple ranges
        tracker.trackPosition(5000)
        tracker.trackPosition(10000)
        tracker.trackPosition(20000)
        
        XCTAssertGreaterThan(tracker.getRangeCount(), 0, "Should have ranges before clearing")
        
        // When: Clearing all ranges
        tracker.clearRanges()
        
        // Then: Should have no ranges
        XCTAssertEqual(tracker.getRangeCount(), 0, "Should have no ranges after clearing")
        XCTAssertTrue(tracker.getRanges().isEmpty, "getRanges should return empty array")
    }
    
    // MARK: - cleanupOldRanges Tests
    
    func testCleanupOldRanges_RemovesRangesBeyondRetention() async throws {
        // Given: Multiple ranges at different positions
        tracker.trackPosition(0)
        tracker.trackPosition(1000)
        
        tracker.trackPosition(10000)
        tracker.trackPosition(11000)
        
        tracker.trackPosition(50000)
        tracker.trackPosition(51000)
        
        XCTAssertEqual(tracker.getRangeCount(), 3, "Should have three ranges initially")
        
        // When: Cleaning up with current position at 52000 and retention of 10000ms
        tracker.cleanupOldRanges(currentPosition: 52000, retentionMs: 10000)
        
        // Then: Should only keep the most recent range
        XCTAssertEqual(tracker.getRangeCount(), 1, "Should have only one range after cleanup")
        
        let ranges = tracker.getRanges()
        XCTAssertEqual(ranges.first?.start, 50000, "Remaining range should be the most recent")
        XCTAssertEqual(ranges.first?.end, 51000)
    }
    
    func testCleanupOldRanges_KeepsRangesWithinRetention() async throws {
        // Given: Multiple ranges
        tracker.trackPosition(40000)
        tracker.trackPosition(41000)
        
        tracker.trackPosition(45000)
        tracker.trackPosition(46000)
        
        tracker.trackPosition(50000)
        tracker.trackPosition(51000)
        
        XCTAssertEqual(tracker.getRangeCount(), 3, "Should have three ranges initially")
        
        // When: Cleaning up with a large retention window
        tracker.cleanupOldRanges(currentPosition: 52000, retentionMs: 20000)
        
        // Then: Should keep all ranges within retention
        XCTAssertEqual(tracker.getRangeCount(), 3, "Should keep all ranges within retention")
    }
    
    // MARK: - Edge Cases
    
    func testTrackPosition_LargeValues() async throws {
        // Given: Very large position values (e.g., long video in milliseconds)
        let largeValue: Double = 3600000 // 1 hour in milliseconds
        
        // When: Tracking large positions
        tracker.trackPosition(largeValue)
        tracker.trackPosition(largeValue + 500)
        
        // Then: Should handle correctly
        XCTAssertEqual(tracker.getRangeCount(), 1)
        XCTAssertTrue(tracker.wasTimePlayed(largeValue + 250))
    }
    
    func testTrackPosition_RapidConsecutiveTracking() async throws {
        // Given: Rapid consecutive position tracking (simulating fast updates)
        for i in stride(from: 0, to: 10000, by: 100) {
            tracker.trackPosition(Double(i))
        }
        
        // Then: Should maintain a single continuous range
        XCTAssertEqual(tracker.getRangeCount(), 1, "Continuous tracking should result in one range")
        
        let ranges = tracker.getRanges()
        XCTAssertEqual(ranges.first?.start, 0)
        XCTAssertEqual(ranges.first?.end, 9900)
        
        // And all positions should be marked as played
        XCTAssertTrue(tracker.wasTimePlayed(0))
        XCTAssertTrue(tracker.wasTimePlayed(5000))
        XCTAssertTrue(tracker.wasTimePlayed(9900))
    }
}
