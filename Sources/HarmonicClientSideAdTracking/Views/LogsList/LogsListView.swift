//
//  LogsListView.swift
//
//
//  Created by Michael on 12/5/2023.
//

import SwiftUI

public struct LogsListView: View {
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return formatter
    }()
    
    @ObservedObject var session: AdBeaconingSession
    @State var filterErrors = false
    
    @Environment(\.dismiss)
    private var dismiss
    
    public init(session: AdBeaconingSession) {
        self.session = session
    }
    
    public var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                Toggle("Show errors only", isOn: $filterErrors)
                    .font(.caption2)
                    .padding()
                List {
                    ForEach(session.logMessages.filter { filterErrors ? $0.isError : true }) { logMessage in
                        NavigationLink(destination: LogMessageView(logMessage: logMessage)) {
                            VStack(alignment: .leading) {
                                Text(dateFormatter.string(from: Date(timeIntervalSince1970: logMessage.timeStamp)))
                                    .font(.caption2)
                                Text(logMessage.message)
                                    .font(.footnote)
                                    .lineLimit(2)
                                    .foregroundColor(logMessage.isError ? .red : .primary)
                            }
                        }
                    }
                }
                Spacer()
            }
            .navigationTitle("Logs")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Dismiss") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LogMessagesView_Previews: PreviewProvider {
    static var previews: some View {
        LogsListView(session: AdBeaconingSession())
    }
}
