import SwiftUI

struct AppRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selection: RSSRadarSection? = .today
    @StateObject private var onboardingViewModel: OnboardingViewModel
    @StateObject private var todayViewModel: TodayViewModel
    @StateObject private var topicsViewModel: TopicsViewModel
    @StateObject private var feedsViewModel: FeedsViewModel
    @StateObject private var processingViewModel: ProcessingViewModel
    @StateObject private var settingsViewModel: SettingsViewModel

    init(environment: AppEnvironment) {
        _onboardingViewModel = StateObject(wrappedValue: OnboardingViewModel(environment: environment))
        _todayViewModel = StateObject(wrappedValue: TodayViewModel(environment: environment))
        _topicsViewModel = StateObject(wrappedValue: TopicsViewModel(environment: environment))
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
                    TodayView(viewModel: todayViewModel)
                case .topics:
                    TopicsView(viewModel: topicsViewModel)
                case .feeds:
                    FeedsView(viewModel: feedsViewModel)
                case .processing:
                    ProcessingView(viewModel: processingViewModel) {
                        selection = .settings
                    }
                case .settings:
                    SettingsView(viewModel: settingsViewModel)
                case .none:
                    TodayView(viewModel: todayViewModel)
                }
            }
        } else {
            OnboardingView(viewModel: onboardingViewModel) {
                hasCompletedOnboarding = true
            }
        }
    }
}
