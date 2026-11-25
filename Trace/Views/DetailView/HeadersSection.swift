//
//  HeadersSection.swift
//  Trace
//
//  Created by Justin on 2026/01/14.
//

import SwiftUI
import TraceCore
import TraceUI
import UIKit

struct HeadersSection: View {
    let headers: [TraceHTTPHeader]
    @State private var copiedKey: String?

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            if !headers.isEmpty {
                SectionCard(title: "Headers（\(headers.count)）") {
                    VStack(spacing: 0) {
                        ForEach(Array(headers.enumerated()), id: \.element.id) { index, header in
                            if index > 0 {
                                Divider()
                            }
                            row(header)
                        }
                    }
                }
            } else {
                TraceContentUnavailableView(
                    "No Headers",
                    systemImage: "list.bullet.rectangle",
                    description: Text("This request has no headers")
                )
            }
        }
    }

    private func row(_ header: TraceHTTPHeader) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(header.key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)

            Text(header.value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            UIPasteboard.general.string = "\(header.key): \(header.value)"
            copiedKey = header.key
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if copiedKey == header.key { copiedKey = nil }
            }
        }
        .overlay(alignment: .trailing) {
            if copiedKey == header.key {
                Text("已复制")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.success)
            }
        }
    }
}

#Preview("With Headers") {
    ScrollView {
        HeadersSection(headers: [
            TraceHTTPHeader(key: "Content-Type", value: "application/json"),
            TraceHTTPHeader(key: "Authorization", value: "Bearer token"),
            TraceHTTPHeader(key: "X-Request-ID", value: "abc-123")
        ])
        .padding()
    }
}

#Preview("Empty") {
    ScrollView {
        HeadersSection(headers: [])
            .padding()
    }
}
