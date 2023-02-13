//
//  TrackingEventView.swift
//
//
//  Created by Michael on 27/1/2023.
//

import SwiftUI

struct TrackingEventView: View {
    @ObservedObject
    private var trackingEvent: TrackingEvent
    
    private let dateFormatter: DateFormatter
    
    private var dateString: String {
        return dateFormatter.string(from: Date(timeIntervalSince1970: (trackingEvent.startTime ?? 0) / 1_000))
    }
    
    init(trackingEvent: TrackingEvent) {
        self.trackingEvent = trackingEvent
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
    }
    
    var body: some View {
        HStack {
            Image(systemName: getSystemImageName(for: trackingEvent.reportingState))
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading) {
                Text("Event: \((trackingEvent.event ?? .unknown).rawValue)")
                    .bold()
                    .font(.caption)
                ForEach(trackingEvent.signalingUrls, id: \.self) { url in
                    Text("URL: \(url)")
                        .font(.caption2)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                }
                Text("Time: \(dateString)")
                    .font(.caption2)
            }
            Spacer()
        }
    }
}

extension TrackingEventView {
    private func getSystemImageName(for reportingState: ReportingState?) -> String {
        switch reportingState {
        case .connecting:
            return "hourglass.circle"
        case .done:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.circle"
        default:
            return "circle"
        }
    }
}

struct TrackingEventView_Previews: PreviewProvider {
    static var previews: some View {
        TrackingEventView(trackingEvent: sampleAdBeacon?.adBreaks.first?.ads.first?.trackingEvents.first ?? TrackingEvent())
            .previewLayout(.fixed(width: 300, height: 80))
    }
}
