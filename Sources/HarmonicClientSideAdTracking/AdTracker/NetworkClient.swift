//
//  NetworkClient.swift
//  
//
//  Created by Michael on 2/1/2026.
//

import Foundation

/// Protocol for making network requests, allowing for dependency injection and mocking in tests.
public protocol NetworkClientProtocol: Sendable {
    /// Makes a simple GET request to the given URL string.
    /// - Parameter urlString: The URL string to make the request to.
    /// - Returns: A tuple containing the response data and HTTP response.
    func makeRequest(to urlString: String) async throws -> (Data, HTTPURLResponse)
    
    /// Makes an init request (GET with query param, or POST fallback) to initialize a session.
    /// - Parameter urlString: The URL string to make the init request to.
    /// - Returns: The parsed InitResponse containing manifest and tracking URLs.
    func makeInitRequest(to urlString: String) async throws -> InitResponse
}

/// Default implementation using URLSession
public struct URLSessionNetworkClient: NetworkClientProtocol {
    public init() {}
    
    public func makeRequest(to urlString: String) async throws -> (Data, HTTPURLResponse) {
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
    
    public func makeInitRequest(to urlString: String) async throws -> InitResponse {
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
                
                guard let manifestUrl = URL(string: initResponse.manifestUrl, relativeTo: httpResponse.url)?.absoluteString,
                      let trackingUrl = URL(string: initResponse.trackingUrl, relativeTo: httpResponse.url)?.absoluteString else {
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
        
        guard let manifestUrl = URL(string: initResponse.manifestUrl, relativeTo: httpResponse.url)?.absoluteString,
              let trackingUrl = URL(string: initResponse.trackingUrl, relativeTo: httpResponse.url)?.absoluteString else {
            let errorMessage = "Failed to create new URLs from init response"
            throw HarmonicAdTrackerError.networkError(errorMessage)
        }
        
        return InitResponse(manifestUrl: manifestUrl, trackingUrl: trackingUrl)
    }
}
