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
                Text("Settings")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
                PageStatusBanner(message: viewModel.statusMessage, errorMessage: viewModel.errorMessage)
            }

            Spacer()

            Button {
                viewModel.saveSettings()
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(viewModel.isWorking)
        }
    }

    private var aiSettings: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("AI")
                    .font(.headline)
                    .foregroundStyle(AppTheme.green)

                if !viewModel.hasSavedAPIKey {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "key.slash")
                            .foregroundStyle(AppTheme.accentGreen)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API key required for AI processing")
                                .font(.callout.weight(.semibold))
                            Text("""
                                RSS feeds can still be scanned. Article analysis, topic generation, \
                                and brief generation start after you save a provider, model, and API key.
                                """)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(AppTheme.accentGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Picker("Provider", selection: $viewModel.selectedProvider) {
                    ForEach(AIProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Base URL", text: $viewModel.baseURLString)
                    .textFieldStyle(.roundedBorder)

                TextField("Model name", text: $viewModel.modelName)
                    .textFieldStyle(.roundedBorder)

                SecureField(
                    viewModel.hasSavedAPIKey ? "Replace saved API key" : "API key",
                    text: $viewModel.apiKey
                )
                .textFieldStyle(.roundedBorder)

                HStack {
                    Text(viewModel.hasSavedAPIKey ? "API key saved in Keychain." : "No API key saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete API Key") {
                        viewModel.deleteSavedAPIKey()
                    }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .disabled(!viewModel.hasSavedAPIKey || viewModel.isWorking)
                }
            }
        }
    }

    private var scanSettings: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Scanning And Cost")
                    .font(.headline)
                    .foregroundStyle(AppTheme.green)

                Picker("Scan mode", selection: $viewModel.scanMode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                SettingsStepper(title: "Scan interval hours", value: $viewModel.scanIntervalHours, range: 1...168)
                SettingsStepper(title: "Max articles per scan", value: $viewModel.maxArticlesPerScan, range: 1...1_000)
                SettingsStepper(
                    title: "Max articles for new feed",
                    value: $viewModel.maxArticlesForNewFeed,
                    range: 1...100
                )
                SettingsStepper(
                    title: "Max topic batch size",
                    value: $viewModel.maxArticlesPerTopicBatch,
                    range: 1...100
                )
                SettingsStepper(title: "AI timeout seconds", value: $viewModel.aiRequestTimeoutSeconds, range: 5...600)
            }
        }
    }

    private var dataSettings: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Data")
                    .font(.headline)
                    .foregroundStyle(AppTheme.green)

                TextField("Database path", text: $viewModel.databasePath)
                    .textFieldStyle(.roundedBorder)

                Text("Current changes to the data path are saved as a setting. A new app bootstrap uses it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    isShowingClearConfirmation = true
                } label: {
                    Label("Clear Local Data", systemImage: "trash")
                }
                .buttonStyle(AppDangerButtonStyle())
            }
        }
    }

    private var clearConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clear Local Data")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.green)

            Text("This deletes feeds, articles, topics, corrections, processing jobs, and logs from the database.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("Also delete the saved Keychain API key", isOn: $viewModel.deleteAPIKeyWhenClearing)

            TextField("Type CLEAR to confirm", text: $viewModel.clearConfirmationText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    isShowingClearConfirmation = false
                }
                .buttonStyle(AppSecondaryButtonStyle())

                Spacer()

                Button("Clear Data") {
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
