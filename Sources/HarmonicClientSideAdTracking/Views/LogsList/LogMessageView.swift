//
//  LogMessageView.swift
//
//
//  Created by Michael on 15/5/2023.
//

import SwiftUI

struct LogMessageView: View {
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss.SSS"
        return formatter
    }()
    
    let logMessage: LogMessage
    
    var body: some View {
        List {
            VStack(alignment: .leading) {
                Text("Timestamp")
                    .font(.caption2)
                Text(dateFormatter.string(from: Date(timeIntervalSince1970: logMessage.timeStamp)))
                    .font(.system(.footnote, design: .monospaced))
            }
            VStack(alignment: .leading) {
                Text("Log message")
                    .font(.caption2)
                Text(logMessage.message)
                    .foregroundColor(logMessage.isError ? .red : .primary)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
    }
}

struct LogMessageView_Previews: PreviewProvider {
    static var previews: some View {
        LogMessageView(logMessage: LogMessage(timeStamp: Date().timeIntervalSince1970, message: "sample message"))
    }
}
