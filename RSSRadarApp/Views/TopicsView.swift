import AppKit
import SwiftUI
import RSSRadarCore
import RSSRadarProcessing

struct TopicsView: View {
    @StateObject var viewModel: TopicsViewModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statusFilter

                if viewModel.filteredTopics.isEmpty {
                    EmptyStateCard(
                        systemImage: "rectangle.stack",
                        title: "当前视图没有主题",
                        message: "文章分析和主题归类任务完成后，主题会显示在这里。"
                    ) {
                        Button {
                            viewModel.load()
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.filteredTopics) { topic in
                                TopicListRow(
                                    topic: topic,
                                    isSelected: topic.id == viewModel.selectedTopicID,
                                    onSelect: { viewModel.select(topicID: topic.id) }
                                )
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .padding(28)
            .frame(minWidth: 380)

            TopicDetailView(
                snapshot: viewModel.selectedTopicDetail,
                onTrackCandidate: viewModel.trackSelectedCandidate,
                onIgnoreCandidate: viewModel.ignoreSelectedCandidate,
                onExtractBrief: viewModel.extractSelectedTopicBrief,
                isWorking: viewModel.isWorking,
                briefExtractionState: viewModel.briefExtractionState
            )
                .frame(minWidth: 500)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .task {
            viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("主题聚合")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
                Spacer()
                Button {
                    viewModel.load()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(AppSecondaryButtonStyle())
            }
            Text("""
                待确认主题：AI发现的潜在主题，你可以点击「跟踪」或「忽略」。
                跟踪主题：AI持续观察跟踪。
                忽略主题：你不感兴趣的主题。
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PageStatusBanner(message: viewModel.statusMessage, errorMessage: viewModel.errorMessage)
        }
    }

    private var statusFilter: some View {
        Picker("主题状态", selection: Binding(
            get: { viewModel.selectedStatus },
            set: { viewModel.setStatusFilter($0) }
        )) {
            Text("全部 (\(viewModel.visibleTopicCount))").tag(TopicStatus?.none)
            ForEach(TopicStatus.visibleInTopicsTab, id: \.self) { status in
                Text("\(status.appDisplayName) (\(viewModel.count(for: status)))")
                    .tag(TopicStatus?.some(status))
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct TopicListRow: View {
    let topic: Topic
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(topic.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(topic.description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        Spacer()
                        Text(topic.status.appDisplayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(statusTint)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 14) {
                        TopicMeta(title: "更新", value: topic.updatedAt.appShortDate)
                        TopicMeta(
                            title: "重要性",
                            value: topic.importanceScore.map { String(format: "%.0f%%", $0 * 100) } ?? "无"
                        )
                    }

                    if topic.entities.isEmpty == false {
                        Text(topic.entities.prefix(5).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppTheme.accentGreen : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var statusTint: Color {
        switch topic.status {
        case .candidate:
            Color.orange.opacity(0.14)
        case .active:
            AppTheme.accentGreen.opacity(0.16)
        case .ignored:
            AppTheme.ceramic
        case .archived:
            AppTheme.houseGreen.opacity(0.10)
        }
    }
}

private struct TopicMeta: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

struct TopicDetailView: View {
    let snapshot: TopicDetailSnapshot?
    var onTrackCandidate: (() -> Void)?
    var onIgnoreCandidate: (() -> Void)?
    var onExtractBrief: (() -> Void)?
    var isWorking = false
    var briefExtractionState: TopicsViewModel.BriefExtractionState?

    var body: some View {
        ScrollView {
            if let snapshot {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(snapshot: snapshot)

                    if let currentTakeaway = snapshot.currentTakeaway {
                        DetailSection(title: "当前结论") {
                            Text(currentTakeaway)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if shouldShowBriefSections(snapshot) {
                        DetailSection(title: "最近变化") {
                            if snapshot.latestChanges.isEmpty {
                                EmptyDetailText("暂无缓存的最近变化。")
                            } else {
                                BulletList(items: snapshot.latestChanges.map(\.text))
                            }
                        }

                        DetailSection(title: "时间线") {
                            if snapshot.timeline.isEmpty {
                                EmptyDetailText("暂无缓存的时间线。")
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(snapshot.timeline.enumerated()), id: \.offset) { _, item in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title)
                                                .font(.callout.weight(.semibold))
                                            Text(item.description)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                            if let date = item.date {
                                                Text(date.appShortDate)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        DetailSection(title: "关键证据") {
                            if snapshot.evidence.isEmpty {
                                EmptyDetailText("暂无缓存的关键证据。")
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(snapshot.evidence.enumerated()), id: \.offset) { _, item in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.evidence.content)
                                                .font(.callout)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(item.sourceName)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    DetailSection(title: "相关文章") {
                        if snapshot.relatedArticles.isEmpty {
                            EmptyDetailText("暂无相关文章。")
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(snapshot.relatedArticles, id: \.article.id) { item in
                                    Button {
                                        NSWorkspace.shared.open(item.article.url)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.article.title)
                                                .font(.callout.weight(.semibold))
                                                .foregroundStyle(AppTheme.green)
                                            if let summary = item.analysisSummary {
                                                Text(summary)
                                                    .font(.callout)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(3)
                                            }
                                            Text(
                                                item.sourceName
                                                    ?? item.article.url.host()
                                                    ?? item.article.url.absoluteString
                                            )
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(28)
            } else {
                EmptyStateCard(
                    systemImage: "doc.text.magnifyingglass",
                    title: "选择一个主题",
                    message: "选择主题后可查看情报页、关键证据和相关文章。"
                ) {
                    EmptyView()
                }
                .padding(28)
            }
        }
        .background(AppTheme.ceramic.opacity(0.65).ignoresSafeArea())
    }

    private func detailHeader(snapshot: TopicDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.topic.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.green)
                    Text(snapshot.topic.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(snapshot.topic.status.appDisplayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.accentGreen.opacity(0.14))
                    .clipShape(Capsule())
            }

            HStack(spacing: 14) {
                TopicMeta(title: "文章", value: "\(snapshot.relatedArticles.count)")
                TopicMeta(title: "更新", value: snapshot.topic.updatedAt.appShortDate)
            }

            if snapshot.topic.status == .active, let onExtractBrief {
                HStack(spacing: 10) {
                    Button(action: onExtractBrief) {
                        Label("一键萃取", systemImage: "sparkles")
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(isWorking)

                    if let briefExtractionState {
                        Text(briefExtractionState.displayText)
                            .font(.callout)
                            .foregroundStyle(briefExtractionTextColor(for: briefExtractionState))
                            .lineLimit(2)
                    } else {
                        Text("点击总结主题动态。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if snapshot.topic.status == .candidate {
                HStack(spacing: 10) {
                    if let onTrackCandidate {
                        Button(action: onTrackCandidate) {
                            Label("跟踪", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                    }

                    if let onIgnoreCandidate {
                        Button(action: onIgnoreCandidate) {
                            Label("忽略", systemImage: "xmark.circle")
                        }
                        .buttonStyle(AppSecondaryButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shouldShowBriefSections(_ snapshot: TopicDetailSnapshot) -> Bool {
        snapshot.topic.status == .active
    }

    private func briefExtractionTextColor(for state: TopicsViewModel.BriefExtractionState) -> Color {
        switch state {
        case .extracting:
            .secondary
        case .success:
            AppTheme.accentGreen
        case .failure:
            AppTheme.danger
        }
    }
}

private extension TopicStatus {
    static var visibleInTopicsTab: [TopicStatus] {
        [.candidate, .active, .ignored]
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.green)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
        }
    }
}

private struct EmptyDetailText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
