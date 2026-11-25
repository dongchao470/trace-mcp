//
//  BodyInspectorView.swift
//  TraceUI
//
//  Created by Justin on 2026/02/06.
//

import Foundation
import ImageIO
import SwiftUI
import UIKit

/// Presents request/response body data with mode switching and type-aware rendering.
public struct BodyInspectorView: View {
    public let title: String
    public var headerSystemImage: String?
    public let content: String
    public var contentType: String?
    public var rawData: Data?
    public var fileName: String?
    public var totalSize: Int?
    public var onCopy: (() -> Void)?
    public var onShare: (() -> Void)?

    @State private var viewMode: ViewMode = .auto
    @State private var previewImageItem: PreviewImageItem?
    @State private var showingFullViewer = false

    public init(
        title: String,
        headerSystemImage: String? = "doc.text",
        content: String,
        contentType: String? = nil,
        rawData: Data? = nil,
        fileName: String? = nil,
        totalSize: Int? = nil,
        onCopy: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil
    ) {
        self.title = title
        self.headerSystemImage = headerSystemImage
        self.content = content
        self.contentType = contentType
        self.rawData = rawData
        self.fileName = fileName
        self.totalSize = totalSize
        self.onCopy = onCopy
        self.onShare = onShare
    }

    public enum ViewMode: String, CaseIterable, Identifiable {
        case auto = "Auto"
        case text = "Text"
        case hex = "Hex"

        public var id: String {
            rawValue
        }
    }

