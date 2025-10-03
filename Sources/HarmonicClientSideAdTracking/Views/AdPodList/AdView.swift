//
//  AdView.swift
//
//
//  Created by Michael on 27/1/2023.
//

import SwiftUI

private let AD_END_TRACKING_EVENT_TIME_TOLERANCE: Double = 500

struct AdView: View {
    @ObservedObject private var ad: Ad
    @ObservedObject private var session: AdBeaconingSession
    
    @State private var expandAd = true
    private var adBreakId: String?
    
#if os(tvOS)
    @FocusState private var trackingEventType: EventType?
#endif
    
    public init(session: AdBeaconingSession, ad: Ad, adBreakId: String? = nil) {
        self.session = session
        self.ad = ad
        self.adBreakId = adBreakId
    }
    
    var body: some View {
        ExpandableListView("Ad: \(ad.id ?? "nil"); Duration: \((ad.duration ?? 0)/1_000)s", isExpanded: $expandAd, {
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
        .onReceive(session.$adPods) { adPods in
            if let pod = adPods.first(where: { $0.id == adBreakId }),
               let ad = pod.ads.first(where: { $0.id == ad.id }),
               let startTime = ad.startTime,
               let duration = ad.duration,
               playheadIsIn(ad) {
                if ad.expanded == nil {
                    expandAd = session.latestPlayhead <= startTime + duration + KEEP_PAST_AD_MS
                }
#if os(tvOS)
                if !session.playerControlIsFocused {
                    let trackingEvents = ad.trackingEvents.filter({ ($0.reportingState) != .idle })
                    trackingEventType = trackingEvents.last?.event
                }
#endif
            }
        }
        .onChange(of: expandAd) { newValue in
            ad.expanded = newValue
        }
    }
}

extension AdView {
    private func playheadIsIn(_ ad: Ad) -> Bool {
        if let start = ad.startTime, let duration = ad.duration {
            let end = start + duration
            if start...(end + AD_END_TRACKING_EVENT_TIME_TOLERANCE) ~= session.latestPlayhead {
                return true
            }
        }
        return false
    }
}

struct AdView_Previews: PreviewProvider {
    static var previews: some View {
        AdView(session: createSampleSession() ?? AdBeaconingSession(), ad: sampleAdBeacon?.adBreaks.first?.ads.first ?? Ad())
    }
}
