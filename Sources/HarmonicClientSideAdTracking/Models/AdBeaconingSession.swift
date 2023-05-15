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

                    let interstitialPlayer = AVPlayerInterstitialEventMonitor(primaryPlayer: player).interstitialPlayer
                    if player.rate == 0 && interstitialPlayer.rate == 0 {
                        let newPlayerItem = AVPlayerItem(url: URL(string: manifestUrl)!)
                        newPlayerItem.automaticallyPreservesTimeOffsetFromLive = automaticallyPreservesTimeOffsetFromLive
                        player.replaceCurrentItem(with: newPlayerItem)
                    }
                } catch {
                    Utility.log("Failed to load media with URL: \(mediaUrl); Error: \(error)",
                                to: self, level: .warning, with: Self.logger)                    
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
    @Published public internal(set) var automaticallyPreservesTimeOffsetFromLive = false
    @Published public var playerControlIsFocused = false
    
    var latestPlayhead: Double = 0
    
    public init() {
        self.playerObserver.setSession(self)
    }
    
}
