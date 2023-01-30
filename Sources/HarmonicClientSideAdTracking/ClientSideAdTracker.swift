//
//  ClientSideAdTracker.swift
//  
//
//  Created by Michael on 27/1/2023.
//

import Foundation

public protocol ClientSideAdTracker {
    func updatePods(_ pods: [AdBreak]?)
    func getAdPods() -> [AdBreak]
    func getPlayheadTime() -> Double
    func needSendBeacon(time: Double) async
}
