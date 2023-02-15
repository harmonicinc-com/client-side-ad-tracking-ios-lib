//
//  AdBreakView.swift
//
//
//  Created by Michael on 27/1/2023.
//

import SwiftUI

let KEEP_PAST_AD_MS: Double = 2_000

struct AdBreakView: View {
    @ObservedObject
    var adBreak: AdBreak
    
    @EnvironmentObject
    private var adTracker: HarmonicAdTracker
    
    @State
    private var expandAdBreak = true
    
    var body: some View {
        ExpandableListView("Ad Break: \(adBreak.id ?? "nil")", isExpanded: $expandAdBreak, {
            ForEach(adBreak.ads) { ad in
                AdView(ad: ad, adBreakId: adBreak.id)
            }
        })
        .onReceive(adTracker.$adPods) { adPods in
            if let pod = adPods.first(where: { $0.id == adBreak.id }),
               let startTime = pod.startTime,
               let duration = pod.duration {
                if adBreak.expanded == nil {
                    Task {
                        expandAdBreak = await adTracker.getPlayheadTime() <= startTime + duration + KEEP_PAST_AD_MS
                    }
                }
            }
        }
        .onChange(of: expandAdBreak) { newValue in
            adBreak.expanded = newValue
        }
    }
}

struct AdBreakView_Previews: PreviewProvider {
    static var previews: some View {
        AdBreakView(adBreak: sampleAdBeacon?.adBreaks.first ?? AdBreak())
            .environmentObject(HarmonicAdTracker())
    }
}
