//
//  ToggleView.swift
//  
//
//  Created by Michael on 24/2/2023.
//

import SwiftUI

public struct ToggleView: View {
    @ObservedObject private var session: AdBeaconingSession

    @State private var expand = false
    
    public init(session: AdBeaconingSession) {
        self.session = session
    }
    
    public var body: some View {
        ExpandableListView("Settings", isExpanded: $expand) {
            VStack {
                Toggle("Debug Overlay", isOn: $session.isShowDebugOverlay)
                Toggle("Automatically Preserves Time Offset From Live", isOn: $session.automaticallyPreservesTimeOffsetFromLive)
                Toggle("POST Request to Initialise Session", isOn: $session.isInitRequest)
            }
            .padding(.trailing, 10)
        }
        .font(.caption2)
    }
}

struct SwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        ToggleView(session: createSampleSession() ?? AdBeaconingSession())
    }
}
