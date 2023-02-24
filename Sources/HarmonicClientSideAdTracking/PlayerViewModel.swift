//
//  PlayerViewModel.swift
//
//
//  Created by Michael on 8/2/2023.
//

import AVFoundation
import Combine

public class PlayerViewModel: ObservableObject {
    
    @Published
    public private(set) var player = AVPlayer()
    
    @Published
    public private(set) var playerControlIsFocused = false
    
    public init() {}
    
    public func setPlayer(_ player: AVPlayer) {
        self.player = player
    }
    
    public func setPlayerControlIsFocused(_ focused: Bool) {
        self.playerControlIsFocused = focused
    }

}
