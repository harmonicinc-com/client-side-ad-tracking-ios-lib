//
//  SessionInfo.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public class SessionInfo: ObservableObject {
    public var localSessionId: String = ""
    public var mediaUrl: String = ""
    @Published public var manifestUrl: String = ""
    @Published public var adTrackingMetadataUrl: String = ""
    
    public init(localSessionId: String = "", mediaUrl: String = "", manifestUrl: String = "", adTrackingMetadataUrl: String = "") {
        self.localSessionId = localSessionId
        self.mediaUrl = mediaUrl
        self.manifestUrl = manifestUrl
        self.adTrackingMetadataUrl = adTrackingMetadataUrl
    }
}
