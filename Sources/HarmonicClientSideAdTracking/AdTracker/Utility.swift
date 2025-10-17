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
    public static func log(_ message: String, to session: AdBeaconingSession?, level: LogLevel, with logger: Logger, error: HarmonicAdTrackerError? = nil) {
        if let session = session {
            let isError = (level == .error || level == .warning)
            session.logMessages.append(LogMessage(timeStamp: Date().timeIntervalSince1970, message: message, isError: isError, error: error))
            
            // Publish error if provided
            if let error = error, isError {
                session.latestError = error
            }
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
    
    static func makeInitRequest(to urlString: String) async throws -> InitResponse {
        guard let url = URL(string: urlString) else {
            let errorMessage = "Invalid URL: \(urlString)"
            throw HarmonicAdTrackerError.networkError(errorMessage)
        }
        
        // First try GET request with initSession=true query param
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "initSession", value: "true"))
        components?.queryItems = queryItems
        
        if let getURL = components?.url {
            do {
                let (data, response) = try await URLSession.shared.data(from: getURL)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw HarmonicAdTrackerError.networkError("Cannot cast URLResponse as HTTPURLResponse for GET URL: \(getURL.absoluteString)")
                }
                guard httpResponse.statusCode == 200 else {
                    throw HarmonicAdTrackerError.networkError("Invalid response status: \(httpResponse.statusCode) for GET URL: \(getURL.absoluteString)")
                }
                
                // Try to parse as InitResponse
                let initResponse = try JSONDecoder().decode(InitResponse.self, from: data)
                
                guard let manifestUrl = URL(string: initResponse.manifestUrl, relativeTo: url)?.absoluteString,
                      let trackingUrl = URL(string: initResponse.trackingUrl, relativeTo: url)?.absoluteString else {
                    throw HarmonicAdTrackerError.networkError("Failed to create new URLs from GET init response")
                }
                
                return InitResponse(manifestUrl: manifestUrl, trackingUrl: trackingUrl)
            } catch {
                // GET request failed, continue to POST fallback
            }
        }
        
        // Fallback to POST request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            let errorMessage = "Cannot cast URLResponse as HTTPURLResponse for URL: \(urlString)"
            throw HarmonicAdTrackerError.networkError(errorMessage)
        }
        guard httpResponse.statusCode == 200 else {
            let errorMessage = "Invalid response status: \(httpResponse.statusCode) for URL: \(urlString); The response is: \(String(data: data, encoding: .utf8) ?? "(nil)")"
            throw HarmonicAdTrackerError.networkError(errorMessage)
        }
        
        let initResponse = try JSONDecoder().decode(InitResponse.self, from: data)
        
        guard let manifestUrl = URL(string: initResponse.manifestUrl, relativeTo: url)?.absoluteString,
              let trackingUrl = URL(string: initResponse.trackingUrl, relativeTo: url)?.absoluteString else {
            let errorMessage = "Failed to create new URLs from init response"
            throw HarmonicAdTrackerError.networkError(errorMessage)
        }
        
        return InitResponse(manifestUrl: manifestUrl, trackingUrl: trackingUrl)
    }
    
    static func rewriteToMetadataUrl(from url: String) -> String {
        return url.replacingOccurrences(of: "\\/[^\\/?]+(\\??[^\\/]*)$",
                                        with: "/\(AD_TRACKING_METADATA_FILE_NAME)$1",
                                        options: .regularExpression)
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
    
    static func getFormattedString(from date: Double) -> String {
        return getFormattedString(from: Date(timeIntervalSince1970: date / 1_000))
    }
    
    static func getFormattedString(from date: Date) -> String {
        return dateFormatter.string(from: date)
    }
    
    static func parseHLSMasterPlaylist(_ data: Data, baseURL: URL) -> String? {
        guard let playlistContent = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        let lines = playlistContent.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip empty lines and comment lines (except for #EXT-X-STREAM-INF)
            if trimmedLine.isEmpty || (trimmedLine.hasPrefix("#") && !trimmedLine.hasPrefix("#EXT-X-STREAM-INF")) {
                continue
            }
            
            // If this is not a comment line, it should be a media playlist URL
            if !trimmedLine.hasPrefix("#") {
                // Resolve the URL relative to the base URL
                if let resolvedURL = URL(string: trimmedLine, relativeTo: baseURL) {
                    return modifyBaseURL(baseURL: baseURL, withResolvedURL: resolvedURL)
                }
            }
        }
        
        return nil
    }
    
    private static func modifyBaseURL(baseURL: URL, withResolvedURL resolvedURL: URL) -> String {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path
        
        // Check if resolvedURL path has prefix "/pmm-"
        let resolvedPath = resolvedURL.path
        if resolvedPath.hasPrefix("/pmm-") {
            // Extract the pmm part and prepend to baseURL path
            if let pmmRange = resolvedPath.range(of: #"^/pmm-[^/]*"#, options: .regularExpression) {
                let pmmPart = String(resolvedPath[pmmRange])
                components?.path = pmmPart + (basePath ?? "")
            }
        }
        
        // Use query params from resolvedURL but remove "isstream=true"
        if let resolvedComponents = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false),
           let queryItems = resolvedComponents.queryItems {
            let filteredQueryItems = queryItems.filter { $0.name != "isstream" }
            components?.queryItems = filteredQueryItems.isEmpty ? nil : filteredQueryItems
        }
        
        return components?.url?.absoluteString ?? baseURL.absoluteString
    }
}
