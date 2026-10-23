import XCTest
@testable import JellyfinKit

final class LocalCredentialTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var directory: URL!
    private var store: CredentialStore!

    override func setUpWithError() throws {
        suite = "LocalCredentialTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = CredentialStore(defaults: defaults, localDirectory: directory)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func session(_ host: String, token: String) -> ServerSession {
        ServerSession(serverURL: URL(string: "http://\(host):8096")!, userId: "same-user",
                      userName: "User", accessToken: token)
    }

    func testLocalFileIsDefaultForNewSetups() throws {
        XCTAssertEqual(store.storage, .localFile)
        try store.save(session("one.example", token: "one"))
        XCTAssertEqual(try store.loadSession()?.accessToken, "one")
    }

    func testExplicitKeychainSelectionIsPreservedAndMigrationCopiesLoadedTokens() throws {
        defaults.set(CredentialStorage.keychain.rawValue, forKey: CredentialStore.storageKey)
        XCTAssertEqual(store.storage, .keychain)
        let first = session("one.example", token: "one")
        let second = session("two.example", token: "two")
        try store.changeStorage(to: .localFile, sessions: [first, second])
        XCTAssertEqual(store.storage, .localFile)
        XCTAssertEqual(try LocalCredentialFile(directory: directory).read(), [first.id: "one", second.id: "two"])
    }

    func testLocalSaveReloadUpdateAndRemove() throws {
        try store.changeStorage(to: .localFile, sessions: [])
        let first = session("one.example", token: "one")
        let second = session("two.example", token: "two")
        try store.save(first)
        try store.save(second)
        let reloaded = CredentialStore(defaults: defaults, localDirectory: directory)
        XCTAssertEqual(try reloaded.loadSessions().count, 2)
        XCTAssertEqual(try reloaded.loadSession()?.id, second.id)
        try reloaded.save(session("one.example", token: "updated"))
        XCTAssertEqual(try reloaded.loadSession()?.accessToken, "updated")
        try reloaded.remove(first)
        XCTAssertEqual(try reloaded.loadSession()?.id, second.id)
        try reloaded.clear()
        XCTAssertTrue(try reloaded.loadSessions().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reloaded.localFileURL.path))
        let metadata = defaults.data(forKey: "solfin.sessions")
        XCTAssertNil(metadata)
    }

    func testTokensNeverAppearInUserDefaultsMetadata() throws {
        try store.changeStorage(to: .localFile, sessions: [])
        try store.save(session("one.example", token: "VERY_SECRET_TOKEN"))
        let metadata = try XCTUnwrap(defaults.data(forKey: "solfin.sessions"))
        XCTAssertFalse(String(decoding: metadata, as: UTF8.self).contains("VERY_SECRET_TOKEN"))
    }

    func testOwnerOnlyPermissionsSurviveReplacementAndAreRepairedOnRead() throws {
        let file = LocalCredentialFile(directory: directory)
        try file.write(["account": "one"])
        try file.write(["account": "two"])
        func permissions(_ url: URL) throws -> Int {
            (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
        }
        XCTAssertEqual(try permissions(directory), 0o700)
        XCTAssertEqual(try permissions(file.url), 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.url.path)
        XCTAssertEqual(try file.read()["account"], "two")
        XCTAssertEqual(try permissions(file.url), 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["credentials.json"])
    }

    func testCorruptFileIsNotSilentlyOverwritten() throws {
        try store.save(session("one.example", token: "original"))
        let data = Data("not json".utf8)
        try data.write(to: store.localFileURL)
        XCTAssertThrowsError(try store.loadSessions())
        XCTAssertThrowsError(try store.save(session("one.example", token: "one")))
        XCTAssertEqual(try Data(contentsOf: store.localFileURL), data)
    }

    func testFailedMigrationLeavesModeUnchanged() throws {
        defaults.set(CredentialStorage.keychain.rawValue, forKey: CredentialStore.storageKey)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        let blockedStore = CredentialStore(defaults: defaults, localDirectory: blocked)
        XCTAssertThrowsError(try blockedStore.changeStorage(to: .localFile, sessions: [session("one.example", token: "one")]))
        XCTAssertEqual(blockedStore.storage, .keychain)
    }

    func testMigrationRejectsUnavailableSavedCredentials() throws {
        defaults.set(CredentialStorage.keychain.rawValue, forKey: CredentialStore.storageKey)
        var meta = session("one.example", token: "")
        meta.accessToken = ""
        defaults.set(try JSONEncoder().encode([meta]), forKey: "solfin.sessions")
        XCTAssertThrowsError(try store.changeStorage(to: .localFile, sessions: []))
        XCTAssertEqual(store.storage, .keychain)
    }

    func testPreexistingKeychainMetadataKeepsKeychainMode() throws {
        defaults.removeObject(forKey: CredentialStore.storageKey)
        defaults.set(try JSONEncoder().encode([session("one.example", token: "")]), forKey: "solfin.sessions")
        let existingStore = CredentialStore(defaults: defaults, localDirectory: directory)
        XCTAssertEqual(existingStore.storage, .keychain)
        defaults.set(CredentialStorage.localFile.rawValue, forKey: CredentialStore.storageKey)
        XCTAssertEqual(CredentialStore(defaults: defaults, localDirectory: directory).storage, .localFile)
    }

    func testLocalModeDoesNotAttemptLegacyKeychainMigration() throws {
        defaults.set(CredentialStorage.localFile.rawValue, forKey: CredentialStore.storageKey)
        defaults.set(try JSONEncoder().encode(session("one.example", token: "")), forKey: "solfin.session")
        XCTAssertTrue(try store.loadSessions().isEmpty)
    }
}
