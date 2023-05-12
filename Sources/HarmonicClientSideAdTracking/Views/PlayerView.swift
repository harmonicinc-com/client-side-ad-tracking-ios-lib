//
//  PlayerView.swift
//
//
//  Created by Michael on 19/1/2023.
//

import SwiftUI
import AVKit
import os

public struct PlayerView: View {
    private static let logger = Logger(
        subsystem: Bundle.module.bundleIdentifier!,
        category: String(describing: PlayerView.self)
    )
    
    @ObservedObject private var session: AdBeaconingSession
    
    public init(session: AdBeaconingSession) {
        self.session = session
    }
        
    public var body: some View {
        VStack {
            VideoPlayer(player: session.player, videoOverlay: {
                if session.isShowDebugOverlay {
                    VideoOverlayView(playerObserver: session.playerObserver)
                }
            })
#if os(iOS)
            .aspectRatio(CGSize(width: 16, height: 9), contentMode: .fit)
#else
            .frame(height: 360)
#endif
            .onReceive(session.$sessionInfo) { info in
                load(with: info.manifestUrl, isAutomaticallyPreservesTimeOffsetFromLive: session.automaticallyPreservesTimeOffsetFromLive)
            }
            .onReceive(session.$automaticallyPreservesTimeOffsetFromLive, perform: { enabled in
                reload(with: session.sessionInfo.manifestUrl, isAutomaticallyPreservesTimeOffsetFromLive: enabled)
            })
        }
    }
}

extension PlayerView {
    private func load(with urlString: String, isAutomaticallyPreservesTimeOffsetFromLive: Bool) {
        guard session.player.timeControlStatus != .playing else { return }

        let interstitialController = AVPlayerInterstitialEventMonitor(primaryPlayer: session.player)
        let interstitialPlayer = interstitialController.interstitialPlayer
        let interstitialStatus = interstitialPlayer.timeControlStatus
        if interstitialStatus == .playing {
            interstitialPlayer.play()
            return
        }
        
        reload(with: urlString, isAutomaticallyPreservesTimeOffsetFromLive: isAutomaticallyPreservesTimeOffsetFromLive)
    }
    
    private func reload(with urlString: String, isAutomaticallyPreservesTimeOffsetFromLive: Bool) {
        guard let url = URL(string: urlString) else { return }
        
        let interstitialController = AVPlayerInterstitialEventController(primaryPlayer: session.player)
        interstitialController.cancelCurrentEvent(withResumptionOffset: .zero)
        
        session.player.pause()
        
        let playerItem = AVPlayerItem(url: url)
        playerItem.automaticallyPreservesTimeOffsetFromLive = isAutomaticallyPreservesTimeOffsetFromLive
        
        // HMS-10699: Set a new player instead of using replaceCurrentItem(with:)
        session.player = AVPlayer(playerItem: playerItem)
        session.playerObserver.setPlayer(session.player)
        
        session.player.play()
    }
}

struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView(session: AdBeaconingSession())
    }
}
