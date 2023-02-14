//
//  VideoOverlayView.swift
//  
//
//  Created by Michael on 13/2/2023.
//

import SwiftUI

struct VideoOverlayView: View {
    @EnvironmentObject
    private var playerVM: PlayerViewModel
    
    @StateObject
    private var playerObserver = PlayerObserver()
    
    @State
    private var currentTime = Date()
    
    private let dateFormatter: DateFormatter
    
    private var textToDisplay: String {
        var text = "Current time: \(dateFormatter.string(from: playerObserver.currentDate ?? Date()))"
        if let playheadDate = playerObserver.playhead, let currentDate = playerObserver.currentDate?.timeIntervalSince1970 {
            text += String(format: "\nLive latency: %.2fs", currentDate - playheadDate / 1_000)
        }
        return text
    }
        
    init() {
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
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
        .onAppear {
            playerObserver.setPlayer(playerVM.player)
        }
    }
}

struct VideoOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        VideoOverlayView()
            .environmentObject(PlayerViewModel())
    }
}
