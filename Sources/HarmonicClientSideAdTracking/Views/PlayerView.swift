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
        subsystem: Bundle.main.bundleIdentifier!,
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
                if !info.manifestUrl.isEmpty && session.player.timeControlStatus != .playing {
                    guard let url = URL(string: info.manifestUrl) else {
                        Utility.log("Cannot load manifest URL: \(info.manifestUrl)",
                                    to: session, level: .warning, with: Self.logger)
                        return
                    }
                    let playerItem = AVPlayerItem(url: url)
                    playerItem.automaticallyPreservesTimeOffsetFromLive = session.automaticallyPreservesTimeOffsetFromLive
                    session.player.replaceCurrentItem(with: playerItem)
                    session.player.play()
                }
            }
            .onReceive(session.$automaticallyPreservesTimeOffsetFromLive, perform: { enabled in
                reload(with: session.sessionInfo.manifestUrl, isAutomaticallyPreservesTimeOffsetFromLive: enabled)
            })
        }
    }
}

extension PlayerView {
    private func reload(with urlString: String, isAutomaticallyPreservesTimeOffsetFromLive: Bool) {
        guard let url = URL(string: urlString) else { return }
        
        let interstitialController = AVPlayerInterstitialEventController(primaryPlayer: session.player)
        interstitialController.cancelCurrentEvent(withResumptionOffset: .zero)
        
        session.player.pause()
        
        let playerItem = AVPlayerItem(url: url)
        playerItem.automaticallyPreservesTimeOffsetFromLive = isAutomaticallyPreservesTimeOffsetFromLive
        
        // HMS-10699: Set a new player instead of using replaceCurrentItem(with:)
        session.player = AVPlayer(playerItem: playerItem)
        session.player.play()
    }
}

struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView(session: AdBeaconingSession())
    }
}
