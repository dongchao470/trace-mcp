//
//  RequestTimelineCard.swift
//  Trace
//
//  KPI strip and timing waterfall for the request detail overview.
//

import SwiftUI
import TraceCore
import TraceUI

struct RequestTimelineCard: View {
    let request: NetworkRequest

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                kpi(title: "耗时", value: Self.formatDuration(request.duration), tint: durationTint)
                kpi(title: "大小", value: DesignSystem.formattedBytes(request.responseBody.totalSize), tint: .primary)
                kpi(title: "TTFB", value: ttfbText, tint: ttfbTint)
            }

            if let phases = request.timingPhases, phases.hasData, let total = totalDuration(phases), total > 0 {
                SectionCard(title: "时间线", systemImage: "chart.bar.xaxis") {
                    VStack(spacing: 8) {
                        bar("DNS", phases.dnsLookup, total: total, color: .cyan)
                        bar("TCP", phases.tcpConnection, total: total, color: .blue)
                        bar("TLS", phases.tlsHandshake, total: total, color: .purple)
                        bar("请求", phases.requestSent, total: total, color: .teal)
                        bar("等待", phases.ttfb, total: total, color: waitColor(phases.ttfb))
                        bar("下载", phases.contentDownload, total: total, color: .green)
                    }
                }
            }
        }
    }

    // MARK: - KPI

    private func kpi(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var durationTint: Color {
        if request.duration >= 5 { return DesignSystem.Colors.danger }
        if request.duration >= 2 { return DesignSystem.Colors.warning }
        return .primary
    }

    private var ttfbTint: Color {
        guard let ttfb = request.timingPhases?.ttfb else { return .secondary }
        if ttfb >= 2 { return DesignSystem.Colors.danger }
        if ttfb >= 1 { return DesignSystem.Colors.warning }
        return .primary
    }

    private var ttfbText: String {
        guard let ttfb = request.timingPhases?.ttfb else { return "—" }
        return Self.formatDuration(ttfb)
    }

    private func waitColor(_ ttfb: TimeInterval?) -> Color {
        guard let ttfb else { return .gray }
        if ttfb >= 2 { return DesignSystem.Colors.danger }
        if ttfb >= 1 { return DesignSystem.Colors.warning }
        return DesignSystem.Colors.success
    }

    // MARK: - Waterfall

    private func bar(_ label: String, _ value: TimeInterval?, total: TimeInterval, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    if let value, value > 0 {
                        Capsule()
                            .fill(color)
                            .frame(width: max(3, geometry.size.width * CGFloat(min(value / total, 1))))
                    }
                }
            }
            .frame(height: 8)

            Text(Self.formatDuration(value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func totalDuration(_ phases: NetworkTimingPhases) -> TimeInterval? {
        let total = phases.total
        return total > 0 ? total : nil
    }

    // MARK: - Formatting

    static func formatDuration(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        if value < 1 {
            return String(format: "%.0f ms", value * 1000)
        }
        return String(format: "%.2f s", value)
    }
}
