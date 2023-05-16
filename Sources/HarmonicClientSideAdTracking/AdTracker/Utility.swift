//
//  Utility.swift
//  
//
//  Created by Michael on 9/5/2023.
//

import Foundation
import os

public struct Utility {
    private static let AD_TRACKING_METADATA_FILE_NAME = "metadata"
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    @MainActor
    public static func log(_ message: String, to session: AdBeaconingSession?, level: LogLevel, with logger: Logger) {
        if let session = session {
            let isError = (level == .error || level == .warning)
            session.logMessages.append(LogMessage(timeStamp: Date().timeIntervalSince1970, message: message, isError: isError))
        }
        
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        }
    }
    
    static func makeRequest(to urlString: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else {
            let errorMessage = "Invalid URL: \(urlString)"
            throw HarmonicAdTrackerError.networkError(errorMessage)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            let errorMessage = "Cannot cast URLResponse as HTTPURLResponse for URL: \(urlString)"
            throw HarmonicAdTrackerError.networkError(errorMessage)
        }
        if !(200...299 ~= httpResponse.statusCode) {
            let errorMessage = "Invalid response status: \(httpResponse.statusCode) for URL: \(urlString); The response is: \(String(data: data, encoding: .utf8) ?? "(nil)")"
            throw HarmonicAdTrackerError.networkError(errorMessage)
        }
        return (data, httpResponse)
    }
    
    static func rewriteToMetadataUrl(from url: String) -> String {
        return url.replacingOccurrences(of: "\\/[^\\/?]+(\\??[^\\/]*)$",
                                        with: "/\(AD_TRACKING_METADATA_FILE_NAME)$1",
                                        options: .regularExpression)
    }
    
    static func timeIsIn(_ range: DataRange, for time: Double, endOffset: Double) -> Bool {
        guard let start = range.start, let end = range.end else { return false }
        return start...(end - endOffset) ~= time
    }
    
    static func playheadIsIncludedIn(_ adPods: [AdBreak], for playhead: Double, startTolerance: Double, endTolerance: Double) -> Bool {
        for adPod in adPods {
            if let start = adPod.startTime, let duration = adPod.duration {
                let startWithTolerance = start - startTolerance
                let endWithTolerance = start + duration + endTolerance
                if startWithTolerance...endWithTolerance ~= playhead {
                    return true
                }
            }
        }
        
        return false
    }
    
    static func trackingEventIsIn(_ ranges: [DataRange], for trackingEvent: TrackingEvent, with endTolerance: Double) -> Bool {
        guard let startTime = trackingEvent.startTime,
              let duration = trackingEvent.duration else {
            return false
        }
        let trackingEventRange = DataRange(start: startTime, end: startTime + max(duration + endTolerance, endTolerance))
        for range in ranges {
            if trackingEventRange.overlaps(range) {
                return true
            }
        }
        return false
    }
    
    static func getFormattedString(from date: Double) -> String {
        return getFormattedString(from: Date(timeIntervalSince1970: date / 1_000))
    }
    
    static func getFormattedString(from date: Date) -> String {
        return dateFormatter.string(from: date)
    }
}
