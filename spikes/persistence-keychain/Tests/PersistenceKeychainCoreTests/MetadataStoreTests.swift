import Foundation
import XCTest

@testable import PersistenceKeychainCore

final class MetadataStoreTests: XCTestCase {
  private var rootURL: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("dataforge-m0-007-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: rootURL.path)
  }

  override func tearDownWithError() throws {
    if let rootURL, FileManager.default.fileExists(atPath: rootURL.path) {
      try FileManager.default.removeItem(at: rootURL)
    }
    try super.tearDownWithError()
  }

  func testV1UpgradeRetainsRowsAndAddsDeterministicHistoryKind() throws {
    let databaseURL = rootURL.appendingPathComponent("upgrade.sqlite")
    let profile = makeProfile()
    let workspace = WorkspaceRecord(
      id: UUID(),
      profileID: profile.id,
      title: "workspace",
      updatedAtMilliseconds: 10)
    let historyID = UUID()

    let v1 = try MetadataStore(
      databaseURL: databaseURL,
      mode: .deleteQueue,
      historyLimit: 20,
      schemaTarget: .v1)
    try v1.saveProfile(profile)
    try v1.saveWorkspace(workspace)
    try v1.insertV1HistoryForProbe(
      id: historyID,
      profileID: profile.id,
      executedAtMilliseconds: 1)
    try v1.close()

    let latest = try MetadataStore(
      databaseURL: databaseURL,
      mode: .deleteQueue,
      historyLimit: 20)
    XCTAssertEqual(try latest.profile(id: profile.id), profile)
    XCTAssertEqual(try latest.workspace(id: workspace.id), workspace)
    XCTAssertEqual(
      try latest.history(),
      [
        QueryHistoryRecord(
          id: historyID,
          profileID: profile.id,
          executedAtMilliseconds: 1,
          operationKind: "query")
      ])
    XCTAssertEqual(
      try latest.completedMigrationIdentifiers(),
      [MetadataStore.migrationV1, MetadataStore.migrationV2])
    try latest.close()
  }

  func testFailedMigrationRollsBackSchemaAndMarker() throws {
    let store = try MetadataStore(
      databaseURL: rootURL.appendingPathComponent("failure.sqlite"),
      mode: .deleteQueue,
      historyLimit: 20)
    XCTAssertThrowsError(try store.runDeliberatelyFailingMigration()) { error in
      XCTAssertEqual(error as? MetadataStoreError, .deliberateMigrationFailure)
    }
    XCTAssertFalse(try store.failedMigrationArtifactsExist())
    XCTAssertEqual(
      try store.completedMigrationIdentifiers(),
      [MetadataStore.migrationV1, MetadataStore.migrationV2])
    try store.close()
  }

  func testFutureMigrationRefusesWithoutRebuild() throws {
    let databaseURL = rootURL.appendingPathComponent("future.sqlite")
    let store = try MetadataStore(
      databaseURL: databaseURL,
      mode: .deleteQueue,
      historyLimit: 20)
    try store.seedFutureMigrationMarkerForProbe("future_v3")
    try store.close()
    let before = try Data(contentsOf: databaseURL)

    XCTAssertThrowsError(
      try MetadataStore(
        databaseURL: databaseURL,
        mode: .deleteQueue,
        historyLimit: 20)
    ) { error in
      XCTAssertEqual(error as? MetadataStoreError, .futureMigration(["future_v3"]))
    }
    XCTAssertEqual(try Data(contentsOf: databaseURL), before)
  }

  func testCorruptionFailsClosedAndOriginalRemainsReadable() throws {
    let originalURL = rootURL.appendingPathComponent("original.sqlite")
    let corruptURL = rootURL.appendingPathComponent("corrupt.sqlite")
    let profile = makeProfile()
    let store = try MetadataStore(
      databaseURL: originalURL,
      mode: .deleteQueue,
      historyLimit: 20)
    try store.saveProfile(profile)
    try store.close()
    try FileManager.default.copyItem(at: originalURL, to: corruptURL)
    let handle = try FileHandle(forWritingTo: corruptURL)
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: Data("not-a-sqlite-db!".utf8))
    try handle.close()

    XCTAssertThrowsError(
      try MetadataStore(
        databaseURL: corruptURL,
        mode: .deleteQueue,
        historyLimit: 20)
    ) { error in
      XCTAssertEqual(error as? MetadataStoreError, .corruptDatabase)
    }
    let reopened = try MetadataStore(
      databaseURL: originalURL,
      mode: .deleteQueue,
      historyLimit: 20)
    try reopened.verifyIntegrity()
    XCTAssertEqual(try reopened.profile(id: profile.id), profile)
    try reopened.close()
  }

  func testRetentionIsBoundedAndIndependentFromProfile() throws {
    let profile = makeProfile()
    let store = try MetadataStore(
      databaseURL: rootURL.appendingPathComponent("retention.sqlite"),
      mode: .walPool,
      historyLimit: 3)
    try store.saveProfile(profile)
    for value in 0..<10 {
      try store.appendHistory(
        QueryHistoryRecord(
          id: UUID(),
          profileID: profile.id,
          executedAtMilliseconds: Int64(value),
          operationKind: "test"))
    }
    XCTAssertEqual(try store.history().count, 3)
    XCTAssertEqual(try store.profile(id: profile.id), profile)
    try store.deleteAllHistory()
    XCTAssertTrue(try store.history().isEmpty)
    XCTAssertEqual(try store.profile(id: profile.id), profile)
    try store.close()
  }

  func testBackupPassesIntegrityAndPreservesRows() throws {
    let profile = makeProfile()
    let sourceURL = rootURL.appendingPathComponent("source.sqlite")
    let backupURL = rootURL.appendingPathComponent("backup.sqlite")
    let source = try MetadataStore(
      databaseURL: sourceURL,
      mode: .walPool,
      historyLimit: 20)
    try source.saveProfile(profile)
    try source.backup(to: backupURL)
    let backup = try MetadataStore(
      databaseURL: backupURL,
      mode: .deleteQueue,
      historyLimit: 20)
    try backup.verifyIntegrity()
    XCTAssertEqual(try backup.profile(id: profile.id), profile)
    try backup.close()
    try source.close()
  }

  func testSchemaSnapshotHasNoSecretColumnsAndRecordsForeignKeys() throws {
    let store = try MetadataStore(
      databaseURL: rootURL.appendingPathComponent("schema.sqlite"),
      mode: .deleteQueue,
      historyLimit: 20)
    let snapshot = try store.schemaSnapshot()
    XCTAssertEqual(
      snapshot.tables["connection_profiles"],
      [
        "id",
        "display_name",
        "host",
        "port",
        "environment",
        "read_only",
        "credential_reference",
      ])
    let columns = snapshot.tables.values.flatMap { $0 }.joined(separator: " ").lowercased()
    XCTAssertFalse(columns.contains("password"))
    XCTAssertFalse(columns.contains("token"))
    XCTAssertFalse(snapshot.foreignKeys["workspaces", default: []].isEmpty)
    try store.close()
  }

  private func makeProfile() -> ConnectionProfile {
    ConnectionProfile(
      id: UUID(),
      displayName: "synthetic",
      host: "127.0.0.1",
      port: 5432,
      environment: .development,
      readOnly: true,
      credentialReference: CredentialReference(rawValue: UUID()))
  }
}
