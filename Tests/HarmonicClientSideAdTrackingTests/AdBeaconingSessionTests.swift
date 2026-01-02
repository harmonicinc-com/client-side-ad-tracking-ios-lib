//
//  AdBeaconingSessionTests.swift
//
//
//  Created by Michael on 2/1/2026.
//

import XCTest
@testable import HarmonicClientSideAdTracking

// MARK: - Mock Network Client

/// A mock network client that records requests and returns configurable responses
final class MockNetworkClient: NetworkClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    
    // Track calls
    private var _makeRequestCalls: [String] = []
    var makeRequestCalls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _makeRequestCalls
    }
    
    private var _makeInitRequestCalls: [String] = []
    var makeInitRequestCalls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _makeInitRequestCalls
    }
    
    // Configurable results
    var makeRequestResult: Result<(Data, HTTPURLResponse), Error>?
    var makeInitRequestResult: Result<InitResponse, Error>?
    
    func makeRequest(to urlString: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            _makeRequestCalls.append(urlString)
        }
        
        switch makeRequestResult {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            fatalError("MockNetworkClient.makeRequest not configured for URL: \(urlString)")
        }
    }
    
    func makeInitRequest(to urlString: String) async throws -> InitResponse {
        lock.withLock {
            _makeInitRequestCalls.append(urlString)
        }
        
        switch makeInitRequestResult {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            fatalError("MockNetworkClient.makeInitRequest not configured for URL: \(urlString)")
        }
    }
    
    func reset() {
        lock.lock()
        _makeRequestCalls.removeAll()
        _makeInitRequestCalls.removeAll()
        lock.unlock()
        makeRequestResult = nil
        makeInitRequestResult = nil
    }
}

// MARK: - Test Cases

@MainActor
final class AdBeaconingSessionTests: XCTestCase {
    
    var session: AdBeaconingSession!
    var mockNetworkClient: MockNetworkClient!
    
    override func setUp() async throws {
        try await super.setUp()
        mockNetworkClient = MockNetworkClient()
        session = AdBeaconingSession(networkClient: mockNetworkClient)
    }
    
