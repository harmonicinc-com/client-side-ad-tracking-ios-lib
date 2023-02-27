//
//  ClientSideAdTracker.swift
//  
//
//  Created by Michael on 27/1/2023.
//

import Foundation

public protocol ClientSideAdTracker {
    func stop() async
    func setMediaUrl(_ urlString: String) async
}
