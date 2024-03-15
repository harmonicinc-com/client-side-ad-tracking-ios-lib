//
//  MetadataType.swift
//
//
//  Created by Michael on 15/3/2024.
//

import Foundation

public enum MetadataType: String, Decodable, CaseIterable, Identifiable {
    public var id: Self { self }
    case full = "Full"
    case latestOnly = "Latest Only"
}
