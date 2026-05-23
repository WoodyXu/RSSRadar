import Foundation
import RSSRadarCore
import RSSRadarPersistence

public struct ProcessingStartupRecoveryUseCase {
    private let repositories: RSSRadarRepositories

    public init(repositories: RSSRadarRepositories) {
        self.repositories = repositories
    }

    @discardableResult
    public func recover(now: Date = Date()) throws -> Int {
        let recoveredCount = try repositories.processingJobs.recoverInterruptedJobs(
            scheduledAt: now,
            updatedAt: now
        )
        if recoveredCount > 0 {
            try repositories.operationLogs.save(
                OperationLog(
                    level: .warning,
                    message: "Recovered interrupted processing jobs",
                    context: ["recovered_count": String(recoveredCount)],
                    createdAt: now
                )
            )
        }
        return recoveredCount
    }
}
