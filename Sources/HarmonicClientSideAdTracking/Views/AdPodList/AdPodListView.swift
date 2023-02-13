//
//  AdPodListView.swift
//
//
//  Created by Michael on 30/1/2023.
//

import SwiftUI

public struct AdPodListView: View {
    @EnvironmentObject
    private var adTracker: HarmonicAdTracker
    
    @State
    private var expandAdPods = true
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            ExpandableListView("Tracking Events", isExpanded: $expandAdPods, {
                ForEach(adTracker.adPods) { pod in
                    AdBreakView(adBreak: pod)
                }
            })
            .font(.caption2)
        }
    }
}

struct AdPodListView_Previews: PreviewProvider {
    static var previews: some View {
        AdPodListView()
            .environmentObject(HarmonicAdTracker(adPods: sampleAdBeacon?.adBreaks ?? []))
    }
}
