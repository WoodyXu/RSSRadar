import RSSRadarCore
import RSSRadarProcessing
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onFinish: () -> Void

    @State private var isImportingOPML = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                    workflow
                    candidateSection
                }
            }

            Button(action: onFinish) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(FloatingActionButtonStyle())
            .help("打开 RSSRadar")
            .padding(24)
        }
        .task {
            viewModel.load()
        }
        .fileImporter(
            isPresented: $isImportingOPML,
            allowedContentTypes: [.xml, .data],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                return
            }
            viewModel.importOPML(from: url)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("RSSRadar")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .tracking(0)

            Text("把 RSS 内容源转化为本地主题情报。")
                .font(.system(size: 21, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(Color.white.opacity(0.72))
                .tracking(0)

            HStack(spacing: 12) {
                Label("本地数据", systemImage: "lock")
                Label("你的 API Key", systemImage: "key")
                Label("无云同步", systemImage: "icloud.slash")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.vertical, 44)
        .background(Theme.houseGreen)
    }

    private var workflow: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let errorMessage = viewModel.errorMessage {
                StatusBanner(message: errorMessage, systemImage: "exclamationmark.triangle", tint: Theme.error)
            }

            HStack(alignment: .top, spacing: 18) {
                feedCard
                providerCard
            }

            scanCard
        }
        .frame(maxWidth: 1120, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
    }

    private var feedCard: some View {
        OnboardingCard(number: "1", title: "内容源", systemImage: "dot.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.feedSummary)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.softText)

                HStack(spacing: 10) {
                    TextField("https://example.com/feed.xml", text: $viewModel.feedURLString)
                        .textFieldStyle(OnboardingTextFieldStyle())

                    Button {
                        Task {
                            await viewModel.addManualFeed()
                        }
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                    .disabled(viewModel.isWorking)
                }

                Button {
                    isImportingOPML = true
                } label: {
                    Label("导入 OPML", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(OutlinePillButtonStyle())
                .disabled(viewModel.isWorking)
            }
        }
    }

    private var providerCard: some View {
        OnboardingCard(number: "2", title: "AI 服务商", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.settingsSummary)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.softText)

                Picker("服务商", selection: $viewModel.selectedProvider) {
                    ForEach(AIProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                TextField("URL", text: $viewModel.baseURLString)
                    .textFieldStyle(OnboardingTextFieldStyle())

                TextField("模型", text: $viewModel.modelName)
                    .textFieldStyle(OnboardingTextFieldStyle())

                SecureField("API Key", text: $viewModel.apiKey)
                    .textFieldStyle(OnboardingTextFieldStyle())

                Stepper(value: $viewModel.maxArticlesPerScan, in: 1...500, step: 10) {
                    Text("文章上限：\(viewModel.maxArticlesPerScan)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                Button {
                    viewModel.saveAISettings()
                } label: {
                    Label("保存配置", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(viewModel.isWorking)
            }
        }
    }

    private var scanCard: some View {
        OnboardingCard(number: "3", title: "首次扫描", systemImage: "play.circle") {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.scanSummary)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)

                    Text("扫描会使用本地处理队列，并隔离单个任务失败。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.softText)
                }

                Spacer()

                Button {
                    Task {
                        await viewModel.startFirstScan()
                    }
                } label: {
                    Label(viewModel.isWorking ? "处理中" : "开始扫描", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(viewModel.isWorking)
            }
        }
    }

    private var candidateSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("待确认主题")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.brandGreen)

            if viewModel.candidatePreviews.isEmpty {
                EmptyCandidateView()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(viewModel.candidatePreviews, id: \.topic.id) { preview in
                        CandidatePreviewTile(preview: preview)
                    }
                }
            }
        }
        .frame(maxWidth: 1120, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.bottom, 88)
    }
}

private struct OnboardingCard<Content: View>: View {
    let number: String
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(number)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.accentGreen)
                    .clipShape(Circle())

                Label(title, systemImage: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(22)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 0.5)
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }
}

private struct CandidatePreviewTile: View {
    let preview: CandidateTopicPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.topic.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)

            Text(preview.previewBrief?.currentTakeaway ?? preview.topic.description)
                .font(.system(size: 14))
                .foregroundStyle(Theme.softText)
                .lineLimit(4)

            HStack {
                Label("\(preview.articleCount)", systemImage: "doc.text")
                Spacer()
            Text(preview.topic.status.appDisplayName)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.brandGreen)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 0.5)
        .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
    }
}

private struct EmptyCandidateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("暂无待确认主题", systemImage: "tray")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("文章分析和主题归类任务产出结果后，待确认主题会显示在这里。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.softText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StatusBanner: View {
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OnboardingTextFieldStyle: TextFieldStyle {
    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.accentGreen)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

private struct OutlinePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accentGreen)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(
                Capsule().stroke(Theme.accentGreen, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

private struct FloatingActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Theme.accentGreen)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.24), radius: 6)
            .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.14), radius: 12, y: 8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

private enum Theme {
    static let canvas = Color(red: 0.95, green: 0.94, blue: 0.92)
    static let brandGreen = Color(red: 0.0, green: 0.38, blue: 0.25)
    static let accentGreen = Color(red: 0.0, green: 0.46, blue: 0.29)
    static let houseGreen = Color(red: 0.12, green: 0.22, blue: 0.20)
    static let text = Color.black.opacity(0.87)
    static let softText = Color.black.opacity(0.58)
    static let error = Color(red: 0.78, green: 0.13, blue: 0.08)
}
