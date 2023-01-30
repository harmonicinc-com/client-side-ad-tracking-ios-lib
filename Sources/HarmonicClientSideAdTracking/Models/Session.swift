//
//  Session.swift
//  
//
//  Created by Michael on 19/1/2023.
//

import Foundation

public class Session: ObservableObject {
    @Published
    public var sessionInfo: SessionInfo? = nil
    
    @Published
    public var load: ((_ url: String) async -> Void)? = nil
    
    public init(sessionInfo: SessionInfo? = nil, load: ((_ url: String) -> Void)? = nil) {
        self.sessionInfo = sessionInfo
        self.load = load
    }
}
