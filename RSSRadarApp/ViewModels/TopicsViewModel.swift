import Foundation
import RSSRadarCore
import RSSRadarProcessing

@MainActor
final class TopicsViewModel: ObservableObject {
    enum BriefExtractionState: Equatable {
        case extracting
        case success
        case failure(String)

        var displayText: String {
            switch self {
            case .extracting:
                "萃取中"
            case .success:
                "成功"
            case let .failure(reason):
                "失败：\(reason)"
            }
        }
    }

    @Published var topics: [Topic] = []
    @Published var selectedTopicID: String?
    @Published var selectedTopicDetail: TopicDetailSnapshot?
    @Published var selectedStatus: TopicStatus?
    @Published var isWorking = false
    @Published var statusMessage = "主题聚合已就绪。"
    @Published var errorMessage: String?
    @Published var briefExtractionState: BriefExtractionState?

    private let environment: AppEnvironment
    private let topicDetailDataSource: TopicDetailDataSource

    init(environment: AppEnvironment) {
        self.environment = environment
        topicDetailDataSource = TopicDetailDataSource(repositories: environment.repositories)
    }

    var filteredTopics: [Topic] {
        let visibleTopics = topics.filter { $0.status != .archived }
        guard let selectedStatus else {
            return visibleTopics
        }
        return visibleTopics.filter { $0.status == selectedStatus }
    }

    var visibleTopicCount: Int {
        topics.filter { $0.status != .archived }.count
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
            briefExtractionState = nil
            statusMessage = topics.isEmpty ? "还没有生成主题。" : "已保存 \(visibleTopicCount) 个可见主题。"
        }
    }

    func select(topicID: String) {
        runSync {
            selectedTopicID = topicID
            try loadSelectedTopicDetail()
            briefExtractionState = nil
        }
    }

    func setStatusFilter(_ status: TopicStatus?) {
        runSync {
            selectedStatus = status
            selectedTopicID = filteredTopics.first?.id
            try loadSelectedTopicDetail()
            briefExtractionState = nil
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

    func extractSelectedTopicBrief() {
        guard !isWorking else {
            return
        }
        isWorking = true
        briefExtractionState = .extracting
        errorMessage = nil

        Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                self.isWorking = false
            }
            do {
                guard let topicID = self.selectedTopicID else {
                    self.briefExtractionState = .failure("未选择主题")
                    return
                }
                guard let topic = try self.environment.repositories.topics.fetch(id: topicID),
                      topic.status == .active else {
                    self.briefExtractionState = .failure("当前主题不可萃取")
                    return
                }
                let settings = try self.environment.repositories.appSettings.fetch()
                let useCase = try self.environment.makeTopicBriefGenerationUseCase()
                _ = try await useCase.regenerate(
                    topicID: topicID,
                    briefType: .full,
                    modelName: settings.modelName
                )
                try self.loadSelectedTopicDetail()
                self.briefExtractionState = .success
                self.statusMessage = "\(topic.name) 已完成主题动态总结。"
            } catch {
                self.briefExtractionState = .failure(AppViewModelErrorMessage.message(from: error))
                self.errorMessage = AppViewModelErrorMessage.message(from: error)
            }
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
            briefExtractionState = nil
            statusMessage = "\(updatedTopic.name) 已更新为\(updatedTopic.status.appDisplayName)。"
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
