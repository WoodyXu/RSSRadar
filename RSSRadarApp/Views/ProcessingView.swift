import SwiftUI
import RSSRadarCore

struct ProcessingView: View {
    @StateObject var viewModel: ProcessingViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                missingAPIKeyState
                aiFailureState
                queueSummary
                jobList
                logList
            }
            .padding(28)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .task {
            viewModel.load()
        }
    }

    @ViewBuilder
    private var missingAPIKeyState: some View {
        if !viewModel.hasSavedAPIKey {
            EmptyStateCard(
                systemImage: "key.slash",
                title: "尚未配置 AI 服务商",
                message: "内容源扫描仍可继续，但文章分析、主题归类和情报页生成需要先在 Keychain 中保存 API Key。"
            ) {
                Button {
                    onOpenSettings()
                } label: {
                    Label("打开通用配置", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(AppPrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var aiFailureState: some View {
        if !viewModel.failedAIJobs.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(AppTheme.danger)
                        Text("AI 调用需要处理")
                            .font(.headline)
                            .foregroundStyle(AppTheme.green)
                    }

                    Text("请检查服务商、API Key、URL 和模型，然后重试失败的 AI 任务。")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.failedAIJobs) { job in
                        AIFailureRow(job: job, viewModel: viewModel, onOpenSettings: onOpenSettings)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("处理日志")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
                PageStatusBanner(message: viewModel.statusMessage, errorMessage: viewModel.errorMessage)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.runPendingJobs()
                }
            } label: {
                Label("运行待处理任务", systemImage: "play.fill")
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(viewModel.isWorking)
        }
    }

    private var queueSummary: some View {
        AppCard {
            HStack(spacing: 24) {
                ProcessingCount(
                    title: "等待中",
                    count: viewModel.jobs.filter { $0.status == .pending }.count
                )
                ProcessingCount(
                    title: "运行中",
                    count: viewModel.jobs.filter { $0.status == .running }.count
                )
                ProcessingCount(
                    title: "失败",
                    count: viewModel.jobs.filter { $0.status == .failed }.count
                )
                ProcessingCount(
                    title: "已完成",
                    count: viewModel.jobs.filter { $0.status == .completed }.count
                )
                Spacer()
            }
        }
    }

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("任务")
                .font(.headline)
                .foregroundStyle(AppTheme.green)

            if viewModel.jobs.isEmpty {
                EmptyStateCard(
                    systemImage: "gearshape.2",
                    title: "暂无处理任务",
                    message: "请在内容源配置中添加 RSS 源并运行扫描。任务开始后会在这里显示，并提供重试入口。"
                ) {
                    Button {
                        Task {
                            await viewModel.runPendingJobs()
                        }
                    } label: {
                        Label("运行待处理任务", systemImage: "play.fill")
                    }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .disabled(viewModel.isWorking)
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.jobs) { job in
                        ProcessingJobRow(job: job, viewModel: viewModel)
                    }
                }
            }
        }
    }

    private var logList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近日志")
                .font(.headline)
                .foregroundStyle(AppTheme.green)

            if viewModel.logs.isEmpty {
                EmptyStateCard(
                    systemImage: "list.bullet.rectangle",
                    title: "暂无日志",
                    message: "扫描或 AI 任务运行后，这里会显示开始、完成、重试和失败记录。"
                ) {
                    EmptyView()
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.logs) { log in
                        AppCard {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(log.level.tint)
                                    .frame(width: 9, height: 9)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.message)
                                        .font(.callout.weight(.semibold))
                                    Text(log.createdAt.appShortDate)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct AIFailureRow: View {
    let job: ProcessingJob
    @ObservedObject var viewModel: ProcessingViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.jobType.displayName)
                        .font(.callout.weight(.semibold))
                    Text("模型 \(modelName) · 失败于 \(job.finishedAt.appShortDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        onOpenSettings()
                    } label: {
                        Label("配置", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(AppSecondaryButtonStyle())

                    Button {
                        Task {
                            await viewModel.retry(job: job)
                        }
                    } label: {
                        Label("重试", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(viewModel.isWorking)
                }
            }

            if let error = job.lastErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background(AppTheme.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var modelName: String {
        job.payload["model_name"].flatMap { $0.isEmpty ? nil : $0 } ?? "未记录"
    }
}

private struct ProcessingCount: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(count))
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.houseGreen)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProcessingJobRow: View {
    let job: ProcessingJob
    @ObservedObject var viewModel: ProcessingViewModel

    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.jobType.displayName)
                        .font(.headline)
                    Text(job.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("计划时间 \(job.scheduledAt.appShortDate) · 尝试 \(job.attemptCount)/\(job.maxAttempts)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let error = job.lastErrorMessage, !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(AppTheme.danger)
                            .lineLimit(3)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    Text(job.status.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(job.status.tint)
                        .clipShape(Capsule())

                    if job.status == .failed {
                        Button {
                            Task {
                                await viewModel.retry(job: job)
                            }
                        } label: {
                            Label("重试", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .disabled(viewModel.isWorking)
                    }
                }
            }
        }
    }
}

private extension ProcessingJobStatus {
    var tint: Color {
        switch self {
        case .pending:
            Color.orange.opacity(0.14)
        case .running:
            AppTheme.accentGreen.opacity(0.16)
        case .completed:
            AppTheme.ceramic
        case .failed:
            AppTheme.danger.opacity(0.12)
        }
    }
}

private extension OperationLogLevel {
    var tint: Color {
        switch self {
        case .info:
            AppTheme.accentGreen
        case .warning:
            .orange
        case .error:
            AppTheme.danger
        }
    }
}
