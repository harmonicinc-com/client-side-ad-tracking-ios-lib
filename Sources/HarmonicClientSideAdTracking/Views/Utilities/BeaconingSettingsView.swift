//
//  BeaconingSettingsView.swift
//
//
//  Created by Michael on 15/3/2024.
//

import SwiftUI

public struct BeaconingSettingsView: View {
    @ObservedObject private var session: AdBeaconingSession
    
    @State private var expand = true
    
    public init(session: AdBeaconingSession) {
        self.session = session
    }
    
    public var body: some View {
        ExpandableListView("Beaconing Settings", isExpanded: $expand) {
            VStack {
                HStack {
                    Text("Metadata Type")
                    if #available(tvOS 17.0, *) {
                        Picker("Metadata Type", selection: $session.metadataType) {
                            ForEach(MetadataType.allCases) { type in
                                Text(type.rawValue)
                            }
                        }
#if os(tvOS)
                        .pickerStyle(.menu)
                        .frame(width: 360)
#else
                        .pickerStyle(.segmented)
#endif
                    } else {
                        Picker("Metadata Type", selection: $session.metadataType) {
                            ForEach(MetadataType.allCases) { type in
                                Text(type.rawValue)
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 10)
        }
        .font(.caption2)
    }
}

#Preview {
    BeaconingSettingsView(session: AdBeaconingSession())
}

