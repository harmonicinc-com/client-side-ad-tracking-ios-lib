//
//  AdView.swift
//
//
//  Created by Michael on 27/1/2023.
//

import SwiftUI

struct AdView: View {
    @ObservedObject
    var ad: Ad
    
    private var adBreakId: String?
    
    @EnvironmentObject
    private var adTracker: HarmonicAdTracker
    
    @State
    private var expandAd = true
    
    @FocusState
    private var trackingEventType: EventType?
    
    public init(ad: Ad, adBreakId: String? = nil) {
        self.ad = ad
        self.adBreakId = adBreakId
    }
    
    var body: some View {
        ExpandableListView("Ad: \(ad.id ?? "nil")", isExpanded: $expandAd, {
            ForEach(ad.trackingEvents, id: \.event) { trackingEvent in
#if os(iOS)
                TrackingEventView(trackingEvent: trackingEvent)
                    .frame(maxWidth: .infinity, alignment: .leading)
#else
                Button {} label: {
                    TrackingEventView(trackingEvent: trackingEvent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(-20)
                }
                .focused($trackingEventType, equals: trackingEvent.event)
#endif
            }
        })
        .onReceive(adTracker.$adPods) { adPods in
            if let pod = adPods.first(where: { $0.id == adBreakId }),
               let ad = pod.ads.first(where: { $0.id == ad.id }),
               let startTime = ad.startTime,
               let duration = ad.duration {
                if ad.expanded == nil {
                    Task {
                        expandAd = await adTracker.getPlayheadTime() <= startTime + duration + KEEP_PAST_AD_MS
                    }
                }
                let trackingEvents = ad.trackingEvents.filter({ ($0.reportingState) == .done })
                trackingEventType = trackingEvents.last?.event
            }
        }
        .onChange(of: expandAd) { newValue in
            ad.expanded = newValue
        }
    }
}

struct AdView_Previews: PreviewProvider {
    static var previews: some View {
        AdView(ad: sampleAdBeacon?.adBreaks.first?.ads.first ?? Ad())
            .environmentObject(HarmonicAdTracker())
    }
}
