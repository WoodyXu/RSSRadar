import SwiftUI

struct AppRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selection: RSSRadarSection? = .today
    @StateObject private var onboardingViewModel: OnboardingViewModel
    @StateObject private var feedsViewModel: FeedsViewModel
    @StateObject private var processingViewModel: ProcessingViewModel
    @StateObject private var settingsViewModel: SettingsViewModel

    init(environment: AppEnvironment) {
        _onboardingViewModel = StateObject(wrappedValue: OnboardingViewModel(environment: environment))
        _feedsViewModel = StateObject(wrappedValue: FeedsViewModel(environment: environment))
        _processingViewModel = StateObject(wrappedValue: ProcessingViewModel(environment: environment))
        _settingsViewModel = StateObject(wrappedValue: SettingsViewModel(environment: environment))
    }

    var body: some View {
        if hasCompletedOnboarding {
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(RSSRadarSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                .navigationTitle("RSSRadar")
            } detail: {
                switch selection {
                case .today:
                    PlaceholderView(title: "Today")
                case .topics:
                    PlaceholderView(title: "Topics")
                case .feeds:
                    FeedsView(viewModel: feedsViewModel)
                case .processing:
                    ProcessingView(viewModel: processingViewModel) {
                        selection = .settings
                    }
                case .settings:
                    SettingsView(viewModel: settingsViewModel)
                case .none:
                    PlaceholderView(title: "Today")
                }
            }
        } else {
            OnboardingView(viewModel: onboardingViewModel) {
                hasCompletedOnboarding = true
            }
        }
    }
}

private struct PlaceholderView: View {
    let title: String

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.94, blue: 0.92)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(red: 0, green: 0.38, blue: 0.25))

                Text("RSSRadar MVP workspace")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(32)
        }
    }
}
