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
    
    let player: AVPlayer
    
    @StateObject
    var playerObserver = PlayerObserver()
    
    @EnvironmentObject
    var session: Session
    
    @EnvironmentObject
    var adTracker: HarmonicAdTracker
    
    private let checkNeedSendBeaconTimer = Timer.publish(every: BEACON_UPDATE_INTERVAL, on: .main, in: .common).autoconnect()
    
    public init(player: AVPlayer) {
        self.player = player
    }
    
    public var body: some View {
        VStack {
            VideoPlayer(player: player)
                .frame(height: 250)
                .onReceive(checkNeedSendBeaconTimer) { _ in
                    Task {
                        await adTracker.needSendBeacon(time: playerObserver.playhead ?? 0)
                    }
                }
                .onReceive(session.$sessionInfo) { info in
                    if let url = URL(string: info.manifestUrl) {
                        player.replaceCurrentItem(with: AVPlayerItem(url: url))
                        player.play()
                    }
                }
                .onAppear {
                    playerObserver.setPlayer(player)
                }
                .onDisappear {
                    player.pause()
                    player.replaceCurrentItem(with: nil)
                }
        }
    }
}

struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView(player: AVPlayer())
            .environmentObject(sampleSession)
            .environmentObject(HarmonicAdTracker())
    }
}
