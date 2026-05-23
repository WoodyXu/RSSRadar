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
                title: "AI provider is not configured",
                message: """
                    Feed scanning can continue, but article analysis, topic assignment, \
                    and brief generation need an API key stored in Keychain.
                    """
            ) {
                Button {
                    onOpenSettings()
                } label: {
                    Label("Open Settings", systemImage: "slider.horizontal.3")
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
                        Text("AI calls need attention")
                            .font(.headline)
                            .foregroundStyle(AppTheme.green)
                    }

                    Text("Review the provider, API key, Base URL, and model name, then retry failed AI jobs.")
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
                Text("Processing")
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
                Label("Run Pending", systemImage: "play.fill")
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(viewModel.isWorking)
        }
    }

    private var queueSummary: some View {
        AppCard {
            HStack(spacing: 24) {
                ProcessingCount(
                    title: "Pending",
                    count: viewModel.jobs.filter { $0.status == .pending }.count
                )
                ProcessingCount(
                    title: "Running",
                    count: viewModel.jobs.filter { $0.status == .running }.count
                )
                ProcessingCount(
                    title: "Failed",
                    count: viewModel.jobs.filter { $0.status == .failed }.count
                )
                ProcessingCount(
                    title: "Completed",
                    count: viewModel.jobs.filter { $0.status == .completed }.count
                )
                Spacer()
            }
        }
    }

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Jobs")
                .font(.headline)
                .foregroundStyle(AppTheme.green)

            if viewModel.jobs.isEmpty {
                EmptyStateCard(
                    systemImage: "gearshape.2",
                    title: "No processing work yet",
                    message: """
                        Add RSS sources from Feeds and run a scan. \
                        Jobs will appear here with retry controls when work starts.
                        """
                ) {
                    Button {
                        Task {
                            await viewModel.runPendingJobs()
                        }
                    } label: {
                        Label("Run Pending", systemImage: "play.fill")
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
            Text("Recent Logs")
                .font(.headline)
                .foregroundStyle(AppTheme.green)

            if viewModel.logs.isEmpty {
                EmptyStateCard(
                    systemImage: "list.bullet.rectangle",
                    title: "No logs yet",
                    message: """
                        Processing logs will show starts, completions, retries, and failures \
                        once scans or AI work run.
                        """
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
                    Text("Model \(modelName) · failed \(job.finishedAt.appShortDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        onOpenSettings()
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(AppSecondaryButtonStyle())

                    Button {
                        Task {
                            await viewModel.retry(job: job)
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.counterclockwise")
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
        job.payload["model_name"].flatMap { $0.isEmpty ? nil : $0 } ?? "not recorded"
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
                    Text("Scheduled \(job.scheduledAt.appShortDate) · attempt \(job.attemptCount)/\(job.maxAttempts)")
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
                            Label("Retry", systemImage: "arrow.counterclockwise")
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
