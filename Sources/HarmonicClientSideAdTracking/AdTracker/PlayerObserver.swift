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
    
    var session: AdBeaconingSession?
    
    @Published public private(set) var currentDate: Date?
    
    @Published public private(set) var playhead: Double?
    @Published public private(set) var primaryStatus: AVPlayer.TimeControlStatus?
    
    @Published public private(set) var hasInterstitialEvents: Bool = false
    @Published public private(set) var interstitialStatus: AVPlayer.TimeControlStatus?
    @Published public private(set) var interstitialDate: Double?
    @Published public private(set) var interstitialStoppedDate: Double?
    @Published public private(set) var interstitialStartTime: Double?
    @Published public private(set) var interstitialStopTime: Double?
    @Published public private(set) var currentInterstitialDuration: Double?
    
    private var interstitialPlayer: AVQueuePlayer?
    private var currentInterstitialItems: [(AVAsset, CMTime)] = []
    
    private var currentDateTimer: AnyCancellable?
    
    private var primaryPlayheadObservation: Any?
    private var primaryPlayerStatusObservation: AnyCancellable?
    
    private var interstitialPlayheadObservation: Any?
    private var interstitialEventsObservation: AnyCancellable?
    private var currentInterstitialEventObservation: AnyCancellable?
    private var interstitialPlayerStatusObservation: AnyCancellable?
    
    init() {}
    
    /// Sets the playhead value. Intended for testing purposes only.
    /// - Parameter value: The playhead value in milliseconds
    internal func setPlayhead(_ value: Double?) {
        self.playhead = value
    }
    
    func setSession(_ session: AdBeaconingSession) {
        let player = session.player
        
        resetObservations()
        
        setCurrentDateTimer()
        
        setPrimaryPlayheadObservation(player)
        setPrimaryPlayerStatusObservation(player)
        
        let interstitialMonitor = AVPlayerInterstitialEventMonitor(primaryPlayer: player)
        hasInterstitialEvents = !interstitialMonitor.events.isEmpty
        interstitialPlayer = interstitialMonitor.interstitialPlayer
        
        setInterstitialPlayerStatusObservation(interstitialMonitor.interstitialPlayer)
        addObserverForInterstitialEvents(interstitialMonitor)
        checkForInterstitialItems(with: interstitialMonitor)
        addObserverForCurrentInterstitialEvent(interstitialMonitor)
        setInterstitialPlayheadObservation(interstitialMonitor)
    }
    
    public func resetObservations() {
        currentDateTimer?.cancel()
        
        // Remove time observers before setting to nil
        if let observer = primaryPlayheadObservation {
            session?.player.removeTimeObserver(observer)
        }
        primaryPlayheadObservation = nil
        
        if let observer = interstitialPlayheadObservation,
           let player = interstitialPlayer {
            player.removeTimeObserver(observer)
        }
        interstitialPlayheadObservation = nil
        
        primaryPlayerStatusObservation?.cancel()
        interstitialEventsObservation?.cancel()
        currentInterstitialEventObservation?.cancel()
        interstitialPlayerStatusObservation?.cancel()
        
        // Clear references
        interstitialPlayer = nil
        currentInterstitialItems = []
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
    
    private func checkForInterstitialItems(with monitor: AVPlayerInterstitialEventMonitor) {
        let currentEvent = monitor.currentEvent
        Task {
            let currentEventItems = (currentEvent?.templateItems ?? []).map({ item in
                return (item.asset, item.asset.duration)
            })
            await setInterstitialItems(currentEventItems)
            if currentInterstitialItems.isEmpty {
                let interstitialPlayerItems = (interstitialPlayer?.items() ?? []).map({ item in
                    return (item.asset, item.asset.duration)
                })
                if !interstitialPlayerItems.isEmpty {
                    Utility.log("No ads found in current event of the interstitial monitor, using the interstital player's queued ads instead.",
                                to: session, level: .error, with: Self.logger)
                    await setInterstitialItems(interstitialPlayerItems)
                }
            }
        }
    }
    
    private func addObserverForCurrentInterstitialEvent(_ monitor: AVPlayerInterstitialEventMonitor) {
        currentInterstitialEventObservation = NotificationCenter.default.publisher(
            for: AVPlayerInterstitialEventMonitor.currentEventDidChangeNotification,
            object: monitor)
        .sink(receiveValue: { [weak self] _ in
            guard let self = self else { return }
            self.checkForInterstitialItems(with: monitor)
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
                }
                if newStatus == .paused {
                    if let interstitialDate = self.interstitialDate, let interstitialStopTime = self.interstitialStopTime {
                        DispatchQueue.main.async {
                            self.interstitialStoppedDate = interstitialDate + interstitialStopTime * 1_000
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.interstitialStoppedDate = self.playhead
                        }
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
                guard let interstitialDate = monitor.currentEvent?.date?.timeIntervalSince1970 else { return }
                DispatchQueue.main.async {
                    self.interstitialDate = interstitialDate * 1_000
                }
                
                guard let interstitialPlayer = self.interstitialPlayer else { return }
                
                guard interstitialPlayer.timeControlStatus == .playing else { return }
                guard let currentPlayingIndex = self.currentInterstitialItems.firstIndex(where: { $0.0 == interstitialPlayer.currentItem?.asset }) else {
                    Utility.log("Cannot find current interstitial item in list.",
                                to: self.session, level: .warning, with: Self.logger)
                    return
                }
                
                let playedAdsTotalDuration = self.currentInterstitialItems.enumerated()
                    .reduce(CMTime(seconds: 0, preferredTimescale: 600)) { partialResult, assetWithDuration in
                        return assetWithDuration.offset < currentPlayingIndex ? partialResult + assetWithDuration.element.1 : partialResult
                    }
                
                let interstitialStopTime = (playedAdsTotalDuration + interstitialPlayer.currentTime()).seconds
                self.setInterstitalStartAndStopTimes(interstitialStopTime: interstitialStopTime)
                
                let interstitialPlayhead = interstitialDate + interstitialStopTime
                DispatchQueue.main.async {
                    self.playhead = interstitialPlayhead * 1_000
                }
            })
    }
    
    private func setInterstitalStartAndStopTimes(interstitialStopTime: Double) {
        if let lastInterstitialStopTime = self.interstitialStopTime,
           interstitialStopTime < lastInterstitialStopTime {
            DispatchQueue.main.async {
                self.interstitialStartTime = interstitialStopTime
            }
        } else if self.interstitialStopTime == nil {
            DispatchQueue.main.async {
                self.interstitialStartTime = interstitialStopTime
            }
        }
        DispatchQueue.main.async {
            self.interstitialStopTime = interstitialStopTime
        }
    }
    
}
