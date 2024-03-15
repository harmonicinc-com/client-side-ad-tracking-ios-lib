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
            .onReceive(session.$automaticallyPreservesTimeOffsetFromLive, perform: { enabled in
                session.reload(with: session.sessionInfo.manifestUrl,
                               isAutomaticallyPreservesTimeOffsetFromLive: enabled)
            })
            .onReceive(session.$metadataType, perform: { _ in
                session.reload(with: session.sessionInfo.manifestUrl,
                               isAutomaticallyPreservesTimeOffsetFromLive: session.automaticallyPreservesTimeOffsetFromLive)
            })
        }
    }
}

struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView(session: createSampleSession() ?? AdBeaconingSession())
    }
}
