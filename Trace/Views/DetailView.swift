//
//  DetailView.swift
//  Trace
//
//  Created by Justin on 2026/01/10.
//

import Foundation
import SwiftUI
import TraceCore
import TraceFeatures
import TraceUI

struct DetailView: View {
    let request: NetworkRequest

    @StateObject private var viewModel = RequestDetailViewModel()
    @StateObject private var executor = RequestExecutor()
    @State private var activeSheet: DetailSheet?
    @ObservedObject private var favoritesManager = FavoritesManager.shared

    private enum DetailSheet: Identifiable {
        case requestBuilder
        case replayResponse(NetworkRequest)

        var id: String {
            switch self {
            case .requestBuilder:
                "requestBuilder"
            case let .replayResponse(response):
                "replayResponse-\(response.id.uuidString)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            QuickActionsBar(
                onReplay: { perform(.replay) },
                onCopyURL: { perform(.copyURL) },
                onCopyCURL: { perform(.copyCurl) },
                onShare: { perform(.shareFullRequest) },
                isLoading: executor.isLoading
            )
            .padding(.horizontal)
            .padding(.top, DesignSystem.Spacing.sm)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Quick actions")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableTabs, id: \.self) { tab in
                        tabChip(tab)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, DesignSystem.Spacing.sm)
            .accessibilityLabel("Request detail tabs")

            tabContent
        }
        .navigationTitle("Request Details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request.id) {
            await viewModel.loadInitialBodyPreview(for: request)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                favoriteButton
            }

