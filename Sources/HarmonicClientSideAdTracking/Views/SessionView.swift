//
//  SessionView.swift
//
//
//  Created by Michael on 30/1/2023.
//

import SwiftUI
import AVFoundation

public struct SessionView: View {
    
    @EnvironmentObject
    private var playerObserver: PlayerObserver
    
    @EnvironmentObject
    private var adTracker: HarmonicAdTracker
    
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
        self.dateFormatter.dateFormat = "dd/MM/yyyy HH:mm:ss.SSS"
    }
    
    public var body: some View {
        VStack(alignment: .leading) {
            Text("Playhead: \(dateFormatter.string(from: getPlayheadDate(playerObserver.playhead)))")
                .bold()
            if let timeToNextAdBreak = getTimeToNextBreak(playhead: playerObserver.playhead) {
                Text(String(format: "Time to next ad break: %.3fs", timeToNextAdBreak))
                    .bold()
            }
            if let interstitialDate = getInterstitialDate(playerObserver.interstitialDate) {
                Text("Last interstitial date: \(dateFormatter.string(from: interstitialDate))")
            }
            if let interstitialStartTime = playerObserver.interstitialStartTime {
                Text(String(format: "Last interstitial started: %.3fs", interstitialStartTime))
            }
            if let interstitialStop = playerObserver.interstitialStopTime {
                Text(String(format: "Last interstitial stopped: %.3fs", interstitialStop))
            }
            ExpandableListView("Session Info", isExpanded: $expandSession) {
                ScrollView {
                    VStack(alignment: .leading) {
                        ExpandableListView("Media URL", isExpanded: $expandMediaUrl) {
                            Text(adTracker.session.sessionInfo.mediaUrl)
                        }
                        ExpandableListView("Manifest URL", isExpanded: $expandManifestUrl) {
                            Text(adTracker.session.sessionInfo.manifestUrl)
                        }
                        ExpandableListView("Ad tracking metadata URL", isExpanded: $expandAdTrackingMetadataUrl) {
                            Text(adTracker.session.sessionInfo.adTrackingMetadataUrl)
                        }
                    }
#if os(tvOS)
                    .font(.system(size: 20))
#else
                    .font(.caption2)
                    .textSelection(.enabled)
#endif
                }
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
    
    private func getInterstitialDate(_ date: Double?) -> Date? {
        if let date = date {
            return Date(timeIntervalSince1970: date / 1_000)
        } else {
            return nil
        }
    }
}

struct SessionInfoView_Previews: PreviewProvider {
    static var previews: some View {
        SessionView()
            .environmentObject(HarmonicAdTracker())
            .environmentObject(PlayerViewModel())
    }
}
