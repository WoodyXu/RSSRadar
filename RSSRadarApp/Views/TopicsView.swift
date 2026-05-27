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
                        title: "No topics in this view",
                        message: "Topics appear after article analysis and topic assignment jobs finish."
                    ) {
                        Button {
                            viewModel.load()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
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
                onIgnoreCandidate: viewModel.ignoreSelectedCandidate
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
                Text("Topics")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
                Spacer()
                Button {
                    viewModel.load()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(AppSecondaryButtonStyle())
            }
            PageStatusBanner(message: viewModel.statusMessage, errorMessage: viewModel.errorMessage)
        }
    }

    private var statusFilter: some View {
        Picker("Topic status", selection: Binding(
            get: { viewModel.selectedStatus },
            set: { viewModel.setStatusFilter($0) }
        )) {
            Text("All (\(viewModel.topics.count))").tag(TopicStatus?.none)
            ForEach(TopicStatus.allCases, id: \.self) { status in
                Text("\(status.appDisplayName.capitalized) (\(viewModel.count(for: status)))")
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
                        TopicMeta(title: "Updated", value: topic.updatedAt.appShortDate)
                        TopicMeta(
                            title: "Importance",
                            value: topic.importanceScore.map { String(format: "%.0f%%", $0 * 100) } ?? "None"
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

    var body: some View {
        ScrollView {
            if let snapshot {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(snapshot: snapshot)

                    if let currentTakeaway = snapshot.currentTakeaway {
                        DetailSection(title: "Current Takeaway") {
                            Text(currentTakeaway)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    DetailSection(title: "Latest Changes") {
                        if snapshot.latestChanges.isEmpty {
                            EmptyDetailText("No latest changes cached.")
                        } else {
                            BulletList(items: snapshot.latestChanges.map(\.text))
                        }
                    }

                    DetailSection(title: "Timeline") {
                        if snapshot.timeline.isEmpty {
                            EmptyDetailText("No timeline cached.")
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

                    DetailSection(title: "Evidence") {
                        if snapshot.evidence.isEmpty {
                            EmptyDetailText("No evidence cached.")
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

                    DetailSection(title: "Related Articles") {
                        if snapshot.relatedArticles.isEmpty {
                            EmptyDetailText("No related articles found.")
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(snapshot.relatedArticles, id: \.article.id) { item in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.article.title)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        if let summary = item.analysisSummary {
                                            Text(summary)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                        }
                                        Text(item.sourceName ?? item.article.url.host() ?? item.article.url.absoluteString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(28)
            } else {
                EmptyStateCard(
                    systemImage: "doc.text.magnifyingglass",
                    title: "Select a topic",
                    message: "Choose a topic to inspect its brief, evidence, and related articles."
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
                TopicMeta(title: "Brief", value: snapshot.briefType.rawValue)
                TopicMeta(title: "Articles", value: "\(snapshot.relatedArticles.count)")
                TopicMeta(title: "Updated", value: snapshot.topic.updatedAt.appShortDate)
            }

            if snapshot.topic.status == .candidate {
                HStack(spacing: 10) {
                    if let onTrackCandidate {
                        Button(action: onTrackCandidate) {
                            Label("Track", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                    }

                    if let onIgnoreCandidate {
                        Button(action: onIgnoreCandidate) {
                            Label("Ignore", systemImage: "xmark.circle")
                        }
                        .buttonStyle(AppSecondaryButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
