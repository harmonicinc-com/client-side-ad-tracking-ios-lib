//
//  SessionView.swift
//
//
//  Created by Michael on 30/1/2023.
//

import SwiftUI

public struct SessionView: View {
    let playerObserver: PlayerObserver
    
    @EnvironmentObject
    var adTracker: HarmonicAdTracker
    
    @EnvironmentObject
    var session: Session
    
    @State
    private var playheadDate: Date?
    
    @State
    private var timeToNextAdBreak: TimeInterval?
    
    private let dateFormatter: DateFormatter
    
    public init(playerObserver: PlayerObserver) {
        self.playerObserver = playerObserver
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
    }
    
    public var body: some View {
        VStack(alignment: .leading) {
            Text("Playhead: \(dateFormatter.string(from: playheadDate ?? .distantPast))")
                .bold()
            Text("Time to next ad break: \(timeToNextAdBreak ?? .infinity)s")
                .bold()
            DisclosureGroup("Session Info") {
                VStack(alignment: .leading) {
                    Text("Media URL:")
                        .bold()
                    Text(session.sessionInfo.mediaUrl)
                        .font(.caption2)
                        .textSelection(.enabled)
                    Text("Manifest URL")
                        .bold()
                    Text(session.sessionInfo.manifestUrl)
                        .font(.caption2)
                        .textSelection(.enabled)
                    Text("Ad tracking metadata URL")
                        .bold()
                    Text(session.sessionInfo.adTrackingMetadataUrl)
                        .font(.caption2)
                        .textSelection(.enabled)
                }
            }
            .onReceive(playerObserver.$playhead) { playhead in
                playheadDate = Date(timeIntervalSince1970: (playhead ?? 0) / 1_000)
                timeToNextAdBreak = getTimeToNextBreak(playhead: playhead ?? 0) / 1_000
            }
        }
        .font(.caption)
    }
}

extension SessionView {
    private func getTimeToNextBreak(playhead: Double) -> Double {
        if let minStartTime = (adTracker.adPods
            .filter { $0.startTime ?? -.infinity > playhead }
            .min { $0.startTime ?? -.infinity < $1.startTime ?? -.infinity }?.startTime) {
            return minStartTime - playhead
        } else {
            return .infinity
        }
    }
}

struct SessionInfoView_Previews: PreviewProvider {
    static var previews: some View {
        SessionView(playerObserver: PlayerObserver())
            .environmentObject(sampleSession)
            .environmentObject(HarmonicAdTracker())
    }
}
