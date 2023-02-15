//
//  PlayerView.swift
//
//
//  Created by Michael on 19/1/2023.
//

import SwiftUI
import AVKit

let BEACON_UPDATE_INTERVAL: TimeInterval = 0.5

public struct PlayerView: View {
    
    @StateObject
    private var playerObserver = PlayerObserver()
    
    @EnvironmentObject
    private var session: Session
    
    @EnvironmentObject
    private var adTracker: HarmonicAdTracker
    
    @EnvironmentObject
    private var playerVM: PlayerViewModel
    
    public init() {}
    
    private let checkNeedSendBeaconTimer = Timer.publish(every: BEACON_UPDATE_INTERVAL, on: .main, in: .common).autoconnect()
    
    public var body: some View {
        VStack {
            VideoPlayer(player: playerVM.player, videoOverlay: {
                VideoOverlayView()
            })
#if os(iOS)
            .aspectRatio(CGSize(width: 16, height: 9), contentMode: .fit)
#else
            .frame(height: 360)
#endif
            .onReceive(checkNeedSendBeaconTimer) { _ in
                guard let playhead = playerObserver.playhead else { return }
                Task {
                    if let status = playerObserver.interstitialStatus,
                        status != .playing,
                        adTracker.playheadIsIncludedInStoredAdPods(playhead: playhead) {
                        return
                    }
                    await adTracker.needSendBeacon(time: playhead)
                }
            }
            .onReceive(session.$sessionInfo) { info in
                if let url = URL(string: info.manifestUrl) {
                    playerVM.player.pause()
                    
                    let playerItem = AVPlayerItem(url: url)
                    playerItem.automaticallyPreservesTimeOffsetFromLive = true
                    playerVM.player.replaceCurrentItem(with: playerItem)
                    
                    playerVM.player.play()
                }
            }
            .onAppear {
                playerObserver.setPlayer(playerVM.player)
            }
            .onDisappear {
                playerVM.player.pause()
                playerVM.player.replaceCurrentItem(with: nil)
            }
        }
    }
}

struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView()
            .environmentObject(sampleSession)
            .environmentObject(HarmonicAdTracker())
            .environmentObject(PlayerViewModel())
    }
}
