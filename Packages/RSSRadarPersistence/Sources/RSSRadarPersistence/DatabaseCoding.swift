import Foundation
import GRDB

enum DatabaseCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        iso8601WithFractionalSeconds.string(from: date)
    }

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return iso8601WithFractionalSeconds.date(from: value) ?? iso8601.date(from: value)
    }

    static func jsonString<T: Encodable>(from value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RSSRadarRepositoryError.invalidJSONString
        }
        return string
    }

    static func value<T: Decodable>(fromJSONString string: String) throws -> T {
        let data = Data(string.utf8)
        return try decoder.decode(T.self, from: data)
    }
}

public enum RSSRadarRepositoryError: Error, Equatable {
    case missingRequiredColumn(String)
    case invalidURL(String)
    case invalidDate(String)
    case invalidJSONString
    case sensitiveLogContent
}

extension Row {
    func requiredString(_ column: String) throws -> String {
        guard let value: String = self[column] else {
            throw RSSRadarRepositoryError.missingRequiredColumn(column)
        }
        return value
    }

    func requiredDouble(_ column: String) throws -> Double {
        guard let value: Double = self[column] else {
            throw RSSRadarRepositoryError.missingRequiredColumn(column)
        }
        return value
    }

    func requiredInt(_ column: String) throws -> Int {
        guard let value: Int = self[column] else {
            throw RSSRadarRepositoryError.missingRequiredColumn(column)
        }
        return value
    }

    func requiredDate(_ column: String) throws -> Date {
        let value = try requiredString(column)
        guard let date = DatabaseCoding.date(from: value) else {
            throw RSSRadarRepositoryError.invalidDate(value)
        }
        return date
    }

    func optionalDate(_ column: String) throws -> Date? {
        let value: String? = self[column]
        guard value != nil else { return nil }
        guard let date = DatabaseCoding.date(from: value) else {
            throw RSSRadarRepositoryError.invalidDate(value ?? "")
        }
        return date
    }

    func requiredURL(_ column: String) throws -> URL {
        let value = try requiredString(column)
        guard let url = URL(string: value) else {
            throw RSSRadarRepositoryError.invalidURL(value)
        }
        return url
    }

    func optionalURL(_ column: String) throws -> URL? {
        let value: String? = self[column]
        guard let value else { return nil }
        guard let url = URL(string: value) else {
            throw RSSRadarRepositoryError.invalidURL(value)
        }
        return url
    }
}
