//
//  PlayerObserver.swift
//
//
//  Created by Michael on 31/1/2023.
//

import AVFoundation
import Combine
import os

@MainActor
public class PlayerObserver: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.module.bundleIdentifier!,
        category: String(describing: PlayerObserver.self)
    )
    
    @Published
    public private(set) var currentDate: Date?
    
    @Published
    public private(set) var playhead: Double?
    
    @Published
    public private(set) var primaryStatus: AVPlayer.TimeControlStatus?
    
    @Published
    public private(set) var interstitialStatus: AVPlayer.TimeControlStatus?
    
    @Published
    public private(set) var interstitialStartDate: Double?
    
    @Published
    public private(set) var interstitialStoppedDate: Double?
    
    @Published
    public private(set) var elapsedTimeInInterstitial: Double?
    
    @Published
    public private(set) var currentInterstitialDuration: Double?
    
    @Published
    public private(set) var hasInterstitialEvents: Bool = false
    
    public private(set) var interstitialPlayer: AVQueuePlayer?
    
    private var currentInterstitialItems: [(AVAsset, CMTime)] = []
    
    private var currentDateTimer: AnyCancellable?
    
    private var primaryPlayheadObservation: Any?
    
    private var primaryPlayerStatusObservation: AnyCancellable?
    
    private var interstitialPlayheadObservation: Any?
    
    private var interstitialEventsObservation: AnyCancellable?
    
    private var currentInterstitialEventObservation: AnyCancellable?
    
    private var interstitialPlayerStatusObservation: AnyCancellable?
    
    public init() {}
    
    public func setPlayer(_ player: AVPlayer) {
        setCurrentDateTimer()
        
        setPrimaryPlayheadObservation(player)
        
        setPrimaryPlayerStatusObservation(player)
        
        let interstitialMonitor = AVPlayerInterstitialEventMonitor(primaryPlayer: player)
        
        interstitialPlayer = interstitialMonitor.interstitialPlayer
        
        setInterstitialPlayerStatusObservation(interstitialMonitor.interstitialPlayer)
        
        addObserverForInterstitialEvents(interstitialMonitor)
        
        addObserverForCurrentInterstitialEvent(interstitialMonitor)
        
        setInterstitialPlayheadObservation(interstitialMonitor)
    }
    
    private func setCurrentDateTimer() {
        currentDateTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
            .sink { [weak self] date in
                guard let self = self else { return }
                self.currentDate = date
            }
    }
    
    private func setPrimaryPlayheadObservation(_ player: AVPlayer) {
        primaryPlayheadObservation = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .global(),
            using: { [weak self] _ in
                guard let self = self else { return }
                if let currentTime = player.currentItem?.currentDate()?.timeIntervalSince1970,
                   self.interstitialPlayer?.timeControlStatus != .playing {
                    DispatchQueue.main.async {
                        self.playhead = currentTime * 1_000
                    }
                }
            })
    }
    
    private func setPrimaryPlayerStatusObservation(_ player: AVPlayer) {
        primaryPlayerStatusObservation = player.publisher(for: \.timeControlStatus)
            .sink(receiveValue: { [weak self] newStatus in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.primaryStatus = newStatus
                }
            })
    }
    
    private func addObserverForInterstitialEvents(_ monitor: AVPlayerInterstitialEventMonitor) {
        interstitialEventsObservation = NotificationCenter.default.publisher(
            for: AVPlayerInterstitialEventMonitor.eventsDidChangeNotification,
            object: monitor)
        .sink(receiveValue: { [weak self] _ in
            guard let self = self else { return }
            if !self.hasInterstitialEvents && !monitor.events.isEmpty {
                DispatchQueue.main.async {
                    self.hasInterstitialEvents = true
                }
            }
        })
    }
    
    private func addObserverForCurrentInterstitialEvent(_ monitor: AVPlayerInterstitialEventMonitor) {
        currentInterstitialEventObservation = NotificationCenter.default.publisher(
            for: AVPlayerInterstitialEventMonitor.currentEventDidChangeNotification,
            object: monitor)
        .sink(receiveValue: { [weak self] _ in
            guard let self = self else { return }
            let currentEvent = monitor.currentEvent
            Task {
                let currentEventItems = (currentEvent?.templateItems ?? []).map({ item in
                    return (item.asset, item.asset.duration)
                })
                await self.setInterstitialItems(currentEventItems)
                if self.currentInterstitialItems.isEmpty {
                    let interstitialPlayerItems = (self.interstitialPlayer?.items() ?? []).map({ item in
                        return (item.asset, item.asset.duration)
                    })
                    if !interstitialPlayerItems.isEmpty {
                        Self.logger.warning("No ads found in current event of the interstitial monitor, using the interstital player's queued ads instead.")
                        await self.setInterstitialItems(interstitialPlayerItems)
                    }
                }
            }
        })
    }
    
    private func setInterstitialItems(_ adItems: [(AVAsset, CMTime)]) async {
        self.currentInterstitialItems = adItems
        if !adItems.isEmpty {
            self.currentInterstitialDuration = (adItems.reduce(0) { $0 + $1.1.seconds }) * 1_000
        }
    }
    
    private func setInterstitialPlayerStatusObservation(_ interstitialPlayer: AVPlayer) {
        interstitialPlayerStatusObservation = interstitialPlayer.publisher(for: \.timeControlStatus)
            .sink(receiveValue: { [weak self] newStatus in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.interstitialStatus = newStatus
                    if newStatus == .paused {
                        self.interstitialStoppedDate = self.playhead
                    }
                }
            })
    }
    
    private func setInterstitialPlayheadObservation(_ monitor: AVPlayerInterstitialEventMonitor) {
        interstitialPlayheadObservation = monitor.interstitialPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .global(),
            using: { [weak self] _ in
                guard let self = self else { return }
                guard let interstitialStartDate = monitor.currentEvent?.date?.timeIntervalSince1970 else { return }
                DispatchQueue.main.async {
                    self.interstitialStartDate = interstitialStartDate * 1_000
                }
                
                guard let interstitialPlayer = self.interstitialPlayer else { return }
                
                guard interstitialPlayer.timeControlStatus == .playing else { return }
                guard let currentPlayingIndex = self.currentInterstitialItems.firstIndex(where: { $0.0 == interstitialPlayer.currentItem?.asset }) else {
                    Self.logger.warning("Cannot find current interstitial item in list.")
                    return
                }
                
                let playedAdsTotalDuration = self.currentInterstitialItems.enumerated()
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
                }
            })
    }
    
}
