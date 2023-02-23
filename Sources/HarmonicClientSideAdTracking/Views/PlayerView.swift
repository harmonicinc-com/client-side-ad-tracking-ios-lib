//
//  PlayerView.swift
//
//
//  Created by Michael on 19/1/2023.
//

import SwiftUI
import AVKit

let BEACON_UPDATE_INTERVAL: TimeInterval = 0.5
private let INTERSTITIAL_BEACON_SEND_TOLERANCE: Double = 1500

public struct PlayerView: View {
    
    @StateObject
    private var playerObserver = PlayerObserver()
    
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
                if let interstitialStatus = playerObserver.interstitialStatus,
                   interstitialStatus != .playing {
                    if playerObserver.interstitialStartDate == nil { return }
                    
                    if let interstitialStop = playerObserver.interstitialStoppedTime,
                       let duration = playerObserver.currentAdDuration,
                       let interstitialStart = playerObserver.interstitialStartDate {
                        if abs(interstitialStop - (interstitialStart + duration*1000)) > INTERSTITIAL_BEACON_SEND_TOLERANCE { return }
                    } else {
                        return
                    }
                }
                
                Task {
                    await adTracker.needSendBeacon(time: playhead)
                }
            }
            .onReceive(adTracker.session.$sessionInfo) { info in
                reload(with: info.manifestUrl, isAutomaticallyPreservesTimeOffsetFromLive: adTracker.session.automaticallyPreservesTimeOffsetFromLive)
            }
            .onReceive(adTracker.session.$automaticallyPreservesTimeOffsetFromLive, perform: { enabled in
                reload(with: adTracker.session.sessionInfo.manifestUrl, isAutomaticallyPreservesTimeOffsetFromLive: enabled)
            })
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

extension PlayerView {
    private func reload(with urlString: String, isAutomaticallyPreservesTimeOffsetFromLive: Bool) {
        guard let url = URL(string: urlString) else { return }
        
        let interstitialController = AVPlayerInterstitialEventController(primaryPlayer: playerVM.player)
        interstitialController.cancelCurrentEvent(withResumptionOffset: .zero)
        
        if let originalPrimaryStatus = playerObserver.primaryStatus {
            if originalPrimaryStatus == .playing {
                playerVM.player.pause()
            }
            
            playerVM.player.replaceCurrentItem(with: nil)
            let playerItem = AVPlayerItem(url: url)
            playerItem.automaticallyPreservesTimeOffsetFromLive = isAutomaticallyPreservesTimeOffsetFromLive
            playerVM.player.replaceCurrentItem(with: playerItem)
            
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
