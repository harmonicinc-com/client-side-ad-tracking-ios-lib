//
//  DetailedDebugInfoView.swift
//  
//
//  Created by Michael on 1/3/2023.
//

import SwiftUI

public struct DetailedDebugInfoView: View {
    @StateObject
    private var playerObserver = PlayerObserver()
    
    @EnvironmentObject
    private var adTracker: HarmonicAdTracker
    
    @EnvironmentObject
    private var playerVM: PlayerViewModel
    
    @State
    private var expandDebugInfo = false
    
    private let dateFormatter: DateFormatter
    
    public init() {
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss"
    }
    
    public var body: some View {
        ExpandableListView("Detailed debug info", isExpanded: $expandDebugInfo) {
            VStack(alignment: .leading) {
                if let lastDataRange = getDataRangeDates(adTracker.lastDataRange) {
                    Text("Data range available: \(dateFormatter.string(from: lastDataRange.0)) to \(dateFormatter.string(from: lastDataRange.1))")
                        .lineLimit(0)
                } else {
                    Text("No data range available in ad tracking metadata.")
                }
                if !adTracker.playedTimeOutsideDataRange.isEmpty {
                    Text("Time ranges played outside of available data range:")
                        .bold()
                    ScrollView {
                        ForEach(adTracker.playedTimeOutsideDataRange, id: \.start) { range in
                            if let rangeDates = getDataRangeDates(range) {
                                Text("\(dateFormatter.string(from: rangeDates.0)) to \(dateFormatter.string(from: rangeDates.1))")
                                    .padding(.leading)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.caption2)
        }
        .font(.caption)
        .onAppear {
            self.playerObserver.setPlayer(playerVM.player)
        }
    }
}

extension DetailedDebugInfoView {
    private func getDataRangeDates(_ dataRange: DataRange?) -> (Date, Date)? {
        var dataRangeDates: (Date, Date)? = nil
        if let dataRange = dataRange,
           let start = dataRange.start,
           let end = dataRange.end {
            dataRangeDates = (Date(timeIntervalSince1970: start / 1_000), Date(timeIntervalSince1970: end / 1_000))
        }
        return dataRangeDates
    }
}

struct DetailedDebugInfoView_Previews: PreviewProvider {
    static var previews: some View {
        DetailedDebugInfoView()
            .environmentObject(HarmonicAdTracker())
            .environmentObject(PlayerViewModel())
    }
}
