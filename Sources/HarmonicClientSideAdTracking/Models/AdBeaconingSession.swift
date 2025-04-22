//
//  AdBeaconingSession.swift
//  
//
//  Created by Michael on 19/1/2023.
//

import AVFoundation
import Combine
import os

@MainActor
public class AdBeaconingSession: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AdBeaconingSession.self)
    )
    
    public var player = AVPlayer() {
        didSet {
            playerObserver.setSession(self)
        }
    }
    public let playerObserver = PlayerObserver()
    
    public var mediaUrl: String = "" {
        didSet {
            guard !mediaUrl.isEmpty else { return }
            Task {
                var manifestUrl, adTrackingMetadataUrl: String

                if isInitRequest {
                    do {
                        let initResponse = try await Utility.makeInitRequest(to: mediaUrl)
                        Utility.log("Parsed URLs from POST init request: \(initResponse.manifestUrl), \(initResponse.trackingUrl)",
                                    to: self, level: .info, with: Self.logger)
                        sessionInfo = SessionInfo(localSessionId: Date().ISO8601Format(),
                                                  mediaUrl: mediaUrl,
                                                  manifestUrl: initResponse.manifestUrl,
                                                  adTrackingMetadataUrl: initResponse.trackingUrl)
                    } catch {
                        Utility
                            .log(
                                "Failed to make POST request to \(mediaUrl) to initialise the session: \(error.localizedDescription)."
                                + "Falling back to GET request.",
                                to: self, level: .warning, with: Self.logger
                            )
                    }
                }
                
                if sessionInfo.manifestUrl.isEmpty || sessionInfo.adTrackingMetadataUrl.isEmpty {
                    do {
                        let (_, httpResponse) = try await Utility.makeRequest(to: mediaUrl)
                        
                        if let redirectedUrl = httpResponse.url {
                            manifestUrl = redirectedUrl.absoluteString
                            adTrackingMetadataUrl = Utility.rewriteToMetadataUrl(from: redirectedUrl.absoluteString)
                        } else {
                            manifestUrl = mediaUrl
                            adTrackingMetadataUrl = Utility.rewriteToMetadataUrl(from: mediaUrl)
                        }
                        
                        sessionInfo = SessionInfo(localSessionId: Date().ISO8601Format(),
                                                  mediaUrl: mediaUrl,
                                                  manifestUrl: manifestUrl,
                                                  adTrackingMetadataUrl: adTrackingMetadataUrl)
                    } catch {
                        Utility.log("Failed to load media with URL: \(mediaUrl); Error: \(error)",
                                    to: self, level: .warning, with: Self.logger)
                    }
                }
            }
        }
    }
    
    @Published public internal(set) var sessionInfo = SessionInfo()
    @Published public internal(set) var adPods: [AdBreak] = []
    @Published public internal(set) var latestDataRange: DataRange?
    @Published public internal(set) var playedTimeOutsideDataRange: [DataRange] = []
    @Published public internal(set) var logMessages: [LogMessage] = []
    
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
    @Published public var metadataType: MetadataType = .latestOnly {
        didSet {
            reload(with: sessionInfo.manifestUrl,
                   isAutomaticallyPreservesTimeOffsetFromLive: automaticallyPreservesTimeOffsetFromLive)
        }
    }
    
    var latestPlayhead: Double = 0
    
    public init() {
        self.playerObserver.setSession(self)
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
