import SwiftUI
import RSSRadarProcessing

struct TodayView: View {
    @StateObject var viewModel: TodayViewModel

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let snapshot = viewModel.snapshot {
                        ScanStatusCard(scanStatus: snapshot.scanStatus)
                        TodayTopicSection(
                            title: "Important Topics",
                            emptyTitle: "No important updates today",
                            items: snapshot.importantTopics,
                            selectedTopicID: viewModel.selectedTopicID,
                            onSelect: viewModel.select(topicID:)
                        )
                        TodayTopicSection(
                            title: "New Candidate Topics",
                            emptyTitle: "No new candidate topics today",
                            items: snapshot.newCandidateTopics,
                            selectedTopicID: viewModel.selectedTopicID,
                            onSelect: viewModel.select(topicID:)
                        )
                        TodayTopicSection(
                            title: "Tracked Updates",
                            emptyTitle: "No tracked topic changes today",
                            items: snapshot.trackedTopicUpdates,
                            selectedTopicID: viewModel.selectedTopicID,
                            onSelect: viewModel.select(topicID:)
                        )
                    } else {
                        EmptyStateCard(
                            systemImage: "sparkles",
                            title: "Today is loading",
                            message: "RSSRadar is reading local topic and processing data."
                        ) {
                            ProgressView()
                        }
                    }
                }
                .padding(28)
            }
            .frame(minWidth: 360)

            TopicDetailView(snapshot: viewModel.selectedTopicDetail)
                .frame(minWidth: 460)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .task {
            viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today")
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
}

private struct ScanStatusCard: View {
    let scanStatus: TodayScanStatus

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Scan Status")
                    .font(.headline)
                    .foregroundStyle(AppTheme.green)

                HStack(spacing: 18) {
                    TodayMetric(title: "Last scan", value: scanStatus.lastScanAt.appRelativeDate)
                    TodayMetric(title: "Processed today", value: "\(scanStatus.processedArticleCount)")
                    TodayMetric(title: "Pending", value: "\(scanStatus.pendingJobCount)")
                    TodayMetric(title: "Failed", value: "\(scanStatus.failedCount)")
                }

                if let latestLog = scanStatus.latestLog {
                    Text(latestLog.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct TodayTopicSection: View {
    let title: String
    let emptyTitle: String
    let items: [TodayTopicItem]
    let selectedTopicID: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.green)

            if items.isEmpty {
                AppCard {
                    Label(emptyTitle, systemImage: "tray")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(items, id: \.topic.id) { item in
                        TodayTopicRow(
                            item: item,
                            isSelected: item.topic.id == selectedTopicID,
                            onSelect: { onSelect(item.topic.id) }
                        )
                    }
                }
            }
        }
    }
}

private struct TodayTopicRow: View {
    let item: TodayTopicItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.topic.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(item.currentTakeaway ?? item.topic.description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        Spacer()
                        Text(item.topic.status.appDisplayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.accentGreen.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 14) {
                        TodayMetric(title: "New", value: "\(item.newArticleCount)")
                        TodayMetric(title: "Related", value: "\(item.relatedArticleCount)")
                        TodayMetric(title: "Activity", value: item.latestActivityAt.appShortDate)
                    }

                    if item.primarySources.isEmpty == false {
                        Text(item.primarySources.prefix(3).joined(separator: " · "))
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
}

private struct TodayMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
