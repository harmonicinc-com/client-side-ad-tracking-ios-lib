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
    
    @EnvironmentObject
    private var playerObserver: PlayerObserver
    
    @EnvironmentObject
    private var adTracker: HarmonicAdTracker
    
    @EnvironmentObject
    private var playerVM: PlayerViewModel
    
    public init() {}
        
    public var body: some View {
        VStack {
            VideoPlayer(player: playerVM.player, videoOverlay: {
                if playerVM.isShowDebugOverlay {
                    VideoOverlayView()
                }
            })
#if os(iOS)
            .aspectRatio(CGSize(width: 16, height: 9), contentMode: .fit)
#else
            .frame(height: 360)
#endif
            .onReceive(adTracker.session.$sessionInfo) { info in
                load(with: info.manifestUrl, isAutomaticallyPreservesTimeOffsetFromLive: adTracker.session.automaticallyPreservesTimeOffsetFromLive)
            }
            .onReceive(adTracker.session.$automaticallyPreservesTimeOffsetFromLive, perform: { enabled in
                reload(with: adTracker.session.sessionInfo.manifestUrl, isAutomaticallyPreservesTimeOffsetFromLive: enabled)
            })
        }
    }
}

extension PlayerView {
    private func load(with urlString: String, isAutomaticallyPreservesTimeOffsetFromLive: Bool) {
        guard playerVM.player.timeControlStatus != .playing else { return }

        let interstitialController = AVPlayerInterstitialEventMonitor(primaryPlayer: playerVM.player)
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
        
        let interstitialController = AVPlayerInterstitialEventController(primaryPlayer: playerVM.player)
        interstitialController.cancelCurrentEvent(withResumptionOffset: .zero)
        
        if let originalPrimaryStatus = playerObserver.primaryStatus {
            if originalPrimaryStatus == .playing {
                playerVM.player.pause()
            }
            
            let playerItem = AVPlayerItem(url: url)
            playerItem.automaticallyPreservesTimeOffsetFromLive = isAutomaticallyPreservesTimeOffsetFromLive
            
            // HMS-10699: Set a new player instead of using replaceCurrentItem(with:)
            playerVM.setPlayer(AVPlayer(playerItem: playerItem))
            playerObserver.setPlayer(playerVM.player)
            
            playerVM.player.play()
        }
    }
}

struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView()
            .environmentObject(HarmonicAdTracker())
            .environmentObject(PlayerViewModel())
    }
}
