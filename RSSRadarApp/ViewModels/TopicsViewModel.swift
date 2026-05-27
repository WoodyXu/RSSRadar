import Foundation
import RSSRadarCore
import RSSRadarProcessing

@MainActor
final class TopicsViewModel: ObservableObject {
    @Published var topics: [Topic] = []
    @Published var selectedTopicID: String?
    @Published var selectedTopicDetail: TopicDetailSnapshot?
    @Published var selectedStatus: TopicStatus?
    @Published var isWorking = false
    @Published var statusMessage = "Topics are ready."
    @Published var errorMessage: String?

    private let environment: AppEnvironment
    private let topicDetailDataSource: TopicDetailDataSource

    init(environment: AppEnvironment) {
        self.environment = environment
        topicDetailDataSource = TopicDetailDataSource(repositories: environment.repositories)
    }

    var filteredTopics: [Topic] {
        guard let selectedStatus else {
            return topics
        }
        return topics.filter { $0.status == selectedStatus }
    }

    func count(for status: TopicStatus) -> Int {
        topics.filter { $0.status == status }.count
    }

    func load() {
        runSync {
            try refreshTopics()
            if selectedTopicID == nil || filteredTopics.contains(where: { $0.id == selectedTopicID }) == false {
                selectedTopicID = filteredTopics.first?.id
            }
            try loadSelectedTopicDetail()
            statusMessage = topics.isEmpty ? "No topics have been generated yet." : "\(topics.count) topics saved."
        }
    }

    func select(topicID: String) {
        runSync {
            selectedTopicID = topicID
            try loadSelectedTopicDetail()
        }
    }

    func setStatusFilter(_ status: TopicStatus?) {
        runSync {
            selectedStatus = status
            selectedTopicID = filteredTopics.first?.id
            try loadSelectedTopicDetail()
        }
    }

    func trackSelectedCandidate() {
        updateSelectedCandidateStatus { topicID in
            try environment.candidateTopicManagementUseCase.trackCandidate(id: topicID)
        }
    }

    func ignoreSelectedCandidate() {
        updateSelectedCandidateStatus { topicID in
            try environment.candidateTopicManagementUseCase.ignoreCandidate(id: topicID)
        }
    }

    private func refreshTopics() throws {
        topics = try environment.repositories.topics.fetchAll()
    }

    private func loadSelectedTopicDetail() throws {
        guard let selectedTopicID else {
            selectedTopicDetail = nil
            return
        }
        selectedTopicDetail = try topicDetailDataSource.load(topicID: selectedTopicID)
    }

    private func updateSelectedCandidateStatus(_ update: (String) throws -> Topic) {
        runSync {
            guard let topicID = selectedTopicID else {
                return
            }

            let updatedTopic = try update(topicID)
            try refreshTopics()
            if selectedStatus.map({ $0 != updatedTopic.status }) == true {
                selectedTopicID = filteredTopics.first?.id
            } else {
                selectedTopicID = updatedTopic.id
            }
            try loadSelectedTopicDetail()
            statusMessage = "\(updatedTopic.name) is now \(updatedTopic.status.appDisplayName)."
        }
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
