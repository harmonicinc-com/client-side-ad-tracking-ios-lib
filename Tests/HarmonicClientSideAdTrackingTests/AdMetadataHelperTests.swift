//
//  AdMetadataHelperTests.swift
//
//
//  Created by Michael on 2/1/2026.
//

import XCTest
@testable import HarmonicClientSideAdTracking

final class AdMetadataHelperTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    /// Creates a test ad with tracking events
    private func createAd(
        id: String,
        startTime: Double,
        duration: Double,
        trackingEvents: [TrackingEvent] = []
    ) -> Ad {
        return Ad(
            id: id,
            startTime: startTime,
            duration: duration,
            trackingEvents: trackingEvents
        )
    }
    
    /// Creates a test ad break (pod) with ads
    private func createAdBreak(
        id: String,
        startTime: Double,
        duration: Double,
        ads: [Ad] = []
    ) -> AdBreak {
        return AdBreak(
            id: id,
            startTime: startTime,
            duration: duration,
            ads: ads
        )
    }
    
    /// Creates a tracking event for testing
    private func createTrackingEvent(
        eventType: EventType,
        startTime: Double,
        duration: Double = 0,
        signalingUrls: [String] = [],
        reportingState: ReportingState = .idle
    ) -> TrackingEvent {
        return TrackingEvent(
            event: eventType,
            startTime: startTime,
            duration: duration,
            signalingUrls: signalingUrls,
            reportingState: reportingState
        )
    }
    
    // MARK: - mergePods Tests - Basic Scenarios
    
    func testMergePods_EmptyExistingPods_ReturnsNewPods() {
        // Given: Empty existing pods and new pods
        let existingPods: [AdBreak] = []
        let newPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 15000),
                createAd(id: "ad-2", startTime: 15000, duration: 15000)
            ])
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: Should return the new pods
        XCTAssertEqual(result.count, 1, "Should have one pod")
        XCTAssertEqual(result[0].id, "pod-1")
        XCTAssertEqual(result[0].ads.count, 2, "Should have two ads")
    }
    
    func testMergePods_EmptyNewPods_KeepsExistingPodsWithinRetention() {
        // Given: Existing pods and empty new pods, playhead at 0
        let existingPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 30000)
            ])
        ]
        let newPods: [AdBreak] = []
        
        // When: Merging with playhead at 0 and large retention window
        // Pod ends at 30000, keepPodsForMs is 60000, playhead is 0
        // 30000 + 60000 = 90000 > 0 (playhead), so pod is kept
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: Should keep existing pod within retention window even if not in new pods
        XCTAssertEqual(result.count, 1, "Should keep pod within retention window")
        XCTAssertEqual(result[0].id, "pod-1")
    }
    
    func testMergePods_EmptyNewPods_RemovesExpiredPods() {
        // Given: Existing pods and empty new pods
        let existingPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 30000)
            ])
        ]
        let newPods: [AdBreak] = []
        
        // When: Merging with playhead past retention window
        // Pod ends at 30000, keepPodsForMs is 10000
        // 30000 + 10000 = 40000 < 50000 (playhead), so pod should be removed
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 50000, keepPodsForMs: 10000)
        
        // Then: Should remove expired pod not in new pods list
        XCTAssertEqual(result.count, 0, "Should remove expired pods not in new pods list")
    }
    
    func testMergePods_BothEmpty_ReturnsEmpty() {
        // Given: Both existing and new pods are empty
        let existingPods: [AdBreak] = []
        let newPods: [AdBreak] = []
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: Should return empty array
        XCTAssertTrue(result.isEmpty, "Should return empty array")
    }
    
    // MARK: - mergePods Tests - Updating Existing Pods
    
    func testMergePods_UpdatesExistingPodDuration() {
        // Given: An existing pod and a new pod with updated duration
        let existingPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 30000)
            ])
        ]
        let newPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 45000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 45000)
            ])
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: Should update the duration
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].duration, 45000, "Pod duration should be updated")
    }
    
    func testMergePods_UpdatesExistingAdDuration() {
        // Given: An existing pod with an ad and new pod with updated ad duration
        let existingPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 15000)
            ])
        ]
        let newPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 20000)
            ])
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: Should update the ad duration
        XCTAssertEqual(result[0].ads.count, 1)
        XCTAssertEqual(result[0].ads[0].duration, 20000, "Ad duration should be updated")
    }
    
    // MARK: - mergePods Tests - Adding New Content
    
    func testMergePods_AddsNewPodToExisting() {
        // Given: An existing pod and a new different pod
        let existingPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 30000)
            ])
        ]
        let newPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 30000)
            ]),
            createAdBreak(id: "pod-2", startTime: 60000, duration: 30000, ads: [
                createAd(id: "ad-2", startTime: 60000, duration: 30000)
            ])
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: Should have both pods
        XCTAssertEqual(result.count, 2, "Should have two pods")
        XCTAssertEqual(result[0].id, "pod-1")
        XCTAssertEqual(result[1].id, "pod-2")
    }
    
    func testMergePods_AddsNewAdToExistingPod() {
        // Given: An existing pod with one ad and new pod with additional ad
        let existingPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 15000)
            ])
        ]
        let newPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 15000),
                createAd(id: "ad-2", startTime: 15000, duration: 15000)
            ])
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: Should have both ads
        XCTAssertEqual(result[0].ads.count, 2, "Should have two ads")
        XCTAssertEqual(result[0].ads[0].id, "ad-1")
        XCTAssertEqual(result[0].ads[1].id, "ad-2")
    }
    
    // MARK: - mergePods Tests - Removal Logic
    
    func testMergePods_RemovesOldPodsBasedOnPlayhead() {
        // Given: An old pod that's past the retention window
        let existingPods = [
            createAdBreak(id: "old-pod", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 30000)
            ]),
            createAdBreak(id: "current-pod", startTime: 100000, duration: 30000, ads: [
                createAd(id: "ad-2", startTime: 100000, duration: 30000)
            ])
        ]
        // New pods only contains current-pod
        let newPods = [
            createAdBreak(id: "current-pod", startTime: 100000, duration: 30000, ads: [
                createAd(id: "ad-2", startTime: 100000, duration: 30000)
            ])
        ]
        
        // When: Merging with playhead at 150000 (past the old pod + keepPodsForMs)
        // old-pod ends at 30000, keepPodsForMs is 10000, so it should be removed when playhead > 40000
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 150000, keepPodsForMs: 10000)
        
        // Then: Should remove the old pod
        XCTAssertEqual(result.count, 1, "Should only have one pod")
        XCTAssertEqual(result[0].id, "current-pod", "Should keep the current pod")
    }
    
    func testMergePods_KeepsOldPodsWithinRetentionWindow() {
        // Given: An old pod that's still within the retention window
        let existingPods = [
            createAdBreak(id: "old-pod", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 30000)
            ])
        ]
        let newPods = [
            createAdBreak(id: "old-pod", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 30000)
            ])
        ]
        
        // When: Merging with playhead at 35000 and keepPodsForMs of 60000
        // old-pod ends at 30000, so it should be kept as 30000 + 60000 > 35000
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 35000, keepPodsForMs: 60000)
        
        // Then: Should keep the old pod
        XCTAssertEqual(result.count, 1, "Should keep the pod within retention")
        XCTAssertEqual(result[0].id, "old-pod")
    }
    
    func testMergePods_RemovesAdsNotInNewPods() {
        // Given: An existing pod with ads not in the new pods
        let existingPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 10000),
                createAd(id: "ad-2", startTime: 10000, duration: 10000),
                createAd(id: "ad-3", startTime: 20000, duration: 10000)
            ])
        ]
        let newPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 10000),
                createAd(id: "ad-3", startTime: 20000, duration: 10000)
            ])
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: ad-2 should be removed
        XCTAssertEqual(result[0].ads.count, 2, "Should have two ads after removal")
        XCTAssertEqual(result[0].ads[0].id, "ad-1")
        XCTAssertEqual(result[0].ads[1].id, "ad-3")
    }
    
    // MARK: - mergePods Tests - Sorting
    
    func testMergePods_SortsPodsbyStartTime() {
        // Given: Pods added in non-chronological order
        let existingPods: [AdBreak] = []
        let newPods = [
            createAdBreak(id: "pod-3", startTime: 90000, duration: 30000),
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000),
            createAdBreak(id: "pod-2", startTime: 60000, duration: 30000)
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 120000)
        
        // Then: Should be sorted by start time
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].id, "pod-1", "First pod should be pod-1")
        XCTAssertEqual(result[1].id, "pod-2", "Second pod should be pod-2")
        XCTAssertEqual(result[2].id, "pod-3", "Third pod should be pod-3")
    }
    
    func testMergePods_SortsAdsWithinPodByStartTime() {
        // Given: Ads in non-chronological order
        let existingPods: [AdBreak] = []
        let newPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 45000, ads: [
                createAd(id: "ad-3", startTime: 30000, duration: 15000),
                createAd(id: "ad-1", startTime: 0, duration: 15000),
                createAd(id: "ad-2", startTime: 15000, duration: 15000)
            ])
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: Ads should be sorted by start time
        XCTAssertEqual(result[0].ads.count, 3)
        XCTAssertEqual(result[0].ads[0].id, "ad-1")
        XCTAssertEqual(result[0].ads[1].id, "ad-2")
        XCTAssertEqual(result[0].ads[2].id, "ad-3")
    }
    
    // MARK: - mergePods Tests - Tracking Events
    
    func testMergePods_PreservesTrackingEventsForNewAds() {
        // Given: New pods with ads containing tracking events
        let existingPods: [AdBreak] = []
        let trackingEvents = [
            createTrackingEvent(eventType: .start, startTime: 0, signalingUrls: ["https://example.com/start"]),
            createTrackingEvent(eventType: .complete, startTime: 30000, signalingUrls: ["https://example.com/complete"])
        ]
        let newPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                Ad(id: "ad-1", startTime: 0, duration: 30000, trackingEvents: trackingEvents)
            ])
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: Should preserve tracking events with idle state
        XCTAssertEqual(result[0].ads[0].trackingEvents.count, 2, "Should have two tracking events")
        XCTAssertEqual(result[0].ads[0].trackingEvents[0].event, .start)
        XCTAssertEqual(result[0].ads[0].trackingEvents[1].event, .complete)
        
        // Verify reporting states are set to idle
        XCTAssertEqual(result[0].ads[0].trackingEvents[0].reportingState, .idle)
        XCTAssertEqual(result[0].ads[0].trackingEvents[1].reportingState, .idle)
    }
    
    func testMergePods_FiltersOutUnknownEventTypes() {
        // Given: New pods with ads containing unknown event types
        let existingPods: [AdBreak] = []
        let trackingEvents = [
            createTrackingEvent(eventType: .start, startTime: 0),
            createTrackingEvent(eventType: .unknown, startTime: 5000), // Should be filtered out
            createTrackingEvent(eventType: .complete, startTime: 30000)
        ]
        let newPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                Ad(id: "ad-1", startTime: 0, duration: 30000, trackingEvents: trackingEvents)
            ])
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 0, keepPodsForMs: 60000)
        
        // Then: Should filter out unknown event types
        XCTAssertEqual(result[0].ads[0].trackingEvents.count, 2, "Should filter out unknown event type")
        XCTAssertEqual(result[0].ads[0].trackingEvents[0].event, .start)
        XCTAssertEqual(result[0].ads[0].trackingEvents[1].event, .complete)
    }
    
    // MARK: - mergePods Tests - Complex Scenarios
    
    func testMergePods_ComplexMergeScenario() {
        // Given: A complex scenario with multiple pods, some to update, some to add, some to remove
        let existingPods = [
            createAdBreak(id: "pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 30000)
            ]),
            createAdBreak(id: "pod-2", startTime: 60000, duration: 30000, ads: [
                createAd(id: "ad-2", startTime: 60000, duration: 15000),
                createAd(id: "ad-3", startTime: 75000, duration: 15000)
            ])
        ]
        
        let newPods = [
            // pod-1: Update duration
            createAdBreak(id: "pod-1", startTime: 0, duration: 35000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 35000)
            ]),
            // pod-2: Remove ad-3, keep ad-2
            createAdBreak(id: "pod-2", startTime: 60000, duration: 30000, ads: [
                createAd(id: "ad-2", startTime: 60000, duration: 30000) // Updated duration
            ]),
            // pod-3: New pod
            createAdBreak(id: "pod-3", startTime: 120000, duration: 30000, ads: [
                createAd(id: "ad-4", startTime: 120000, duration: 30000)
            ])
        ]
        
        // When: Merging pods
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 50000, keepPodsForMs: 60000)
        
        // Then: Verify all changes
        XCTAssertEqual(result.count, 3, "Should have three pods")
        
        // pod-1 updated
        XCTAssertEqual(result[0].id, "pod-1")
        XCTAssertEqual(result[0].duration, 35000, "pod-1 duration should be updated")
        
        // pod-2 with ad-3 removed
        XCTAssertEqual(result[1].id, "pod-2")
        XCTAssertEqual(result[1].ads.count, 1, "pod-2 should have one ad")
        XCTAssertEqual(result[1].ads[0].id, "ad-2")
        XCTAssertEqual(result[1].ads[0].duration, 30000, "ad-2 duration should be updated")
        
        // pod-3 added
        XCTAssertEqual(result[2].id, "pod-3")
        XCTAssertEqual(result[2].ads[0].id, "ad-4")
    }
    
    func testMergePods_LiveStreamScenario() {
        // Given: A live stream scenario where old pods should be cleaned up
        let existingPods = [
            createAdBreak(id: "old-pod-1", startTime: 0, duration: 30000, ads: [
                createAd(id: "ad-1", startTime: 0, duration: 30000)
            ]),
            createAdBreak(id: "old-pod-2", startTime: 60000, duration: 30000, ads: [
                createAd(id: "ad-2", startTime: 60000, duration: 30000)
            ]),
            createAdBreak(id: "current-pod", startTime: 300000, duration: 30000, ads: [
                createAd(id: "ad-3", startTime: 300000, duration: 30000)
            ])
        ]
        
        // New metadata only contains current and future pods
        let newPods = [
            createAdBreak(id: "current-pod", startTime: 300000, duration: 30000, ads: [
                createAd(id: "ad-3", startTime: 300000, duration: 30000)
            ]),
            createAdBreak(id: "future-pod", startTime: 400000, duration: 30000, ads: [
                createAd(id: "ad-4", startTime: 400000, duration: 30000)
            ])
        ]
        
        // When: Merging with playhead at 310000 and keepPodsForMs of 60000
        // old-pod-1 (ends at 30000) and old-pod-2 (ends at 90000) should be removed
        let result = AdMetadataHelper.mergePods(existingPods, with: newPods, playhead: 310000, keepPodsForMs: 60000)
        
        // Then: Only current and future pods should remain
        XCTAssertEqual(result.count, 2, "Should only have current and future pods")
        XCTAssertEqual(result[0].id, "current-pod")
        XCTAssertEqual(result[1].id, "future-pod")
    }
}
