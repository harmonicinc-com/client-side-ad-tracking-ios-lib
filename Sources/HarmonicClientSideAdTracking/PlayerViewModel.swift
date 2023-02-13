//
//  PlayerViewModel.swift
//
//
//  Created by Michael on 8/2/2023.
//

import AVFoundation

public class PlayerViewModel: ObservableObject {
    
    @Published
    public private(set) var player = AVPlayer()
    
    public init() {}

}
