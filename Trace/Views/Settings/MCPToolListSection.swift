//
//  MCPToolListSection.swift
//  Trace
//
//  Tool catalogue for the loopback MCP endpoint.
//

import SwiftUI
import TraceCore

struct MCPToolListSection: View {
    private let tools = TraceMCPDispatcher.shared.tools

    var body: some View {
        Section {
            ForEach(tools, id: \.name) { tool in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .font(.system(.footnote, design: .monospaced))
                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Tools")
        }
    }
}
