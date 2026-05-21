import Foundation
import Security

public enum KeychainAPIKeyStoreError: Error, Equatable, LocalizedError {
    case emptyAccountIdentifier
    case emptyAPIKey
    case invalidStoredData
    case unhandledStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .emptyAccountIdentifier:
            "Keychain account identifier cannot be empty."
        case .emptyAPIKey:
            "API key cannot be empty."
        case .invalidStoredData:
            "Stored API key data could not be decoded."
        case let .unhandledStatus(status):
            "Keychain operation failed with status \(status)."
        }
    }
}

public final class KeychainAPIKeyStore {
    public static let defaultService = "com.rssradar.api-key"

    private let service: String

    public init(service: String = KeychainAPIKeyStore.defaultService) {
        self.service = service
    }

    public static func makeAccountIdentifier() -> String {
        "api-key-\(UUID().uuidString)"
    }

    public func saveAPIKey(_ apiKey: String, accountIdentifier: String) throws {
        let accountIdentifier = try validatedAccountIdentifier(accountIdentifier)
        let apiKey = try validatedAPIKey(apiKey)
        let data = Data(apiKey.utf8)
        let query = baseQuery(accountIdentifier: accountIdentifier)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainAPIKeyStoreError.unhandledStatus(addStatus)
            }
        default:
            throw KeychainAPIKeyStoreError.unhandledStatus(updateStatus)
        }
    }

    public func readAPIKey(accountIdentifier: String) throws -> String? {
        let accountIdentifier = try validatedAccountIdentifier(accountIdentifier)
        var query = baseQuery(accountIdentifier: accountIdentifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let apiKey = String(data: data, encoding: .utf8) else {
                throw KeychainAPIKeyStoreError.invalidStoredData
            }
            return apiKey
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainAPIKeyStoreError.unhandledStatus(status)
        }
    }

    public func deleteAPIKey(accountIdentifier: String) throws {
        let accountIdentifier = try validatedAccountIdentifier(accountIdentifier)
        let status = SecItemDelete(baseQuery(accountIdentifier: accountIdentifier) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainAPIKeyStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(accountIdentifier: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountIdentifier
        ]
    }

    private func validatedAccountIdentifier(_ accountIdentifier: String) throws -> String {
        let trimmed = accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KeychainAPIKeyStoreError.emptyAccountIdentifier
        }
        return trimmed
    }

    private func validatedAPIKey(_ apiKey: String) throws -> String {
        guard !apiKey.isEmpty else {
            throw KeychainAPIKeyStoreError.emptyAPIKey
        }
        return apiKey
    }
}
