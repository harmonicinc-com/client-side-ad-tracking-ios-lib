//
//  PlayerObserver.swift
//
//
//  Created by Michael on 31/1/2023.
//

import Combine
import AVFoundation

public class PlayerObserver {
    
    @Published
    public private(set) var playhead: Double?
    
    private var dateObservation: Any?
    
    public init(player: AVPlayer) {
        dateObservation = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: nil, using: { _ in
            self.playhead = (player.currentItem?.currentDate()?.timeIntervalSince1970 ?? 0) * 1_000
        })
    }
    
    public init() {}
    
}
