//
//  DataRange.swift
//  
//
//  Created by Michael on 18/1/2023.
//

import Foundation

public class DataRange: Decodable, Hashable {
    public var start: Double?
    public var end: Double?
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    public init(start: Double?, end: Double?) {
        self.start = start
        self.end = end
    }
    
    public func overlaps(_ dataRange: DataRange?) -> Bool {
        guard let start = start,
              let end = end,
              let otherStart = dataRange?.start,
              let otherEnd = dataRange?.end else {
            return false
        }
        return start...end ~= otherStart || start...end ~= otherEnd || otherStart...otherEnd ~= start || otherStart...otherEnd ~= end
    }
    
    public func isWithin(_ dataRange: DataRange?) -> Bool {
        guard let start = start,
              let end = end,
              let otherStart = dataRange?.start,
              let otherEnd = dataRange?.end else {
            return false
        }
        return otherStart <= start && end <= otherEnd
    }
    
    public func contains(_ time: Double) -> Bool {
        guard let start = start, let end = end else { return false }
        return start...end ~= time
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(end)
    }
    
    public static func == (lhs: DataRange, rhs: DataRange) -> Bool {
        return (lhs.start ?? 0) == (rhs.start ?? 0) && (lhs.end ?? 0) == (rhs.end ?? 0)
    }
}

extension DataRange: CustomStringConvertible {
    public var description: String {
        guard let start = start, let end = end else {
            return "DataRange(nil)"
        }
        return "DataRange(start: \(Self.dateFormatter.string(from: Date(timeIntervalSince1970: start / 1_000))); "
        + "end: \(Self.dateFormatter.string(from: Date(timeIntervalSince1970: end / 1_000))))"
    }
}
