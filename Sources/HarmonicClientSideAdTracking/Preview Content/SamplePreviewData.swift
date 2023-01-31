//
//  SamplePreviewData.swift
//  ClientSideAdTrackingDemo
//
//  Created by Michael on 27/1/2023.
//

import Foundation

let sampleMediaUrl = "http://10.50.110.66:20202/variant/v1/dai/HLS/Live/channel(c071e4fd-e7cd-4312-e884-d7546870490e)/variant.m3u8"
let sampleManifestUrl = "http://10.50.110.66:20202/variant/v1/dai/HLS/Live/channel(c071e4fd-e7cd-4312-e884-d7546870490e)/variant.m3u8?sessid=06a09dac-0815-4aa2-a5aa-4ea71a25ba9e"
let sampleAdTrackingMetadataUrl = "http://10.50.110.66:20202/variant/v1/dai/HLS/Live/channel(c071e4fd-e7cd-4312-e884-d7546870490e)/metadata?sessid=06a09dac-0815-4aa2-a5aa-4ea71a25ba9e"
let sampleSession = Session(sessionInfo: SessionInfo(mediaUrl: sampleMediaUrl,
                                                     manifestUrl: sampleManifestUrl,
                                                     adTrackingMetadataUrl: sampleAdTrackingMetadataUrl))

var sampleAdBeacon = loadMetdataSample("sample-metadata.json")
    
private func loadMetdataSample(_ filename: String) -> AdBeacon? {
    let data: Data
    
    guard let file = Bundle.module.url(forResource: filename, withExtension: nil) else {
        fatalError("Couldn't find \(filename) in main bundle.")
    }
    
    do {
        data = try Data(contentsOf: file)
    } catch {
        fatalError("Couldn't load \(filename) from main bundle:\n\(error)")
    }
    
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    
    do {
        return try decoder.decode(AdBeacon.self, from: data)
    } catch {
        fatalError("Couldn't parse \(filename) as \(AdBeacon.self):\n\(error)")
    }
}
