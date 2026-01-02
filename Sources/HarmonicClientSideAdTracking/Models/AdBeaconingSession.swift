//
//  AdBeaconingSession.swift
//  
//
//  Created by Michael on 19/1/2023.
//

import AVFoundation
import Combine
import os

private let METADATA_UPDATE_INTERVAL: TimeInterval = 4

@MainActor
public class AdBeaconingSession: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AdBeaconingSession.self)
    )
    
    /// The network client used for making HTTP requests. Can be injected for testing.
    let networkClient: NetworkClientProtocol
    
    public var player = AVPlayer() {
        willSet {
            // Clean up observations on the old player before setting new one
            Task { @MainActor in
                playerObserver.resetObservations()
            }
        }
        didSet {
            playerObserver.setSession(self)
        }
    }
    public let playerObserver = PlayerObserver()
    
    public var mediaUrl: String = "" {
        didSet {
            guard !mediaUrl.isEmpty else { return }
            Task {
                await loadSession(for: mediaUrl)
            }
        }
    }
    
    /// Loads session information for the given media URL.
    /// This method is internal to allow testing.
    func loadSession(for urlString: String) async {
        var manifestUrl, adTrackingMetadataUrl: String

        var isInitRequestSucceeded = false
        if isInitRequest {
            do {
                let initResponse = try await networkClient.makeInitRequest(to: urlString)
                Utility.log("Parsed URLs from session init request: \(initResponse.manifestUrl), \(initResponse.trackingUrl)",
                            to: self, level: .info, with: Self.logger)
                sessionInfo = SessionInfo(localSessionId: Date().ISO8601Format(),
                                          mediaUrl: urlString,
                                          manifestUrl: initResponse.manifestUrl,
                                          adTrackingMetadataUrl: initResponse.trackingUrl)
                isInitRequestSucceeded = true
            } catch let trackerError as HarmonicAdTrackerError {
                Utility
                    .log(
                        "Failed to make request to \(urlString) to initialise the session: \(trackerError)."
                        + "Falling back to redirect/parsing manifest.",
                        to: self, level: .warning, with: Self.logger, error: trackerError
                    )
            } catch {
                let trackerError = HarmonicAdTrackerError.networkError("Failed to initialise session: \(error.localizedDescription)")
                Utility
                    .log(
                        "Failed to make request to \(urlString) to initialise the session: \(error.localizedDescription)."
                        + "Falling back to redirect/parsing manifest.",
                        to: self, level: .warning, with: Self.logger, error: trackerError
                    )
            }
        }
        
        if !isInitRequest || (isInitRequest && !isInitRequestSucceeded) {
            do {
                let (data, httpResponse) = try await networkClient.makeRequest(to: urlString)
                
                let redirectStatusCodes = [301, 302]
                if let redirectedUrl = httpResponse.url, redirectStatusCodes.contains(httpResponse.statusCode) {
                    manifestUrl = redirectedUrl.absoluteString
                    adTrackingMetadataUrl = Utility.rewriteToMetadataUrl(from: redirectedUrl.absoluteString)
                } else {
                    // No redirect occurred, parse the HLS master playlist
                    guard let originalUrl = URL(string: urlString) else {
                        manifestUrl = urlString
                        adTrackingMetadataUrl = Utility.rewriteToMetadataUrl(from: urlString)
                        Utility.log("Failed to create URL from mediaUrl: \(urlString)", 
                                   to: self, level: .warning, with: Self.logger)
                        return
                    }
                    
                    if let firstMediaPlaylistUrl = Utility.parseHLSMasterPlaylist(data, baseURL: originalUrl) {
                        manifestUrl = firstMediaPlaylistUrl
                        adTrackingMetadataUrl = Utility.rewriteToMetadataUrl(from: firstMediaPlaylistUrl)
                        Utility.log("Parsed first media playlist URL from HLS master: \(firstMediaPlaylistUrl)", 
                                   to: self, level: .info, with: Self.logger)
                    } else {
                        // Fallback to original URL if parsing fails
                        manifestUrl = urlString
                        adTrackingMetadataUrl = Utility.rewriteToMetadataUrl(from: urlString)
                        Utility.log("Failed to parse HLS master playlist, using original URL: \(urlString)", 
                                   to: self, level: .warning, with: Self.logger)
                    }
                }
                
                sessionInfo = SessionInfo(localSessionId: Date().ISO8601Format(),
                                          mediaUrl: urlString,
                                          manifestUrl: manifestUrl,
                                          adTrackingMetadataUrl: adTrackingMetadataUrl)
            } catch let trackerError as HarmonicAdTrackerError {
                Utility.log("Failed to load media with URL: \(urlString); Error: \(trackerError)",
                            to: self, level: .warning, with: Self.logger, error: trackerError)
            } catch {
                let trackerError = HarmonicAdTrackerError.networkError("Failed to load media: \(error.localizedDescription)")
                Utility.log("Failed to load media with URL: \(urlString); Error: \(error)",
                            to: self, level: .warning, with: Self.logger, error: trackerError)
            }
        }
    }
    
    @Published public internal(set) var sessionInfo = SessionInfo()
    @Published public internal(set) var adPods: [AdBreak] = []
    @Published public internal(set) var latestDataRange: DataRange?
    @Published public internal(set) var playedTimeOutsideDataRange: [DataRange] = []
    @Published public internal(set) var logMessages: [LogMessage] = []
    @Published public internal(set) var latestError: HarmonicAdTrackerError?
    
    @Published public internal(set) var isShowDebugOverlay = true
    @Published public var isInitRequest: Bool = true {
        didSet {
            // Trigger reload using either POST or GET to init session
            let oldMediaUrl = mediaUrl
            mediaUrl = oldMediaUrl
        }
    }
    @Published public var automaticallyPreservesTimeOffsetFromLive = false
    @Published public var playerControlIsFocused = false
    @Published public var metadataType: MetadataType = .latestOnly // Setting is deprecated
    @Published public var keepPodsForMs: Double =  1_000 * 60 * 60 * 2   // 2 hours
    @Published public var metadataUpdateInterval: TimeInterval = 4 // 4 seconds
    
    var latestPlayhead: Double = 0
    
    public init(networkClient: NetworkClientProtocol = URLSessionNetworkClient()) {
        self.networkClient = networkClient
        self.playerObserver.setSession(self)
    }
    
    deinit {
        // Clean up player observations to prevent memory leaks
        // Note: resetObservations will be called asynchronously but the cleanup will happen
        let playerObserver = self.playerObserver
        let player = self.player
        Task { @MainActor in
            playerObserver.resetObservations()
            
            // Clear the player's current item
            player.replaceCurrentItem(with: nil)
        }
    }
    
    /// Call this method before setting the session to nil for immediate cleanup
    public func cleanup() {
        playerObserver.resetObservations()
        player.replaceCurrentItem(with: nil)
    }
    
    public func reload(with urlString: String, isAutomaticallyPreservesTimeOffsetFromLive: Bool) {
        guard let url = URL(string: urlString) else { return }
        
        let interstitialController = AVPlayerInterstitialEventController(primaryPlayer: player)
        interstitialController.cancelCurrentEvent(withResumptionOffset: .zero)
        
        let playerItem = AVPlayerItem(url: url)
        playerItem.automaticallyPreservesTimeOffsetFromLive = isAutomaticallyPreservesTimeOffsetFromLive
        player.replaceCurrentItem(with: playerItem)
    }
    
}
