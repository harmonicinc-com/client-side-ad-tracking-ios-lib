//
//  AdPodListView.swift
//
//
//  Created by Michael on 30/1/2023.
//

import SwiftUI

public struct AdPodListView: View {
    @ObservedObject private var session: AdBeaconingSession
    
    @State private var expandAdPods = true
    
    public init(session: AdBeaconingSession) {
        self.session = session
    }
    
    public var body: some View {
        ScrollView {
            ExpandableListView("Tracking Events", isExpanded: $expandAdPods, {
                ForEach(session.adPods) { pod in
                    AdBreakView(adBreak: pod, session: session)
                }
            })
            .font(.caption2)
        }
    }
}

struct AdPodListView_Previews: PreviewProvider {
    static var previews: some View {
        AdPodListView(session: createSampleSession() ?? AdBeaconingSession())
    }
}
