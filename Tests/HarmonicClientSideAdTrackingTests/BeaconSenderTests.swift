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
}
