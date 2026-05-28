import SwiftUI
import RSSRadarCore

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    @State private var isShowingClearConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                aiSettings
                currentAISettings
                scanSettings
                dataSettings
            }
            .padding(28)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .sheet(isPresented: $isShowingClearConfirmation) {
            clearConfirmationSheet
        }
        .task {
            viewModel.load()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("通用配置")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
                PageStatusBanner(message: viewModel.statusMessage, errorMessage: viewModel.errorMessage)
            }

            Spacer()

            Button {
                viewModel.saveSettings()
            } label: {
                Label("保存", systemImage: "checkmark")
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(viewModel.isWorking)
        }
    }

    private var aiSettings: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("AI 新配置")
                    .font(.headline)
                    .foregroundStyle(AppTheme.green)

                if !viewModel.hasSavedAPIKey {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "key.slash")
                            .foregroundStyle(AppTheme.accentGreen)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI 处理需要 API Key")
                                .font(.callout.weight(.semibold))
                            Text("RSS 源仍可扫描。保存服务商、模型和 API Key 后，文章分析、主题生成和情报页生成才会开始。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(AppTheme.accentGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Picker("服务商", selection: $viewModel.selectedProvider) {
                    ForEach(AIProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                TextField("URL", text: $viewModel.baseURLString)
                    .textFieldStyle(.roundedBorder)

                TextField("模型", text: $viewModel.modelName)
                    .textFieldStyle(.roundedBorder)

                SecureField(
                    viewModel.hasSavedAPIKey ? "替换已保存 API Key" : "API Key",
                    text: $viewModel.apiKey
                )
                .textFieldStyle(.roundedBorder)

                HStack {
                    Text(viewModel.hasSavedAPIKey ? "API Key 已保存在 Keychain。" : "尚未保存 API Key。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("删除 API Key") {
                        viewModel.deleteSavedAPIKey()
                    }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .disabled(!viewModel.hasSavedAPIKey || viewModel.isWorking)
                }
            }
        }
    }

    private var currentAISettings: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("当前配置")
                    .font(.headline)
                    .foregroundStyle(AppTheme.green)

                SettingsReadOnlyRow(title: "服务商", value: viewModel.savedProviderName)
                SettingsReadOnlyRow(title: "URL", value: viewModel.savedBaseURLString)
                SettingsReadOnlyRow(title: "Model", value: viewModel.savedModelName)
                SettingsReadOnlyRow(title: "API Key", value: viewModel.hasSavedAPIKey ? "已保存到 Keychain" : "未配置")
            }
        }
    }

    private var scanSettings: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("扫描与成本")
                    .font(.headline)
                    .foregroundStyle(AppTheme.green)

                Picker("扫描模式", selection: $viewModel.scanMode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                SettingsStepper(title: "扫描间隔小时数", value: $viewModel.scanIntervalHours, range: 1...168)
                SettingsStepper(title: "单次扫描最大文章数", value: $viewModel.maxArticlesPerScan, range: 1...1_000)
                SettingsStepper(
                    title: "新源最大文章数",
                    value: $viewModel.maxArticlesForNewFeed,
                    range: 1...100
                )
                SettingsStepper(
                    title: "主题批处理最大文章数",
                    value: $viewModel.maxArticlesPerTopicBatch,
                    range: 1...100
                )
                SettingsStepper(title: "AI 超时秒数", value: $viewModel.aiRequestTimeoutSeconds, range: 5...600)
            }
        }
    }

    private var dataSettings: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("数据")
                    .font(.headline)
                    .foregroundStyle(AppTheme.green)

                TextField("数据库路径", text: $viewModel.databasePath)
                    .textFieldStyle(.roundedBorder)

                Text("数据库路径会保存为配置，并在下次应用启动时生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    isShowingClearConfirmation = true
                } label: {
                    Label("清空本地数据", systemImage: "trash")
                }
                .buttonStyle(AppDangerButtonStyle())
            }
        }
    }

    private var clearConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("清空本地数据")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.green)

            Text("这会从数据库中删除内容源、文章、主题、纠错记录、处理任务和日志。")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("同时删除 Keychain 中保存的 API Key", isOn: $viewModel.deleteAPIKeyWhenClearing)

            TextField("输入 CLEAR 确认", text: $viewModel.clearConfirmationText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("取消") {
                    isShowingClearConfirmation = false
                }
                .buttonStyle(AppSecondaryButtonStyle())

                Spacer()

                Button("清空数据") {
                    viewModel.clearLocalData()
                    if viewModel.errorMessage == nil {
                        isShowingClearConfirmation = false
                    }
                }
                .buttonStyle(AppDangerButtonStyle())
                .disabled(!viewModel.canClearLocalData)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(AppTheme.canvas)
    }
}

private struct SettingsStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: $value, in: range) {
                Text(String(value))
                    .font(.callout.weight(.semibold))
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
    }
}

private struct SettingsReadOnlyRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
