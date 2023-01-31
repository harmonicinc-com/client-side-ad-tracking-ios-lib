//
//  AdView.swift
//
//
//  Created by Michael on 27/1/2023.
//

import SwiftUI

struct AdView: View {
    @EnvironmentObject
    var adTracker: HarmonicAdTracker
    
    @ObservedObject
    var ad: Ad
    
    var adBreakId: String?
    
    @State
    private var expandAd = true
    
    var body: some View {
        DisclosureGroup("Ad: \(ad.id ?? "nil")", isExpanded: $expandAd) {
            ForEach(ad.trackingEvents, id: \.event) { trackingEvent in
                TrackingEventView(trackingEvent: trackingEvent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onReceive(adTracker.$adPods) { adPods in
            if let pod = adPods.first(where: { $0.id == adBreakId }),
                let ad = pod.ads.first(where: { $0.id == ad.id }),
                let startTime = ad.startTime,
                let duration = ad.duration {
                expandAd = adTracker.getPlayheadTime() <= startTime + duration + KEEP_PAST_AD_MS
            }
        }
    }
}

struct AdView_Previews: PreviewProvider {
    static var previews: some View {
        AdView(ad: sampleAdBeacon?.adBreaks.first?.ads.first ?? Ad())
            .environmentObject(HarmonicAdTracker())
    }
}
