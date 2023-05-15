//
//  ExpandableListView.swift
//  
//
//  Created by Michael on 7/2/2023.
//

import SwiftUI

struct ExpandableListView<Content: View> : View {
    
    private let label: String
    private let isExpanded: Binding<Bool>
    private let content: () -> Content
    
    init(_ label: String, isExpanded: Binding<Bool>, @ViewBuilder _ content: @escaping () -> Content) {
        self.label = label
        self.isExpanded = isExpanded
        self.content = content
    }
    
    var body: some View {
#if os(iOS)
        DisclosureGroup(label, isExpanded: isExpanded) {
            content()
                .padding(.leading, 5)
        }
#else
        VStack(alignment: .leading) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                Text(label)
                    .font(.caption2)
                    .padding(-15)
                Spacer()
                isExpanded.wrappedValue
                ?
                Image(systemName: "chevron.down")
                    .resizable()
                    .frame(width: 20, height: 10)
                    .padding(-5)
                :
                Image(systemName: "chevron.right")
                    .resizable()
                    .frame(width: 10, height: 20)
                    .padding(-10)
            }
            if isExpanded.wrappedValue {
                content()
                    .padding(.leading, 5)
            }
        }
        .padding(.horizontal, 15)
#endif
    }
}

struct ExpandableListView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ExpandableListView("Ad events", isExpanded: .constant(true)) {
                TrackingEventView(trackingEvent: sampleAdBeacon?.adBreaks.first?.ads.first?.trackingEvents.first ?? TrackingEvent())
            }
            ExpandableListView("Ad events", isExpanded: .constant(true)) {
                TrackingEventView(trackingEvent: sampleAdBeacon?.adBreaks.first?.ads.first?.trackingEvents.first ?? TrackingEvent())
            }
        }
    }
}
