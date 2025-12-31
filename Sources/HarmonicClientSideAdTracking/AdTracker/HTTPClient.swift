//
//  HTTPClient.swift
//  
//
//  Created by Michael on 24/12/2024.
//

import Foundation

/// Protocol for making HTTP requests, allowing for dependency injection and mocking in tests.
public protocol HTTPClientProtocol: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

/// Default implementation using URLSession
public struct URLSessionHTTPClient: HTTPClientProtocol {
    public init() {}
    
    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(from: url)
    }
}
