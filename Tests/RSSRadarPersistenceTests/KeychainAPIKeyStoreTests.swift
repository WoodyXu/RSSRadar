import XCTest
@testable import RSSRadarPersistence

final class KeychainAPIKeyStoreTests: XCTestCase {
    private var store: KeychainAPIKeyStore!
    private var accountIdentifiers: [String] = []

    override func setUp() {
        super.setUp()
        store = KeychainAPIKeyStore(service: "com.rssradar.tests.\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        for accountIdentifier in accountIdentifiers {
            try store.deleteAPIKey(accountIdentifier: accountIdentifier)
        }
        accountIdentifiers = []
        store = nil
        try super.tearDownWithError()
    }

    func testSaveReadReplaceAndDeleteAPIKey() throws {
        let accountIdentifier = makeAccountIdentifier()

        try store.saveAPIKey("first-secret", accountIdentifier: accountIdentifier)
        XCTAssertEqual(try store.readAPIKey(accountIdentifier: accountIdentifier), "first-secret")

        try store.saveAPIKey("replacement-secret", accountIdentifier: accountIdentifier)
        XCTAssertEqual(try store.readAPIKey(accountIdentifier: accountIdentifier), "replacement-secret")

        try store.deleteAPIKey(accountIdentifier: accountIdentifier)
        XCTAssertNil(try store.readAPIKey(accountIdentifier: accountIdentifier))
    }

    func testDeleteMissingAPIKeyDoesNotThrow() throws {
        try store.deleteAPIKey(accountIdentifier: makeAccountIdentifier())
    }

    func testValidationRejectsEmptyInputs() throws {
        XCTAssertThrowsError(try store.saveAPIKey("secret", accountIdentifier: "  \n")) { error in
            XCTAssertEqual(error as? KeychainAPIKeyStoreError, .emptyAccountIdentifier)
        }
        XCTAssertThrowsError(try store.saveAPIKey("", accountIdentifier: makeAccountIdentifier())) { error in
            XCTAssertEqual(error as? KeychainAPIKeyStoreError, .emptyAPIKey)
        }
        XCTAssertThrowsError(try store.readAPIKey(accountIdentifier: "")) { error in
            XCTAssertEqual(error as? KeychainAPIKeyStoreError, .emptyAccountIdentifier)
        }
    }

    func testAccountIdentifierGenerationDoesNotExposeAPIKey() {
        let secretAPIKey = "sk-test-secret-value"
        let accountIdentifier = KeychainAPIKeyStore.makeAccountIdentifier()

        XCTAssertTrue(accountIdentifier.hasPrefix("api-key-"))
        XCTAssertFalse(accountIdentifier.contains(secretAPIKey))
    }

    func testErrorsDoNotExposeAPIKeyPlaintext() throws {
        let secretAPIKey = "sk-test-secret-value"

        XCTAssertThrowsError(try store.saveAPIKey(secretAPIKey, accountIdentifier: "")) { error in
            XCTAssertFalse(String(describing: error).contains(secretAPIKey))
            XCTAssertFalse((error.localizedDescription).contains(secretAPIKey))
        }
    }

    private func makeAccountIdentifier() -> String {
        let accountIdentifier = KeychainAPIKeyStore.makeAccountIdentifier()
        accountIdentifiers.append(accountIdentifier)
        return accountIdentifier
    }
}