            ToolbarItem(placement: .topBarTrailing) {
                overflowMenu
            }
        }
        .shareSheet(item: $viewModel.shareSheetItem)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .requestBuilder:
                RequestBuilderView(existingRequest: request)
            case let .replayResponse(response):
                replayResponseSheet(response: response)
            }
        }
        .toast(message: $viewModel.toastMessage)
    }

    private var availableTabs: [DetailTab] {
        viewModel.availableTabs(for: request)
    }

    private func tabChip(_ tab: DetailTab) -> some View {
        let isSelected = viewModel.selectedTab == tab
        return Button {
            viewModel.selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isSelected
                            ? DesignSystem.Colors.accent.opacity(0.18)
                            : Color(.secondarySystemBackground)
                    )
                )
                .foregroundStyle(isSelected ? DesignSystem.Colors.accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .overview:
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    RequestTimelineCard(request: request)
                    OverviewSection(request: request)
                }
                .padding()
            }

        case .requestHeaders:
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    HeadersSection(headers: request.requestHeaders)
                    requestBodySection
                }
                .padding()
            }

        case .responseHeaders:
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    HeadersSection(headers: request.responseHeaders)
                    responseBodySection
                }
                .padding()
            }

        case .cookies:
            ScrollView {
                CookiesSection(request: request)
                    .padding()
            }

        case .body:
            bodyTabContent

        case .sse:
            ScrollView {
                SSEEventsSection(request: request)
            }
        }
    }

    private var bodyTabContent: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                requestBodySection
                responseBodySection
                emptyBodyMessage
            }
            .padding()
        }
    }

    @ViewBuilder
    private var requestBodySection: some View {
        if !request.requestBody.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                if viewModel.isLoadingRequestBody {
                    LoadingPlaceholderCard(
                        title: "Request Body",
                        headerSystemImage: nil,
                        message: "Loading request body..."
                    )
                } else {
                    let contentType = viewModel.requestContentType(from: request)
                    let shareRequestBody = { viewModel.shareRequestBody(for: request) }
                    if let requestBodyNotice = viewModel.requestBodyNotice {
                        bodyNotice(requestBodyNotice)
                    }
                    BodyInspectorView(
                        title: "Request Body",
                        headerSystemImage: nil,
                        content: viewModel.requestBodyText ?? "",
                        contentType: contentType,
                        rawData: viewModel.requestBodyRawData,
                        fileName: nil,
                        totalSize: request.requestBody.capturedSize,
                        onCopy: viewModel.requestBodyText.map { text in
                            { viewModel.copyToClipboard(text) }
                        },
                        onShare: shareRequestBody
                    )
                }

                if viewModel.isRequestBodyPreview {
                    Button("Load Full Captured Request Body") {
                        Task {
                            await viewModel.loadRequestBody(for: request, full: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var responseBodySection: some View {
        if !request.responseBody.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                if viewModel.isLoadingResponseBody {
                    LoadingPlaceholderCard(
                        title: "Response Body",
                        headerSystemImage: nil,
                        message: "Loading response body..."
                    )
                } else {
                    let contentType = viewModel.responseContentType(from: request)
                    let fileName = viewModel.responseAttachmentFilename(from: request)
                    let shareResponseBody = { viewModel.shareResponseBody(for: request) }
                    if let responseBodyNotice = viewModel.responseBodyNotice {
                        bodyNotice(responseBodyNotice)
                    }
                    BodyInspectorView(
                        title: "Response Body",
                        headerSystemImage: nil,
                        content: viewModel.responseBodyText ?? "",
                        contentType: contentType,
                        rawData: viewModel.responseBodyRawData,
                        fileName: fileName,
                        totalSize: request.responseBody.capturedSize,
                        onCopy: viewModel.responseBodyText.map { text in
                            { viewModel.copyToClipboard(text) }
                        },
                        onShare: shareResponseBody
                    )
                }

                if viewModel.isResponseBodyPreview {
                    Button("Load Full Captured Response Body") {
                        Task {
                            await viewModel.loadResponseBody(for: request, full: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyBodyMessage: some View {
        if request.requestBody.isEmpty && request.responseBody.isEmpty {
            TraceContentUnavailableView(
                "No Body Content",
                systemImage: "doc.text",
                description: Text("This request has no body data")
            )
            .padding()
        }
    }

    private func bodyNotice(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
    }

    private var favoriteButton: some View {
        Button {
            favoritesManager.toggleFavorite(requestId: request.id)
        } label: {
            Image(systemName: favoritesManager.isFavorited(requestId: request.id) ? "star.fill" : "star")
                .foregroundStyle(favoritesManager.isFavorited(requestId: request.id) ? DesignSystem.Colors.favorite : .primary)
        }
        .accessibilityLabel(favoritesManager.isFavorited(requestId: request.id) ? "Remove from favorites" : "Add to favorites")
        .accessibilityHint("Double tap to \(favoritesManager.isFavorited(requestId: request.id) ? "remove from" : "add to") favorites")
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(overflowActions) { action in
                Button {
                    perform(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private var overflowActions: [DetailAction] {
        DetailActionModel.overflowActions(
            hasRequestBody: !request.requestBody.isEmpty,
            hasResponseBody: !request.responseBody.isEmpty
        )
    }

    private func replayResponseSheet(response: NetworkRequest) -> some View {
        NavigationStack {
            DetailView(request: response)
                .navigationTitle("Replay Response")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            activeSheet = nil
                        }
                    }
                }
        }
    }

    private func perform(_ action: DetailAction) {
        switch action {
        case .replay:
            replayRequest()
        case .copyURL:
            viewModel.copyToClipboard(request.url)
        case .copyCurl:
            viewModel.copyRequestAsCurl(for: request)
        case .shareFullRequest:
            viewModel.shareFullRequest(for: request)
        case .editAndSend:
            activeSheet = .requestBuilder
        case .shareResponseBody:
            viewModel.shareResponseBody(for: request)
        case .shareRequestBody:
            viewModel.shareRequestBody(for: request)
        }
    }

    private func replayRequest() {
        DesignSystem.Haptics.medium()
        Task {
            do {
                let response = try await executor.replay(request)
                try AppGroupStorage.shared.saveRequest(response)
                await MainActor.run {
                    DesignSystem.Haptics.success()
                    activeSheet = .replayResponse(response)
                }
            } catch {
                await MainActor.run {
                    DesignSystem.Haptics.error()
                    withAnimation(DesignSystem.Accessibility.preferredAnimation) {
                        viewModel.toastMessage = "Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

#Preview {
    let sampleRequest = NetworkRequest(
        url: "https://api.example.com/users/123",
        method: .get,
        statusCode: 200,
        timestamp: Date(),
        duration: 0.234,
        requestHeaders: [
            TraceHTTPHeader(key: "Content-Type", value: "application/json"),
            TraceHTTPHeader(key: "Authorization", value: "Bearer token...")
        ],
        responseHeaders: [
            TraceHTTPHeader(key: "Content-Type", value: "application/json")
        ],
        requestBody: .empty,
        responseBody: BodyStorage.from(string: """
        {
          "id": 123,
          "name": "John Doe",
          "email": "john@example.com"
        }
        """)
    )

    NavigationStack {
        DetailView(request: sampleRequest)
    }
}
