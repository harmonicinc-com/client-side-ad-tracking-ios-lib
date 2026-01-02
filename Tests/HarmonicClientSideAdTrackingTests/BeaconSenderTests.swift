//
//  BeaconSenderTests.swift
//
//
//  Created by Michael on 24/12/2024.
//

import XCTest
import AVFoundation
@testable import HarmonicClientSideAdTracking

// MARK: - Mock HTTP Client

/// A mock HTTP client that records requests and returns configurable responses
final class MockHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    
    private var _requestedURLs: [URL] = []
    var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _requestedURLs
    }
    
    var mockStatusCode: Int = 200
    var shouldThrowError: Bool = false
    var mockError: Error?
    
    func data(from url: URL) async throws -> (Data, URLResponse) {
        lock.withLock {
            _requestedURLs.append(url)
        }
        
        if shouldThrowError {
            throw mockError ?? URLError(.badServerResponse)
        }
        
        let response = HTTPURLResponse(
            url: url,
            statusCode: mockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        
        return (Data(), response)
    }
    
    func reset() {
        lock.lock()
        _requestedURLs.removeAll()
        lock.unlock()
    }
}

// MARK: - Test Cases

@MainActor
final class BeaconSenderTests: XCTestCase {
    
    var session: AdBeaconingSession!
    var mockHTTPClient: MockHTTPClient!
    var beaconSender: BeaconSender!
    
    override func setUp() async throws {
        try await super.setUp()
        session = AdBeaconingSession()
        mockHTTPClient = MockHTTPClient()
        beaconSender = BeaconSender(session: session, httpClient: mockHTTPClient)
    }
    
    override func tearDown() async throws {
        session.cleanup()
        session = nil
        mockHTTPClient = nil
        beaconSender = nil
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Creates a test ad pod with a single ad containing the specified tracking events
    private func createTestAdPod(
        podStartTime: Double,
        podDuration: Double,
        adId: String = "test-ad-1",
        adStartTime: Double,
        adDuration: Double,
        trackingEvents: [TrackingEvent]
    ) -> AdBreak {
        let ad = Ad(
            id: adId,
            startTime: adStartTime,
            duration: adDuration,
            trackingEvents: trackingEvents
        )
        
        return AdBreak(
            id: "test-pod-1",
            startTime: podStartTime,
            duration: podDuration,
            ads: [ad]
        )
    }
    
    /// Creates a tracking event for testing
    private func createTrackingEvent(
        eventType: EventType,
        startTime: Double,
        duration: Double = 0,
        signalingUrls: [String],
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
    
    // MARK: - sendUserTriggeredBeacon Tests
    
    func testSendUserTriggeredBeacon_WhenAdIsPlaying_SendsBeaconSuccessfully() async throws {
        // Given: A session with an ad pod containing a pause tracking event
        let currentPlayhead: Double = 5000 // 5 seconds into playback (in milliseconds)
        
        let pauseEvent = createTrackingEvent(
            eventType: .pause,
            startTime: 0,
            duration: 30000,
            signalingUrls: ["https://example.com/beacon/pause"]
        )
        
        let adPod = createTestAdPod(
            podStartTime: 0,
            podDuration: 30000,
            adStartTime: 0,
            adDuration: 30000,
            trackingEvents: [pauseEvent]
        )
        
        session.adPods = [adPod]
        
        // Set the playhead to simulate an ad playing at 5 seconds
        session.playerObserver.setPlayhead(currentPlayhead)
        
        // When: Attempting to send a pause beacon
        let result = await beaconSender.sendUserTriggeredBeacon(eventType: .pause)
        
        // Then: Should return true and send the beacon
        XCTAssertTrue(result, "Should return true when beacon is sent successfully")
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 1, "Should make exactly one HTTP request")
        XCTAssertEqual(
            mockHTTPClient.requestedURLs.first?.absoluteString,
            "https://example.com/beacon/pause",
            "Should send request to the correct URL"
        )
    }
    
    func testSendUserTriggeredBeacon_WhenNoAdIsPlaying_ReturnsFalse() async throws {
        // Given: A session with no ad pods but a valid playhead
        session.adPods = []
        session.playerObserver.setPlayhead(5000) // Set a valid playhead position
        
        // When: Attempting to send a pause beacon
        let result = await beaconSender.sendUserTriggeredBeacon(eventType: .pause)
        
        // Then: Should return false
        XCTAssertFalse(result, "Should return false when no ads are available")
        XCTAssertTrue(mockHTTPClient.requestedURLs.isEmpty, "No HTTP requests should be made")
    }

    /// Test that verifies the beacon sender correctly identifies tracking events by type
    func testSendUserTriggeredBeacon_MatchesCorrectEventType() async throws {
        // Given: A session with multiple tracking events for different event types
        let pauseEvent = createTrackingEvent(
            eventType: .pause,
            startTime: 0,
            duration: 30000,
            signalingUrls: ["https://example.com/beacon/pause"],
            reportingState: .idle
        )
        
        let muteEvent = createTrackingEvent(
            eventType: .mute,
            startTime: 0,
            duration: 30000,
            signalingUrls: ["https://example.com/beacon/mute"],
            reportingState: .idle
        )
        
        let adPod = createTestAdPod(
            podStartTime: 0,
            podDuration: 30000,
            adStartTime: 0,
            adDuration: 30000,
            trackingEvents: [pauseEvent, muteEvent]
        )
        
        session.adPods = [adPod]
        
        // Set playhead to be within the ad
        session.playerObserver.setPlayhead(5000)
        
        // When: Sending a mute beacon
        let result = await beaconSender.sendUserTriggeredBeacon(eventType: .mute)
        
        // Then: Should successfully send the mute beacon
        XCTAssertTrue(result, "Should return true when mute beacon is sent successfully")
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 1, "Should make exactly one HTTP request")
        XCTAssertEqual(
            mockHTTPClient.requestedURLs.first?.absoluteString,
            "https://example.com/beacon/mute",
            "Should send request to the mute URL, not pause URL"
        )
    }
    
