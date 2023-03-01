//
//  PlayerView.swift
//
//
//  Created by Michael on 19/1/2023.
//

import SwiftUI
import AVKit
import os

private let BEACON_UPDATE_INTERVAL: TimeInterval = 0.5
private let INTERSTITIAL_BEACON_SEND_TOLERANCE: Double = 1_500

public struct PlayerView: View {
    private static let logger = Logger(
        subsystem: Bundle.module.bundleIdentifier!,
        category: String(describing: PlayerView.self)
    )
    
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
                if playerVM.isShowDebugOverlay {
                    VideoOverlayView()
                }
            })
#if os(iOS)
            .aspectRatio(CGSize(width: 16, height: 9), contentMode: .fit)
#else
            .frame(height: 360)
#endif
            .onReceive(checkNeedSendBeaconTimer) { _ in
                guard let playhead = playerObserver.playhead else { return }
                let shouldCheckBeacon = shouldCheckBeaconForInterstitials(playhead: playhead)
                Task {
                    if shouldCheckBeacon {
                        await adTracker.needSendBeacon(time: playhead)
                    }
                    await adTracker.setPlayheadTime(playhead, shouldCheckBeacon: shouldCheckBeacon)
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
    
    private func shouldCheckBeaconForInterstitials(playhead: Double) -> Bool {
        var shouldCheckBeacon = true
        
        if playerObserver.hasInterstitialEvents,
           let interstitialStatus = playerObserver.interstitialStatus,
           interstitialStatus != .playing,
           adTracker.playheadIsIncludedInStoredAdPods() {
            // There are interstitial events and the playhead is inside the range of the adPods, but the interstitialPlayer is not playing
            shouldCheckBeacon = false
            
            if let interstitialDate = playerObserver.interstitialDate,
               let interstitialStop = playerObserver.interstitialStoppedDate,
               let duration = playerObserver.currentInterstitialDuration {
                // The interstitialPlayer status may change to .paused (and the interstitalStoppedDate set) before the "complete" signal is sent.
                // So we should still check beacon if the stop date is not too far from the calculated one (interstitialDate + duration)
                // and it has just stopped playing the interstitial.
                if abs(interstitialStop - (interstitialDate + duration)) <= INTERSTITIAL_BEACON_SEND_TOLERANCE &&
                    abs(interstitialStop - playhead) <= INTERSTITIAL_BEACON_SEND_TOLERANCE {
                    shouldCheckBeacon = true
                } else {
                    shouldCheckBeacon = false
                }
                
            }
        }
        
        return shouldCheckBeacon
    }
}

struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView()
            .environmentObject(HarmonicAdTracker())
            .environmentObject(PlayerViewModel())
    }
}
