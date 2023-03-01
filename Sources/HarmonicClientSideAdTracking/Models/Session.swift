//
//  Session.swift
//  
//
//  Created by Michael on 19/1/2023.
//

import Foundation
import Combine

public class Session: ObservableObject {
    @Published
    public var sessionInfo: SessionInfo
    
    @Published
    public var automaticallyPreservesTimeOffsetFromLive: Bool = false
    
    public init(sessionInfo: SessionInfo = SessionInfo()) {
        self.sessionInfo = sessionInfo
    }
}
