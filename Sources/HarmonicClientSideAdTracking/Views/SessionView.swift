//
//  SessionView.swift
//
//
//  Created by Michael on 30/1/2023.
//

import SwiftUI
import AVFoundation

public struct SessionView: View {
    
    @StateObject
    private var playerObserver = PlayerObserver()
    
    @EnvironmentObject
    private var adTracker: HarmonicAdTracker
    
    @EnvironmentObject
    private var session: Session
    
    @EnvironmentObject
    private var playerVM: PlayerViewModel
    
    @State
    private var expandSession = false
    
    @State
    private var expandMediaUrl = true
    
    @State
    private var expandManifestUrl = true
    
    @State
    private var expandAdTrackingMetadataUrl = true
    
    private let dateFormatter: DateFormatter
    
    public init() {
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
    }
    
    public var body: some View {
        VStack(alignment: .leading) {
            Text("Playhead: \(dateFormatter.string(from: getPlayheadDate(playerObserver.playhead)))")
                .bold()
            if let timeToNextAdBreak = getTimeToNextBreak(playhead: playerObserver.playhead) {
                Text(String(format: "Time to next ad break: %.2fs", timeToNextAdBreak))
                    .bold()
            }
            if let interstitialStart = getInterstitialStartDate(playerObserver.interstitialStartDate) {
                Text("Last interstitial start: \(dateFormatter.string(from: interstitialStart))")
            }
            if let interstitialElapsed = playerObserver.elapsedTimeInInterstitial {
                Text(String(format: "Last interstitial elapsed: %.2fs", interstitialElapsed))
            }
            ExpandableListView("Session Info", isExpanded: $expandSession) {
                ScrollView {
                    VStack(alignment: .leading) {
                        ExpandableListView("Media URL", isExpanded: $expandMediaUrl) {
                            Text(session.sessionInfo.mediaUrl)
                        }
                        ExpandableListView("Manifest URL", isExpanded: $expandManifestUrl) {
                            Text(session.sessionInfo.manifestUrl)
                        }
                        ExpandableListView("Ad tracking metadata URL", isExpanded: $expandAdTrackingMetadataUrl) {
                            Text(session.sessionInfo.adTrackingMetadataUrl)
                        }
                    }
                    .font(.caption2)
#if os(iOS)
                    .textSelection(.enabled)
#endif
                }
            }
            .onAppear {
                self.playerObserver.setPlayer(playerVM.player)
            }
        }
        .font(.caption)
    }
}

extension SessionView {
    private func getPlayheadDate(_ playhead: Double?) -> Date {
        return Date(timeIntervalSince1970: (playhead ?? 0) / 1_000)
    }
    
    private func getTimeToNextBreak(playhead: Double?) -> Double? {
        if let minStartTime = (adTracker.adPods
            .filter { ($0.startTime ?? -.infinity) > (playhead ?? 0) }
            .min { ($0.startTime ?? -.infinity) < ($1.startTime ?? -.infinity) }?.startTime) {
            return (minStartTime - (playhead ?? 0)) / 1_000
        } else {
            return nil
        }
    }
    
    private func getInterstitialStartDate(_ start: Double?) -> Date? {
        if let start = start {
            return Date(timeIntervalSince1970: start / 1_000)
        } else {
            return nil
        }
    }
}

struct SessionInfoView_Previews: PreviewProvider {
    static var previews: some View {
        SessionView()
            .environmentObject(sampleSession)
            .environmentObject(HarmonicAdTracker())
            .environmentObject(PlayerViewModel())
    }
}
