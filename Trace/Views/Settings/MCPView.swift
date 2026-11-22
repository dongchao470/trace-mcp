//
//  MCPView.swift
//  Trace
//
//  Local MCP endpoint: status, port, self test and tool catalogue.
//

import Combine
import Foundation
import SwiftUI
import TraceCore
import UIKit

struct MCPView: View {
    @State private var preferences: TraceMCPPreferences
    @State private var portText: String
    @State private var snapshot: TraceMCPRuntimeSnapshot
    @State private var copied = false

    private let host = "app"
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init() {
        let stored = TraceMCPPreferences.load()
        _preferences = State(initialValue: stored)
        _portText = State(initialValue: String(stored.port))
        _snapshot = State(initialValue: TraceMCPServer.shared.runtimeSnapshot)
    }

    var body: some View {
        Form {
            serviceSection
            selfTestSection
            clientSection
            MCPToolListSection()
        }
        .navigationTitle("MCP Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            TraceMCPBootstrap.startIfEnabled(host: host)
            refresh()
        }
        .onReceive(timer) { _ in
            refresh()
        }
    }

    private var serviceSection: some View {
        Section {
            Toggle("Enable MCP Server", isOn: Binding(
                get: { preferences.enabled },
                set: { toggle($0) }
            ))

            HStack {
                Text("Status")
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Port")
                Spacer()
                TextField("6180", text: $portText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 96)
                    .onSubmit(applyPort)
                    .disabled(!preferences.enabled)
            }

            if preferences.enabled, (Int(portText) ?? 0) != Int(preferences.port) {
                Button("Apply Port", action: applyPort)
            }

            HStack {
                Text("Endpoint")
                Spacer()
                Text(endpoint)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let error = snapshot.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Service")
        } footer: {
            Text("Trace only answers 127.0.0.1 requests. The app serves the endpoint while it stays active; keep the VPN tunnel running so background requests are answered by the extension.")
        }
    }

    private var selfTestSection: some View {
        Section {
            Button {
                TraceMCPServer.shared.runSelfCheck()
                refresh()
            } label: {
                Label("Test Loopback Connection", systemImage: "bolt.horizontal")
            }

            if let result = snapshot.selfCheck {
                Text(result)
                    .font(.footnote)
                    .textSelection(.enabled)
            }

            if let peer = snapshot.lastPeer {
                Text(verbatim: "Last peer: \(peer) · \(snapshot.connections)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Self Test")
        }
    }

    private var clientSection: some View {
        Section {
            Text(endpoint)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)

            Button {
                copyEndpoint()
            } label: {
                Label(copied ? "Copied" : "Copy Endpoint", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
        } header: {
            Text("Client")
        } footer: {
            Text("Add the URL above as an HTTP MCP server in SiriAI or another MCP client, then reload its tool list.")
        }
    }

    private var endpoint: String {
        "http://127.0.0.1:\(preferences.port)/mcp"
    }

    private var statusText: String {
        guard preferences.enabled else {
            return String(localized: "Disabled")
        }
        return snapshot.listening ? String(localized: "Listening") : String(localized: "Stopped")
    }

    private var statusColor: Color {
        guard preferences.enabled else {
            return .secondary
        }
        return snapshot.listening ? .green : .orange
    }

    private func toggle(_ enabled: Bool) {
        preferences = TraceMCPBootstrap.setEnabled(enabled, host: host)
        refresh()
    }

    private func applyPort() {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        guard let port = UInt16(trimmed), port >= 1024 else {
            portText = String(preferences.port)
            return
        }
        preferences = TraceMCPBootstrap.setPort(port, host: host)
        portText = String(preferences.port)
        refresh()
    }

    private func copyEndpoint() {
        UIPasteboard.general.string = endpoint
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private func refresh() {
        var current = TraceMCPServer.shared.runtimeSnapshot
        if current.selfCheck == nil, let stored = TraceMCPStatusStore.loadLastSnapshot() {
            current = stored
        }
        snapshot = current
    }
}
