//
//  ToggleView.swift
//  
//
//  Created by Michael on 24/2/2023.
//

import SwiftUI

public struct ToggleView: View {
    @EnvironmentObject
    private var adTracker: HarmonicAdTracker
    
    @EnvironmentObject
    private var playerVM: PlayerViewModel
    
    @State
    private var expand = false
    
    public init() {}
    
    public var body: some View {
        ExpandableListView("Settings", isExpanded: $expand) {
            VStack {
                Toggle("Debug Overlay", isOn: $playerVM.isShowDebugOverlay)
                Toggle("Set Automatically Preserves Time Offset From Live", isOn: $adTracker.session.automaticallyPreservesTimeOffsetFromLive)
            }
            .padding(.trailing, 10)
        }
        .font(.caption2)
    }
}

struct SwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        ToggleView()
            .environmentObject(HarmonicAdTracker())
            .environmentObject(PlayerViewModel())
    }
}
