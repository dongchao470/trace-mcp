//
//  CookiesSection.swift
//  Trace
//
//  Cookie 专用键值视图：请求侧 Cookie 与响应侧 Set-Cookie 分开呈现。
//

import SwiftUI
import TraceCore
import TraceUI
import UIKit

struct CookiePair: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let attributes: [CookieAttribute]
}

struct CookieAttribute: Identifiable {
    let id = UUID()
    let name: String
    let value: String?
}

enum CookieParser {
    static func requestCookies(in headers: [TraceHTTPHeader]) -> [CookiePair] {
        var cookies: [CookiePair] = []
        for header in headers where header.key.caseInsensitiveCompare("Cookie") == .orderedSame {
            for chunk in header.value.split(separator: ";") {
                let trimmed = chunk.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(parts[0])
                let value = parts.count > 1 ? String(parts[1]) : ""
                cookies.append(CookiePair(name: name, value: value, attributes: []))
            }
        }
        return cookies
    }

    static func responseCookies(in headers: [TraceHTTPHeader]) -> [CookiePair] {
        var cookies: [CookiePair] = []
        for header in headers where header.key.caseInsensitiveCompare("Set-Cookie") == .orderedSame {
            let parts = header.value
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = parts.first, !first.isEmpty else { continue }
            let head = first.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(head[0])
            let value = head.count > 1 ? String(head[1]) : ""

            var attributes: [CookieAttribute] = []
            for part in parts.dropFirst() where !part.isEmpty {
                let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(kv[0])
                let attrValue = kv.count > 1 ? String(kv[1]) : nil
                attributes.append(CookieAttribute(name: key, value: attrValue))
            }
            cookies.append(CookiePair(name: name, value: value, attributes: attributes))
        }
        return cookies
    }
}

struct CookiesSection: View {
    let request: NetworkRequest
    @State private var copiedCookie: String?

    private var requestCookies: [CookiePair] {
        CookieParser.requestCookies(in: request.requestHeaders)
    }

    private var responseCookies: [CookiePair] {
        CookieParser.responseCookies(in: request.responseHeaders)
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            if requestCookies.isEmpty && responseCookies.isEmpty {
                TraceContentUnavailableView(
                    "No Cookies",
                    systemImage: "circle.dashed",
                    description: Text("这个请求没有 Cookie，响应也没有 Set-Cookie")
                )
            } else {
                if !requestCookies.isEmpty {
                    SectionCard(title: "请求 Cookie（\(requestCookies.count)）", systemImage: "arrow.up.circle") {
                        VStack(spacing: 0) {
                            ForEach(Array(requestCookies.enumerated()), id: \.element.id) { index, cookie in
                                if index > 0 { Divider() }
                                cookieRow(cookie, showsAttributes: false)
                            }
                        }
                    }
                }

                if !responseCookies.isEmpty {
                    SectionCard(title: "响应 Set-Cookie（\(responseCookies.count)）", systemImage: "arrow.down.circle") {
                        VStack(spacing: 0) {
                            ForEach(Array(responseCookies.enumerated()), id: \.element.id) { index, cookie in
                                if index > 0 { Divider() }
                                cookieRow(cookie, showsAttributes: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cookieRow(_ cookie: CookiePair, showsAttributes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(cookie.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 108, alignment: .leading)

                Text(cookie.value.isEmpty ? "（空值）" : cookie.value)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsAttributes && !cookie.attributes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(cookie.attributes) { attribute in
                            Text(attributeLabel(attribute))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color(.tertiarySystemFill))
                                )
                        }
                    }
                    .padding(.leading, 118)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            UIPasteboard.general.string = "\(cookie.name)=\(cookie.value)"
            copiedCookie = cookie.name
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if copiedCookie == cookie.name { copiedCookie = nil }
            }
        }
        .overlay(alignment: .trailing) {
            if copiedCookie == cookie.name {
                Text("已复制")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.success)
            }
        }
    }

    private func attributeLabel(_ attribute: CookieAttribute) -> String {
        guard let value = attribute.value else { return attribute.name }
        return "\(attribute.name)=\(value)"
    }
}
