//
//  PlayerObserver.swift
//
//
//  Created by Michael on 31/1/2023.
//

import Combine
import AVFoundation

public class PlayerObserver: ObservableObject {
    
    @Published
    public private(set) var currentDate: Date?
    
    @Published
    public private(set) var playhead: Double?
    
    @Published
    public private(set) var interstitialStartDate: Double?
    
    @Published
    public private(set) var elapsedTimeInInterstitial: Double?
    
    private var interstitialPlayer: AVPlayer?
    
    private var currentAdItems: [(AVAsset, CMTime)] = []
    
    private var primaryPlayheadObservation: Any?
    
    private var interstitialPlayheadObservation: Any?
    
    public func setPlayer(_ player: AVPlayer) {
        setPrimaryPlayheadObservation(player)
        
        let interstitialMonitor = AVPlayerInterstitialEventMonitor(primaryPlayer: player)
        
        interstitialPlayer = interstitialMonitor.interstitialPlayer
        
        addObserverForCurrentInterstitialEvent(interstitialMonitor)
        
        setInterstitialPlayheadObservation(interstitialMonitor)
    }
    
    private func setPrimaryPlayheadObservation(_ player: AVPlayer) {
        primaryPlayheadObservation = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .global(),
            using: { _ in
                if let currentTime = player.currentItem?.currentDate()?.timeIntervalSince1970,
                   self.interstitialPlayer?.timeControlStatus != .playing {
                    DispatchQueue.main.async {
                        self.playhead = currentTime * 1_000
                        self.currentDate = Date.now
                    }
                }
            })
    }
    
    private func addObserverForCurrentInterstitialEvent(_ monitor: AVPlayerInterstitialEventMonitor) {
        NotificationCenter.default.addObserver(
            forName: AVPlayerInterstitialEventMonitor.currentEventDidChangeNotification,
            object: monitor,
            queue: nil) { notification in
                let currentEvent = monitor.currentEvent
                self.currentAdItems = currentEvent?.templateItems.map({ item in
                    return (item.asset, item.asset.duration)
                }) ?? []
            }
    }
    
    private func setInterstitialPlayheadObservation(_ monitor: AVPlayerInterstitialEventMonitor) {
        interstitialPlayheadObservation = monitor.interstitialPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .global(),
            using: { _ in
                guard let interstitialStartDate = monitor.currentEvent?.date?.timeIntervalSince1970 else { return }
                DispatchQueue.main.async {
                    self.interstitialStartDate = interstitialStartDate * 1_000
                }
                
                guard let interstitialPlayer = self.interstitialPlayer else { return }
                
                guard interstitialPlayer.timeControlStatus == .playing else { return }
                guard let currentPlayingIndex = self.currentAdItems.firstIndex(where: { $0.0 == interstitialPlayer.currentItem?.asset }) else { return }
                
                let playedAdsTotalDuration = self.currentAdItems.enumerated()
                    .reduce(CMTime(seconds: 0, preferredTimescale: 600)) { partialResult, assetWithDuration in
                        return assetWithDuration.offset < currentPlayingIndex ? partialResult + assetWithDuration.element.1 : partialResult
                    }
                
                let elapsedTimeInInterstitial = (playedAdsTotalDuration + interstitialPlayer.currentTime()).seconds
                DispatchQueue.main.async {
                    self.elapsedTimeInInterstitial = elapsedTimeInInterstitial
                }
                
                let interstitialPlayhead = interstitialStartDate + elapsedTimeInInterstitial
                DispatchQueue.main.async {
                    self.playhead = interstitialPlayhead * 1_000
                    self.currentDate = Date.now
                }
            })
    }
    
}
