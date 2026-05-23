enum SensitiveContentValidator {
    private static let markers = [
        "api_key",
        "api key",
        "authorization",
        "bearer ",
        "x-api-key",
        "sk-"
    ]

    static func validate(_ values: [String]) throws {
        let containsSensitiveMarker = values.contains { value in
            let normalized = value.lowercased()
            return markers.contains { normalized.contains($0) }
        }

        if containsSensitiveMarker {
            throw RSSRadarRepositoryError.sensitiveLogContent
        }
    }
}
