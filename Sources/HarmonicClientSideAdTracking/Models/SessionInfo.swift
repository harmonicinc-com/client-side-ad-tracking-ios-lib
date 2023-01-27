//
//  SessionInfo.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public struct SessionInfo {
    public var localSessionId: String?
    public var mediaUrl: String?
    public var manifestUrl: String?
    public var adTrackingMetadataUrl: String?
    
    public init(localSessionId: String, mediaUrl: String, manifestUrl: String, adTrackingMetadataUrl: String) {
        self.localSessionId = localSessionId
        self.mediaUrl = mediaUrl
        self.manifestUrl = manifestUrl
        self.adTrackingMetadataUrl = adTrackingMetadataUrl
    }
}