    // MARK: - iterateTrackingEvents Tests
    
    func testIterateTrackingEvents_SendsBeaconWhenPlayheadCrossesEventStartTime() async throws {
        // Given: A session with an ad pod containing a start tracking event
        let startEvent = createTrackingEvent(
            eventType: .start,
            startTime: 5000, // Event triggers at 5 seconds
            duration: 0,
            signalingUrls: ["https://example.com/beacon/start"],
            reportingState: .idle
        )
        
        let adPod = createTestAdPod(
            podStartTime: 0,
            podDuration: 30000,
            adStartTime: 0,
            adDuration: 30000,
            trackingEvents: [startEvent]
        )
        
        session.adPods = [adPod]
        
        // When: Playhead moves from 4s to 5.5s (crossing the event start time)
        await beaconSender.iterateTrackingEvents(time0: 4000, time1: 5500)
        
        // Then: Should send the beacon
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 1, "Should send exactly one beacon")
        XCTAssertEqual(
            mockHTTPClient.requestedURLs.first?.absoluteString,
            "https://example.com/beacon/start",
            "Should send request to the start event URL"
        )
        XCTAssertEqual(startEvent.reportingState, .done, "Tracking event should be marked as done")
    }
    
    func testIterateTrackingEvents_DoesNotSendBeaconWhenPlayheadBeforeEventStartTime() async throws {
        // Given: A session with an ad pod containing a start tracking event at 10 seconds
        let startEvent = createTrackingEvent(
            eventType: .start,
            startTime: 10000, // Event triggers at 10 seconds
            duration: 0,
            signalingUrls: ["https://example.com/beacon/start"],
            reportingState: .idle
        )
        
        let adPod = createTestAdPod(
            podStartTime: 0,
            podDuration: 30000,
            adStartTime: 0,
            adDuration: 30000,
            trackingEvents: [startEvent]
        )
        
        session.adPods = [adPod]
        
        // When: Playhead is before the event start time (moving from 2s to 3s)
        await beaconSender.iterateTrackingEvents(time0: 2000, time1: 3000)
        
        // Then: Should not send any beacon
        XCTAssertTrue(mockHTTPClient.requestedURLs.isEmpty, "Should not send any beacons when playhead is before event start")
        XCTAssertEqual(startEvent.reportingState, .idle, "Tracking event should remain idle")
    }
    
    func testIterateTrackingEvents_DoesNotResendAlreadySentBeacon() async throws {
        // Given: A session with a tracking event that has already been sent
        let startEvent = createTrackingEvent(
            eventType: .start,
            startTime: 5000,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/start"],
            reportingState: .done // Already sent
        )
        
        let adPod = createTestAdPod(
            podStartTime: 0,
            podDuration: 30000,
            adStartTime: 0,
            adDuration: 30000,
            trackingEvents: [startEvent]
        )
        
        session.adPods = [adPod]
        
        // When: Playhead crosses the event start time
        await beaconSender.iterateTrackingEvents(time0: 4000, time1: 6000)
        
        // Then: Should not resend the beacon
        XCTAssertTrue(mockHTTPClient.requestedURLs.isEmpty, "Should not resend already completed beacons")
        XCTAssertEqual(startEvent.reportingState, .done, "Reporting state should remain done")
    }
    
    func testIterateTrackingEvents_SendsMultipleBeaconsInTimeRange() async throws {
        // Given: A session with multiple tracking events in the same time range
        let startEvent = createTrackingEvent(
            eventType: .start,
            startTime: 0,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/start"],
            reportingState: .idle
        )
        
        let impressionEvent = createTrackingEvent(
            eventType: .impression,
            startTime: 0,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/impression"],
            reportingState: .idle
        )
        
        let adPod = createTestAdPod(
            podStartTime: 0,
            podDuration: 30000,
            adStartTime: 0,
            adDuration: 30000,
            trackingEvents: [startEvent, impressionEvent]
        )
        
        session.adPods = [adPod]
        
        // When: Playhead crosses both event start times
        await beaconSender.iterateTrackingEvents(time0: -1000, time1: 500)
        
        // Then: Should send both beacons
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 2, "Should send two beacons")
        
        let requestedURLStrings = Set(mockHTTPClient.requestedURLs.map { $0.absoluteString })
        XCTAssertTrue(requestedURLStrings.contains("https://example.com/beacon/start"), "Should send start beacon")
        XCTAssertTrue(requestedURLStrings.contains("https://example.com/beacon/impression"), "Should send impression beacon")
        
        XCTAssertEqual(startEvent.reportingState, .done, "Start event should be marked as done")
        XCTAssertEqual(impressionEvent.reportingState, .done, "Impression event should be marked as done")
    }
    
    func testIterateTrackingEvents_SkipsPlayerInitiatedEvents() async throws {
        // Given: A session with player-initiated events (pause, mute)
        let pauseEvent = createTrackingEvent(
            eventType: .pause,
            startTime: 5000,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/pause"],
            reportingState: .idle
        )
        
        let muteEvent = createTrackingEvent(
            eventType: .mute,
            startTime: 5000,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/mute"],
            reportingState: .idle
        )
        
        let startEvent = createTrackingEvent(
            eventType: .start,
            startTime: 5000,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/start"],
            reportingState: .idle
        )
        
        let adPod = createTestAdPod(
            podStartTime: 0,
            podDuration: 30000,
            adStartTime: 0,
            adDuration: 30000,
            trackingEvents: [pauseEvent, muteEvent, startEvent]
        )
        
        session.adPods = [adPod]
        
        // When: Playhead crosses the event start time
        await beaconSender.iterateTrackingEvents(time0: 4000, time1: 6000)
        
        // Then: Should only send the start beacon, not pause or mute
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 1, "Should send only one beacon")
        XCTAssertEqual(
            mockHTTPClient.requestedURLs.first?.absoluteString,
            "https://example.com/beacon/start",
            "Should only send the start event, not player-initiated events"
        )
        XCTAssertEqual(pauseEvent.reportingState, .idle, "Pause event should remain idle")
        XCTAssertEqual(muteEvent.reportingState, .idle, "Mute event should remain idle")
        XCTAssertEqual(startEvent.reportingState, .done, "Start event should be marked as done")
    }
    
    func testIterateTrackingEvents_SendsQuartileEventsAtCorrectTimes() async throws {
        // Given: A 30-second ad with all quartile events
        let adDuration: Double = 30000 // 30 seconds in milliseconds
        
        let firstQuartileEvent = createTrackingEvent(
            eventType: .firstQuartile,
            startTime: 7500, // 25% of 30 seconds
            duration: 0,
            signalingUrls: ["https://example.com/beacon/firstQuartile"],
            reportingState: .idle
        )
        
        let midpointEvent = createTrackingEvent(
            eventType: .midpoint,
            startTime: 15000, // 50% of 30 seconds
            duration: 0,
            signalingUrls: ["https://example.com/beacon/midpoint"],
            reportingState: .idle
        )
        
        let thirdQuartileEvent = createTrackingEvent(
            eventType: .thirdQuartile,
            startTime: 22500, // 75% of 30 seconds
            duration: 0,
            signalingUrls: ["https://example.com/beacon/thirdQuartile"],
            reportingState: .idle
        )
        
        let adPod = createTestAdPod(
            podStartTime: 0,
            podDuration: adDuration,
            adStartTime: 0,
            adDuration: adDuration,
            trackingEvents: [firstQuartileEvent, midpointEvent, thirdQuartileEvent]
        )
        
        session.adPods = [adPod]
        
        // When: Playhead crosses the first quartile time
        await beaconSender.iterateTrackingEvents(time0: 7000, time1: 8000)
        
        // Then: Should send only the first quartile beacon
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 1, "Should send exactly one beacon")
        XCTAssertEqual(
            mockHTTPClient.requestedURLs.first?.absoluteString,
            "https://example.com/beacon/firstQuartile",
            "Should send the first quartile beacon"
        )
        XCTAssertEqual(firstQuartileEvent.reportingState, .done, "First quartile should be done")
        XCTAssertEqual(midpointEvent.reportingState, .idle, "Midpoint should still be idle")
        XCTAssertEqual(thirdQuartileEvent.reportingState, .idle, "Third quartile should still be idle")
        
        // Reset for next check
        mockHTTPClient.reset()
        
        // When: Playhead crosses the midpoint
        await beaconSender.iterateTrackingEvents(time0: 14500, time1: 15500)
        
        // Then: Should send the midpoint beacon
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 1, "Should send exactly one beacon")
        XCTAssertEqual(
            mockHTTPClient.requestedURLs.first?.absoluteString,
            "https://example.com/beacon/midpoint",
            "Should send the midpoint beacon"
        )
        XCTAssertEqual(midpointEvent.reportingState, .done, "Midpoint should now be done")
    }
    
    func testIterateTrackingEvents_HandlesMultipleAdsInPod() async throws {
        // Given: A pod with two consecutive ads
        let ad1StartEvent = createTrackingEvent(
            eventType: .start,
            startTime: 0,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/ad1/start"],
            reportingState: .idle
        )
        
        let ad1 = Ad(
            id: "ad-1",
            startTime: 0,
            duration: 15000,
            trackingEvents: [ad1StartEvent]
        )
        
        let ad2StartEvent = createTrackingEvent(
            eventType: .start,
            startTime: 15000,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/ad2/start"],
            reportingState: .idle
        )
        
        let ad2 = Ad(
            id: "ad-2",
            startTime: 15000,
            duration: 15000,
            trackingEvents: [ad2StartEvent]
        )
        
        let adPod = AdBreak(
            id: "test-pod",
            startTime: 0,
            duration: 30000,
            ads: [ad1, ad2]
        )
        
        session.adPods = [adPod]
        
        // When: Playhead crosses the first ad start time
        await beaconSender.iterateTrackingEvents(time0: -500, time1: 500)
        
        // Then: Should send only the first ad's start beacon
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 1, "Should send exactly one beacon")
        XCTAssertEqual(
            mockHTTPClient.requestedURLs.first?.absoluteString,
            "https://example.com/beacon/ad1/start",
            "Should send ad1's start beacon"
        )
        
        mockHTTPClient.reset()
        
        // When: Playhead crosses the second ad start time
        await beaconSender.iterateTrackingEvents(time0: 14500, time1: 15500)
        
        // Then: Should send the second ad's start beacon
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 1, "Should send exactly one beacon")
        XCTAssertEqual(
            mockHTTPClient.requestedURLs.first?.absoluteString,
            "https://example.com/beacon/ad2/start",
            "Should send ad2's start beacon"
        )
    }
    
    func testIterateTrackingEvents_HTTPFailureMarksEventAsFailed() async throws {
        // Given: A session with a tracking event and a failing HTTP client
        let startEvent = createTrackingEvent(
            eventType: .start,
            startTime: 5000,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/start"],
            reportingState: .idle
        )
        
        let adPod = createTestAdPod(
            podStartTime: 0,
            podDuration: 30000,
            adStartTime: 0,
            adDuration: 30000,
            trackingEvents: [startEvent]
        )
        
        session.adPods = [adPod]
        mockHTTPClient.shouldThrowError = true
        
        // When: Playhead crosses the event start time
        await beaconSender.iterateTrackingEvents(time0: 4000, time1: 6000)
        
        // Then: Should attempt to send the beacon and mark as failed
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 1, "Should attempt to send the beacon")
        XCTAssertEqual(startEvent.reportingState, .failed, "Tracking event should be marked as failed")
    }
    
    func testIterateTrackingEvents_NonSuccessStatusCodeMarksEventAsFailed() async throws {
        // Given: A session with a tracking event and HTTP client returning 500
        let startEvent = createTrackingEvent(
            eventType: .start,
            startTime: 5000,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/start"],
            reportingState: .idle
        )
        
        let adPod = createTestAdPod(
            podStartTime: 0,
            podDuration: 30000,
            adStartTime: 0,
            adDuration: 30000,
            trackingEvents: [startEvent]
        )
        
        session.adPods = [adPod]
        mockHTTPClient.mockStatusCode = 500
        
        // When: Playhead crosses the event start time
        await beaconSender.iterateTrackingEvents(time0: 4000, time1: 6000)
        
        // Then: Should mark the event as failed due to non-2xx status
        XCTAssertEqual(mockHTTPClient.requestedURLs.count, 1, "Should attempt to send the beacon")
        XCTAssertEqual(startEvent.reportingState, .failed, "Tracking event should be marked as failed for non-2xx status")
    }
    
    func testIterateTrackingEvents_PlayheadOutsideAdPodDoesNotSendBeacons() async throws {
        // Given: A session with an ad pod that starts at 30 seconds
        let startEvent = createTrackingEvent(
            eventType: .start,
            startTime: 30000,
            duration: 0,
            signalingUrls: ["https://example.com/beacon/start"],
            reportingState: .idle
        )
        
        let adPod = createTestAdPod(
            podStartTime: 30000, // Pod starts at 30 seconds
            podDuration: 30000,
            adStartTime: 30000,
            adDuration: 30000,
            trackingEvents: [startEvent]
        )
        
        session.adPods = [adPod]
        
        // When: Playhead is before the ad pod (0-5 seconds)
        await beaconSender.iterateTrackingEvents(time0: 0, time1: 5000)
        
        // Then: Should not send any beacons
        XCTAssertTrue(mockHTTPClient.requestedURLs.isEmpty, "Should not send beacons when playhead is outside ad pod")
        XCTAssertEqual(startEvent.reportingState, .idle, "Tracking event should remain idle")
    }
}
