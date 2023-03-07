//
//  ClientSideAdTracker.swift
//  
//
//  Created by Michael on 27/1/2023.
//

import Foundation

public protocol ClientSideAdTracker {
    func start() async
    func stop() async
    func setMediaUrl(_ urlString: String) async
}
