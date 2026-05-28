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
                        Text("添加源")
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
                                Label("添加", systemImage: "plus")
                            }
                            .buttonStyle(AppPrimaryButtonStyle())
                            .disabled(viewModel.feedURLString.isEmpty || viewModel.isWorking)
                        }

                        HStack(spacing: 10) {
                            Button {
                            isImportingOPML = true
                        } label: {
                            Label("导入 OPML", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(AppSecondaryButtonStyle())

                        Button {
                                Task {
                                    await viewModel.refreshAll()
                            }
                        } label: {
                            Label("全部手动刷新", systemImage: "arrow.clockwise")
                        }
                            .buttonStyle(AppPrimaryButtonStyle())
                            .disabled(viewModel.feeds.isEmpty || viewModel.isWorking)
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("当前源管理")
                            .font(.headline)
                            .foregroundStyle(AppTheme.green)

                        if viewModel.feeds.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("暂无 RSS 源", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(AppTheme.green)
                                Text("请先导入 OPML 文件或添加 RSS URL。RSSRadar 需要内容源后才能发现文章和主题。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Button {
                                    isImportingOPML = true
                                } label: {
                                    Label("导入 OPML", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(AppPrimaryButtonStyle())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.feeds) { feed in
                                    FeedRow(feed: feed, viewModel: viewModel)
                                }
                            }
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
            Text("内容源配置")
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
                    FeedMetric(title: "最近检查", value: feed.lastCheckedAt.appRelativeDate)
                    FeedMetric(title: "最近成功", value: feed.lastSuccessAt.appRelativeDate)
                    FeedMetric(title: "处理进度", value: feed.lastProcessedArticlePublishedAt.appShortDate)
                    Spacer()
                }

                if let error = feed.errorMessage, !error.isEmpty {
                    FeedNotice(
                        systemImage: "exclamationmark.triangle",
                        title: "内容源需要处理",
                        message: error,
                        tint: AppTheme.danger
                    )
                }

                if feed.status == .noArticles {
                    FeedNotice(
                        systemImage: "tray",
                        title: "未发现文章",
                        message: "这个源可以访问，但没有暴露可读取的 RSS 条目。你可以保留、稍后刷新或删除它。",
                        tint: .orange
                    )
                }

                let fallbackCount = viewModel.rssSummaryFallbackCount(for: feed)
                if fallbackCount > 0 {
                    FeedNotice(
                        systemImage: "doc.text.magnifyingglass",
                        title: "部分文章页面无法提取正文",
                        message: "\(fallbackCount) 篇文章将使用 RSS 摘要继续处理，AI 分析会基于较短的来源文本。",
                        tint: AppTheme.accentGreen
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await viewModel.refresh(feed: feed)
                        }
                    } label: {
                        Label("手动刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(AppSecondaryButtonStyle())

                    Button {
                        viewModel.delete(feed: feed)
                    } label: {
                        Label("删除", systemImage: "trash")
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
