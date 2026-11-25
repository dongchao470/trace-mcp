//
//  FormBodyView.swift
//  TraceUI
//
//  application/x-www-form-urlencoded 的键值视图：解码百分号转义，嵌套 JSON 可展开。
//

import Foundation
import SwiftUI

public enum FormBodyParser {
    public static func pairs(_ text: String) -> [(key: String, value: String)] {
        text
            .split(separator: "&", omittingEmptySubsequences: true)
            .map { chunk in
                let parts = chunk.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let rawKey = String(parts[0])
                let rawValue = parts.count > 1 ? String(parts[1]) : ""
                return (decode(rawKey), decode(rawValue))
            }
    }

    public static func decode(_ value: String) -> String {
        let plusDecoded = value.replacingOccurrences(of: "+", with: " ")
        guard let decoded = plusDecoded.removingPercentEncoding else { return plusDecoded }
        // 有些服务端会二次编码，再试一次且只在结果仍是合法 JSON 前缀时采用
        if decoded.contains("%7B") || decoded.contains("%5B"),
           let second = decoded.removingPercentEncoding,
           second.hasPrefix("{") || second.hasPrefix("[") {
            return second
        }
        return decoded
    }

    public static func prettyJSON(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              )
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}

public struct FormBodyView: View {
    public let text: String
    @State private var expandedKeys: Set<String> = []

    public init(text: String) {
        self.text = text
    }

    private var pairs: [(key: String, value: String)] {
        FormBodyParser.pairs(text)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Form（\(pairs.count) 个字段）")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                if index > 0 { Divider() }
                row(for: pair)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(for pair: (key: String, value: String)) -> some View {
        let pretty = FormBodyParser.prettyJSON(pair.value)
        let isExpanded = expandedKeys.contains(pair.key)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(pair.key)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 108, alignment: .leading)

                Text(pair.value.isEmpty ? "（空）" : pair.value)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if pretty != nil {
                    Button {
                        if isExpanded {
                            expandedKeys.remove(pair.key)
                        } else {
                            expandedKeys.insert(pair.key)
                        }
                    } label: {
                        Text("JSON")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isExpanded, let pretty {
                ScrollView(.vertical) {
                    Text(pretty)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 260)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .padding(.leading, 118)
            }
        }
        .padding(.vertical, 6)
    }
}
