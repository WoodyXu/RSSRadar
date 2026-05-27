import Foundation
import RSSRadarProcessing

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var snapshot: TodayPageSnapshot?
    @Published var selectedTopicID: String?
    @Published var selectedTopicDetail: TopicDetailSnapshot?
    @Published var isWorking = false
    @Published var statusMessage = "Today is ready."
    @Published var errorMessage: String?

    private let environment: AppEnvironment
    private let todayDataSource: TodayPageDataSource
    private let topicDetailDataSource: TopicDetailDataSource

    init(environment: AppEnvironment) {
        self.environment = environment
        todayDataSource = TodayPageDataSource(repositories: environment.repositories)
        topicDetailDataSource = TopicDetailDataSource(repositories: environment.repositories)
    }

    func load() {
        runSync {
            snapshot = try todayDataSource.load()
            statusMessage = "Today refreshed \(Date().appShortDate)."
            if selectedTopicID == nil {
                selectedTopicID = snapshot?.importantTopics.first?.topic.id
                    ?? snapshot?.newCandidateTopics.first?.topic.id
                    ?? snapshot?.trackedTopicUpdates.first?.topic.id
            }
            try loadSelectedTopicDetail()
        }
    }

    func select(topicID: String) {
        runSync {
            selectedTopicID = topicID
            try loadSelectedTopicDetail()
        }
    }

    private func loadSelectedTopicDetail() throws {
        guard let selectedTopicID else {
            selectedTopicDetail = nil
            return
        }
        selectedTopicDetail = try topicDetailDataSource.load(topicID: selectedTopicID)
    }

    private func runSync(_ operation: () throws -> Void) {
        guard !isWorking else {
            return
        }
        isWorking = true
        errorMessage = nil
        do {
            try operation()
        } catch {
            errorMessage = AppViewModelErrorMessage.message(from: error)
        }
        isWorking = false
    }
}