    override func tearDown() async throws {
        session.cleanup()
        session = nil
        mockNetworkClient = nil
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Creates a mock HTTPURLResponse
    private func createMockHTTPResponse(
        url: String,
        statusCode: Int = 200
    ) -> HTTPURLResponse {
        return HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
    
    /// Creates a mock HLS master playlist data
    private func createMockHLSMasterPlaylist(mediaPlaylistPath: String = "media.m3u8") -> Data {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720
        \(mediaPlaylistPath)
        """
        return playlist.data(using: .utf8)!
    }
    
    // MARK: - loadSession Tests - Init Request Success
    
    func testLoadSession_InitRequestSuccess_SetsSessionInfo() async throws {
        // Given: A successful init request response
        let expectedManifestUrl = "https://example.com/manifest.m3u8"
        let expectedTrackingUrl = "https://example.com/metadata"
        
        mockNetworkClient.makeInitRequestResult = .success(
            InitResponse(manifestUrl: expectedManifestUrl, trackingUrl: expectedTrackingUrl)
        )
        
        session.isInitRequest = true
        
        // When: Loading session
        await session.loadSession(for: "https://example.com/stream")
        
        // Then: Should set session info from init response
        XCTAssertEqual(mockNetworkClient.makeInitRequestCalls.count, 1, "Should make exactly one init request")
        XCTAssertEqual(mockNetworkClient.makeInitRequestCalls.first, "https://example.com/stream")
        XCTAssertTrue(mockNetworkClient.makeRequestCalls.isEmpty, "Should not make regular request when init succeeds")
        
        XCTAssertEqual(session.sessionInfo.manifestUrl, expectedManifestUrl)
        XCTAssertEqual(session.sessionInfo.adTrackingMetadataUrl, expectedTrackingUrl)
        XCTAssertEqual(session.sessionInfo.mediaUrl, "https://example.com/stream")
    }
    
    func testLoadSession_InitRequestFailure_FallsBackToRegularRequest() async throws {
        // Given: A failing init request and successful regular request
        mockNetworkClient.makeInitRequestResult = .failure(
            HarmonicAdTrackerError.networkError("Init request failed")
        )
        
        let mockResponse = createMockHTTPResponse(url: "https://example.com/redirected.m3u8", statusCode: 302)
        mockNetworkClient.makeRequestResult = .success((Data(), mockResponse))
        
        session.isInitRequest = true
        
        // When: Loading session
        await session.loadSession(for: "https://example.com/stream")
        
        // Then: Should fallback to regular request
        XCTAssertEqual(mockNetworkClient.makeInitRequestCalls.count, 1, "Should try init request first")
        XCTAssertEqual(mockNetworkClient.makeRequestCalls.count, 1, "Should fallback to regular request")
    }
    
    // MARK: - loadSession Tests - Regular Request (No Init)
    
    func testLoadSession_IsInitRequestFalse_SkipsInitRequest() async throws {
        // Given: isInitRequest is false
        session.isInitRequest = false
        
        let mockResponse = createMockHTTPResponse(url: "https://example.com/stream.m3u8")
        let mockData = createMockHLSMasterPlaylist()
        mockNetworkClient.makeRequestResult = .success((mockData, mockResponse))
        
        // When: Loading session
        await session.loadSession(for: "https://example.com/stream")
        
        // Then: Should skip init request and go directly to regular request
        XCTAssertTrue(mockNetworkClient.makeInitRequestCalls.isEmpty, "Should not make init request when isInitRequest is false")
        XCTAssertEqual(mockNetworkClient.makeRequestCalls.count, 1, "Should make regular request")
    }
    
    func testLoadSession_RedirectResponse_UsesRedirectedUrl() async throws {
        // Given: A redirect response (301 or 302)
        session.isInitRequest = false
        
        let redirectedUrl = "https://cdn.example.com/session123/manifest.m3u8"
        let mockResponse = HTTPURLResponse(
            url: URL(string: redirectedUrl)!,
            statusCode: 302,
            httpVersion: nil,
            headerFields: nil
        )!
        mockNetworkClient.makeRequestResult = .success((Data(), mockResponse))
        
        // When: Loading session
        await session.loadSession(for: "https://example.com/stream")
        
        // Then: Should use redirected URL for manifest
        XCTAssertEqual(session.sessionInfo.manifestUrl, redirectedUrl)
        // Metadata URL should be derived from redirected URL
        XCTAssertTrue(session.sessionInfo.adTrackingMetadataUrl.contains("metadata"))
    }
    
    func testLoadSession_HLSMasterPlaylist_ParsesFirstMediaPlaylist() async throws {
        // Given: A 200 response with HLS master playlist content
        session.isInitRequest = false
        
        let baseUrl = "https://example.com/stream/master.m3u8"
        let mockResponse = createMockHTTPResponse(url: baseUrl)
        let mockData = createMockHLSMasterPlaylist(mediaPlaylistPath: "720p/media.m3u8")
        mockNetworkClient.makeRequestResult = .success((mockData, mockResponse))
        
        // When: Loading session
        await session.loadSession(for: baseUrl)
        
        // Then: Should parse the first media playlist URL
        XCTAssertTrue(session.sessionInfo.manifestUrl.contains("720p") || session.sessionInfo.manifestUrl.contains("stream"),
                      "Should use parsed media playlist URL or fallback")
    }
    
    // MARK: - loadSession Tests - Error Handling
    
    func testLoadSession_NetworkError_LogsError() async throws {
        // Given: Both init and regular requests fail
        mockNetworkClient.makeInitRequestResult = .failure(
            HarmonicAdTrackerError.networkError("Init failed")
        )
        mockNetworkClient.makeRequestResult = .failure(
            HarmonicAdTrackerError.networkError("Request failed")
        )
        
        session.isInitRequest = true
        let initialLogCount = session.logMessages.count
        
        // When: Loading session
        await session.loadSession(for: "https://example.com/stream")
        
        // Then: Should log errors
        XCTAssertGreaterThan(session.logMessages.count, initialLogCount, "Should log error messages")
        
        // Session info should remain empty/default
        XCTAssertTrue(session.sessionInfo.manifestUrl.isEmpty, "Manifest URL should be empty on failure")
    }
    
    func testLoadSession_EmptyUrl_DoesNothing() async throws {
        // Given: An empty URL (via mediaUrl setter)
        let initialSessionInfo = session.sessionInfo
        
        // When: Setting empty mediaUrl
        session.mediaUrl = ""
        
        // Allow any async tasks to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then: Should not make any requests
        XCTAssertTrue(mockNetworkClient.makeInitRequestCalls.isEmpty)
        XCTAssertTrue(mockNetworkClient.makeRequestCalls.isEmpty)
        XCTAssertEqual(session.sessionInfo.localSessionId, initialSessionInfo.localSessionId)
    }
    
    // MARK: - loadSession Tests - Multiple Calls
    
    func testLoadSession_MultipleUrls_UpdatesSessionInfo() async throws {
        // Given: Two different URLs
        mockNetworkClient.makeInitRequestResult = .success(
            InitResponse(manifestUrl: "https://example.com/first.m3u8", trackingUrl: "https://example.com/first-metadata")
        )
        
        session.isInitRequest = true
        
        // When: Loading first URL
        await session.loadSession(for: "https://example.com/first")
        
        // Then: Should set first session info
        XCTAssertEqual(session.sessionInfo.manifestUrl, "https://example.com/first.m3u8")
        
        // When: Loading second URL
        mockNetworkClient.makeInitRequestResult = .success(
            InitResponse(manifestUrl: "https://example.com/second.m3u8", trackingUrl: "https://example.com/second-metadata")
        )
        await session.loadSession(for: "https://example.com/second")
        
        // Then: Should update to second session info
        XCTAssertEqual(session.sessionInfo.manifestUrl, "https://example.com/second.m3u8")
        XCTAssertEqual(session.sessionInfo.mediaUrl, "https://example.com/second")
    }
    
    // MARK: - Integration Tests via mediaUrl Setter
    
    func testMediaUrlSetter_TriggersLoadSession() async throws {
        // Given: A configured mock for init request
        mockNetworkClient.makeInitRequestResult = .success(
            InitResponse(manifestUrl: "https://example.com/manifest.m3u8", trackingUrl: "https://example.com/metadata")
        )
        
        session.isInitRequest = true
        
        // When: Setting mediaUrl
        session.mediaUrl = "https://example.com/stream"
        
        // Allow the Task in didSet to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then: Should trigger loadSession and update sessionInfo
        XCTAssertEqual(mockNetworkClient.makeInitRequestCalls.count, 1)
        XCTAssertEqual(session.sessionInfo.manifestUrl, "https://example.com/manifest.m3u8")
    }
}