    public var body: some View {
        SectionCard(title: title, systemImage: headerSystemImage) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                metadataRow
                viewModePicker
                fileInfoRow
                viewerNoticeRow
                contentArea
            }
        }
        .sheet(item: $previewImageItem) { item in
            ImagePreviewView(
                imageData: item.data,
                preferredFilename: item.filename,
                contentType: item.contentType,
                title: item.title
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingFullViewer) {
            fullViewerSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var metadataRow: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            if let detectedType = detectedContentType {
                Label(detectedType.displayName, systemImage: detectedType.icon)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(DesignSystem.Colors.accent.opacity(0.1))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .clipShape(Capsule())
            }

            if let totalSize, totalSize > 0 {
                Text(DesignSystem.formattedBytes(totalSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if onCopy != nil || onShare != nil || showsFullScreenOption {
                Menu {
                    if let onCopy {
                        Button(action: onCopy) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }

                    if let onShare {
                        Button(action: onShare) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }

                    if showsFullScreenOption {
                        Divider()
                        Button {
                            showingFullViewer = true
                        } label: {
                            Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .accessibilityLabel("Body actions")
                .accessibilityHint("Copy, share, or view full screen")
            }
        }
    }

    private var viewModePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            ForEach(ViewMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Body view mode")
    }

    @ViewBuilder
    private var fileInfoRow: some View {
        if detectedContentType == .binary, let fileName, !fileName.isEmpty {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "doc.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(fileName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
        }
    }

    @ViewBuilder
    private var viewerNoticeRow: some View {
        if let viewerNotice {
            Label(viewerNotice, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch viewMode {
        case .text:
            DirectionalScrollView([.horizontal, .vertical]) {
                textView
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignSystem.Spacing.xs)
            }
            .frame(maxHeight: 420)

        case .hex:
            DirectionalScrollView([.horizontal, .vertical]) {
                hexView
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignSystem.Spacing.xs)
            }
            .frame(maxHeight: 420)

        case .auto:
            autoContentView
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 120)
        }
    }

    @ViewBuilder
    private var autoContentView: some View {
        switch effectiveDetectedContentType {
        case .json:
            JSONViewerView(jsonString: content)
                .frame(minHeight: 200)

        case .html:
            HTMLViewerView(htmlString: content)
                .frame(minHeight: 200)

        case .xml:
            XMLViewerView(xmlString: content)
                .frame(minHeight: 200)

        case .javascript:
            JavaScriptViewerView(code: content)
                .frame(minHeight: 200)

        case .css:
            CSSViewerView(code: content)
                .frame(minHeight: 200)

        case .image:
            imageView

        case .multipart:
            if let contentType, let data = content.data(using: .utf8) {
                MultipartFormView(data: data, contentType: contentType)
            } else {
                Text("Unable to parse multipart data")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            }

        case .form:
            FormBodyView(text: content)
                .frame(minHeight: 120)

        case .plainText, .none:
            DirectionalScrollView([.horizontal, .vertical]) {
                textView
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignSystem.Spacing.xs)
            }
            .frame(maxHeight: 420)

        case .binary:
            DirectionalScrollView([.horizontal, .vertical]) {
                hexView
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignSystem.Spacing.xs)
            }
            .frame(maxHeight: 420)
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let svgData {
            SVGPreviewView(svgData: svgData)
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        } else if let imageData = imageDataFromContent,
                  let uiImage = downsampledImage(from: imageData) {
            Button {
                previewImageItem = PreviewImageItem(
                    data: imageData,
                    filename: fileName,
                    contentType: contentType,
                    title: fileName ?? "Image"
                )
            } label: {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        } else if let image = imageFromContent {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        } else {
            imageLoadErrorView
        }
    }

    private var imageLoadErrorView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Unable to load image")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let data = rawData ?? content.data(using: .utf8) {
                Text("\(DesignSystem.formattedBytes(data.count)) of data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
        .background(DesignSystem.Colors.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }

    private var textView: some View {
        Text(content)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
    }

    private var hexView: some View {
        Text(hexRepresentation)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
    }

    private var fullViewerSheet: some View {
        NavigationStack {
            Group {
                switch effectiveDetectedContentType {
                case .json:
                    JSONViewerView(jsonString: content)
                case .html:
                    HTMLViewerView(htmlString: content)
                case .xml:
                    XMLViewerView(xmlString: content)
                case .javascript:
                    JavaScriptViewerView(code: content)
                case .css:
                    CSSViewerView(code: content)
                case .form:
                    ScrollView(.vertical) {
                        FormBodyView(text: content)
                            .padding()
                    }
                case .image:
                    imageFullScreenView
                default:
                    DirectionalScrollView([.horizontal, .vertical]) {
                        textView
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .navigationTitle(effectiveDetectedContentType?.displayName ?? "Body")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingFullViewer = false
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if let onShare {
                        Button {
                            onShare()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                if let onCopy {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            onCopy()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var imageFullScreenView: some View {
        if let svgData {
            SVGPreviewView(svgData: svgData)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.surface)
        } else if let data = imageDataFromContent {
            ImagePreviewView(
                imageData: data,
                preferredFilename: fileName,
                contentType: contentType,
                title: fileName ?? "Image"
            )
        } else if let image = imageFromContent {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Unable to load image")
                .foregroundStyle(.secondary)
        }
    }

    private var showsFullScreenOption: Bool {
        guard let type = effectiveDetectedContentType else { return false }
        switch type {
        case .plainText, .binary:
            return false
        default:
            return true
        }
    }

    private enum DetectedContentType {
        case json
        case html
        case xml
        case javascript
        case css
        case image
        case multipart
        case form
        case plainText
        case binary

        var displayName: String {
            switch self {
            case .json: "JSON"
            case .html: "HTML"
            case .xml: "XML"
            case .javascript: "JavaScript"
            case .css: "CSS"
            case .image: "Image"
            case .multipart: "Multipart"
            case .form: "Form"
            case .plainText: "Plain Text"
            case .binary: "Binary"
            }
        }

        var icon: String {
            switch self {
            case .json: "curlybraces"
            case .html: "doc.text"
            case .xml: "chevron.left.forwardslash.chevron.right"
            case .javascript: "scroll"
            case .css: "paintbrush"
            case .image: "photo"
            case .multipart: "doc.on.doc"
            case .form: "list.bullet.rectangle.portrait"
            case .plainText: "text.alignleft"
            case .binary: "doc.zipper"
            }
        }
    }

    private var detectedContentType: DetectedContentType? {
        if let fileName = fileName?.lowercased(),
           fileName.hasSuffix(".zip") || fileName.hasSuffix(".pdf") {
            return .binary
        }

        guard let ct = contentType?.lowercased() else {
            return detectFromContent()
        }

        if ct.contains("json") { return .json }
        if ct.contains("html") { return .html }
        if ct.contains("image/svg") { return .image }
        if ct.contains("xml") { return .xml }
        if ct.contains("javascript") { return .javascript }
        if ct.contains("css") { return .css }
        if ct.hasPrefix("image/") { return .image }
        if ct.contains("multipart") { return .multipart }
        if ct.contains("x-www-form-urlencoded") { return .form }
        if ct.contains("text/plain") { return detectFromContent() ?? .plainText }
        if ct.contains("octet-stream") ||
            ct.contains("application/zip") ||
            ct.contains("application/x-zip-compressed") ||
            ct.contains("application/pdf") ||
            ct.contains("application/x-gzip") ||
            ct.contains("application/gzip") ||
            ct.contains("font/") ||
            ct.hasPrefix("video/") ||
            ct.hasPrefix("audio/") {
            return .binary
        }

        return detectFromContent()
    }

    private func detectFromContent() -> DetectedContentType? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
            (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if let data = content.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return .json
            }
        }

        if trimmed.lowercased().contains("<!doctype html") || trimmed.lowercased().contains("<html") {
            return .html
        }

        if trimmed.hasPrefix("<?xml") || (trimmed.hasPrefix("<") && trimmed.contains("</")) {
            return .xml
        }

        if svgData != nil {
            return .image
        }

        return nil
    }

    private var effectiveDetectedContentType: DetectedContentType? {
        guard let detectedContentType else { return nil }
        if shouldUseLightweightRenderer {
            return .plainText
        }
        return detectedContentType
    }

    private var viewerNotice: String? {
        guard shouldUseLightweightRenderer else { return nil }
        return "Showing a lightweight text view because this body is too large for structured rendering."
    }

    private var shouldUseLightweightRenderer: Bool {
        BodyViewerPolicy.shouldPreferLightweightRenderer(
            contentType: contentType,
            byteCount: viewerByteCount
        )
    }

    private var viewerByteCount: Int {
        rawData?.count ?? content.utf8.count
    }

    private var hexRepresentation: String {
        let data: Data? = rawData ?? content.data(using: .utf8)
        guard let data else { return "" }

        let maxHexBytes = 64 * 1024
        let displayData = data.prefix(maxHexBytes)
        let wasTruncated = data.count > maxHexBytes

        var hex = ""
        for (index, byte) in displayData.enumerated() {
            if index > 0 && index % 16 == 0 {
                hex += "\n"
            } else if index > 0 && index % 8 == 0 {
                hex += "  "
            } else if index > 0 {
                hex += " "
            }
            hex += String(format: "%02X", byte)
        }

        if wasTruncated {
            hex += "\n\n… (truncated, showing first \(DesignSystem.formattedBytes(maxHexBytes)))"
        }
        return hex
    }

    private var imageFromContent: UIImage? {
        if let rawData {
            return downsampledImage(from: rawData)
        }
        if let data = Data(base64Encoded: content) {
            return downsampledImage(from: data)
        }
        if let data = content.data(using: .utf8) {
            return downsampledImage(from: data)
        }
        return nil
    }

    private var imageDataFromContent: Data? {
        if let rawData {
            return rawData
        }
        if let data = Data(base64Encoded: content) {
            return data
        }
        return content.data(using: .utf8)
    }

    private var svgData: Data? {
        SVGPreviewHelper.svgData(from: content, contentType: contentType)
    }

    private func downsampledImage(from data: Data) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: BodyViewerPolicy.imageThumbnailMaxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage)
    }

    private struct PreviewImageItem: Identifiable {
        let id = UUID()
        let data: Data
        let filename: String?
        let contentType: String?
        let title: String
    }
}
