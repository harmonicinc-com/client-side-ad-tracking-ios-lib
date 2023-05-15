//
//  VideoOverlayView.swift
//  
//
//  Created by Michael on 13/2/2023.
//

import SwiftUI

struct VideoOverlayView: View {
    @ObservedObject private var playerObserver: PlayerObserver
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return formatter
    }()
    
    private var textToDisplay: String {
        var text = "Current time: \(dateFormatter.string(from: playerObserver.currentDate ?? Date()))"
        if let playheadDate = playerObserver.playhead, let currentDate = playerObserver.currentDate?.timeIntervalSince1970 {
            text += String(format: "\nLive latency: %.2fs", currentDate - playheadDate / 1_000)
        }
        return text
    }
    
    init(playerObserver: PlayerObserver) {
        self.playerObserver = playerObserver
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(textToDisplay)
                    .padding(5)
                    .background(Color.black.opacity(0.5))
                    .foregroundColor(.white)
                    .font(.caption)
                Spacer()
            }
            Spacer()
        }
    }
}

struct VideoOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        VideoOverlayView(playerObserver: PlayerObserver())
    }
}
