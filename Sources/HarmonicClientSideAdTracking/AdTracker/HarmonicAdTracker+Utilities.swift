//
//  HarmonicAdTracker+Utilities.swift
//  
//
//  Created by Michael on 27/1/2023.
//

import Foundation

private let AD_TRACING_METADATA_FILE_NAME = "metadata"
private let EARLY_FETCH_MS: Double = 5_000

extension HarmonicAdTracker {
    static func makeRequestTo(_ urlString: String) async throws -> (Data, HTTPURLResponse)? {
        guard let url = URL(string: urlString) else {
            let errorMessage = "Invalid URL: \(urlString)"
            Self.logger.error("\(errorMessage, privacy: .public)")
            return nil
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            let errorMessage = "Cannot cast URLResponse as HTTPURLResponse for URL: \(urlString)"
            Self.logger.error("\(errorMessage, privacy: .public)")
            return nil
        }
        if !(200...299 ~= httpResponse.statusCode) {
            let errorMessage = "Invalid response status: \(httpResponse.statusCode) for URL: \(urlString)"
            Self.logger.error("\(errorMessage, privacy: .public)")
            return nil
        }
        return (data, httpResponse)
    }
    
    static func rewriteUrlToMetadataUrl(_ url: String) -> String {
        return url.replacingOccurrences(of: "\\/[^\\/?]+(\\??[^\\/]*)$",
                                        with: "/\(AD_TRACING_METADATA_FILE_NAME)$1",
                                        options: .regularExpression)
    }
    
    static func isInRange(time: Double?, range: DataRange) -> Bool {
        guard let time = time else { return true }
        guard let start = range.start, let end = range.end else { return false }
        return start...(end-EARLY_FETCH_MS) ~= time
    }
    
    static func getFormattedString(from date: Double) -> String {
        return getFormattedString(from: Date(timeIntervalSince1970: date / 1_000))
    }
    
    static func getFormattedString(from date: Date) -> String {
        return date.formatted(date: .omitted, time: .standard)
    }
}
