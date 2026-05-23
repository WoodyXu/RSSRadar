import SwiftUI
import RSSRadarCore
import UniformTypeIdentifiers

struct FeedsView: View {
    @StateObject var viewModel: FeedsViewModel
    @State private var isImportingOPML = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Add Source")
                            .font(.headline)
                            .foregroundStyle(AppTheme.green)

                        HStack(spacing: 10) {
                            TextField("https://example.com/feed.xml", text: $viewModel.feedURLString)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                Task {
                                    await viewModel.addManualFeed()
                                }
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .buttonStyle(AppPrimaryButtonStyle())
                            .disabled(viewModel.feedURLString.isEmpty || viewModel.isWorking)
                        }

                        HStack(spacing: 10) {
                            Button {
                                isImportingOPML = true
                            } label: {
                                Label("Import OPML", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(AppSecondaryButtonStyle())

                            Button {
                                Task {
                                    await viewModel.refreshAll()
                                }
                            } label: {
                                Label("Refresh All", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(AppPrimaryButtonStyle())
                            .disabled(viewModel.feeds.isEmpty || viewModel.isWorking)
                        }
                    }
                }

                if viewModel.feeds.isEmpty {
                    EmptyStateCard(
                        systemImage: "dot.radiowaves.left.and.right",
                        title: "No RSS sources",
                        message: """
                            Import an OPML file or add a feed URL before scanning. \
                            RSSRadar needs sources before it can find articles and topics.
                            """
                    ) {
                        Button {
                            isImportingOPML = true
                        } label: {
                            Label("Import OPML", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.feeds) { feed in
                            FeedRow(feed: feed, viewModel: viewModel)
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .fileImporter(isPresented: $isImportingOPML, allowedContentTypes: [.xml, .data]) { result in
            if case let .success(url) = result {
                viewModel.importOPML(from: url)
            }
        }
        .task {
            viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Feeds")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.green)
            PageStatusBanner(message: viewModel.statusMessage, errorMessage: viewModel.errorMessage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeedRow: View {
    let feed: Feed
    @ObservedObject var viewModel: FeedsViewModel

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(feed.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(feed.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(feed.status.appDisplayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusTint)
                        .clipShape(Capsule())
                }

                HStack(spacing: 18) {
                    FeedMetric(title: "Last checked", value: feed.lastCheckedAt.appRelativeDate)
                    FeedMetric(title: "Last success", value: feed.lastSuccessAt.appRelativeDate)
                    FeedMetric(title: "Progress", value: feed.lastProcessedArticlePublishedAt.appShortDate)
                    Spacer()
                }

                if let error = feed.errorMessage, !error.isEmpty {
                    FeedNotice(
                        systemImage: "exclamationmark.triangle",
                        title: "Feed needs attention",
                        message: error,
                        tint: AppTheme.danger
                    )
                }

                if feed.status == .noArticles {
                    FeedNotice(
                        systemImage: "tray",
                        title: "No articles found",
                        message: """
                            This source was reachable, but it did not expose readable RSS items. \
                            You can keep it, refresh later, or delete it.
                            """,
                        tint: .orange
                    )
                }

                let fallbackCount = viewModel.rssSummaryFallbackCount(for: feed)
                if fallbackCount > 0 {
                    FeedNotice(
                        systemImage: "doc.text.magnifyingglass",
                        title: "Some article pages could not be extracted",
                        message: """
                            \(fallbackCount) articles are available through RSS summaries. \
                            AI analysis can continue, but those results are based on shorter source text.
                            """,
                        tint: AppTheme.accentGreen
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await viewModel.refresh(feed: feed)
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(AppSecondaryButtonStyle())

                    Button {
                        viewModel.setPaused(feed.status != .paused, feed: feed)
                    } label: {
                        Label(feed.status == .paused ? "Resume" : "Pause", systemImage: "pause.circle")
                    }
                    .buttonStyle(AppSecondaryButtonStyle())

                    Button {
                        viewModel.delete(feed: feed)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(AppDangerButtonStyle())
                }
                .disabled(viewModel.isWorking)
            }
        }
    }

    private var statusTint: Color {
        switch feed.status {
        case .active:
            AppTheme.accentGreen.opacity(0.16)
        case .paused:
            AppTheme.ceramic
        case .error:
            AppTheme.danger.opacity(0.12)
        case .noArticles:
            Color.orange.opacity(0.14)
        }
    }
}

private struct FeedNotice: View {
    let systemImage: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FeedMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}
