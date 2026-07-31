import Dispatch
import Foundation
import PersistenceKeychainCore
import Security

enum PersistenceProbe {
  static func run(arguments: RunArguments) throws -> ProbeReport {
    try prepareRoot(arguments.rootURL)
    let secretData = try readOwnedCanary(arguments.secretFileURL)
    let credentialReference = CredentialReference(rawValue: UUID())
    let profile = ConnectionProfile(
      id: UUID(),
      displayName: "Synthetic production-like profile",
      host: "127.0.0.1",
      port: 5_432,
      environment: .production,
      readOnly: true,
      credentialReference: credentialReference)
    let workspace = WorkspaceRecord(
      id: UUID(),
      profileID: profile.id,
      title: "Synthetic workspace",
      updatedAtMilliseconds: 1_785_436_800_000)
    let legacyHistoryID = UUID()

    var scenarios: [ScenarioEvidence] = []
    var measurements: [String: Int64] = [:]

    let migrationURL = arguments.rootURL.appendingPathComponent("migration.sqlite")
    let v1Store = try MetadataStore(
      databaseURL: migrationURL,
      mode: .deleteQueue,
      historyLimit: 50,
      schemaTarget: .v1)
    try v1Store.saveProfile(profile)
    try v1Store.saveWorkspace(workspace)
    try v1Store.insertV1HistoryForProbe(
      id: legacyHistoryID,
      profileID: profile.id,
      executedAtMilliseconds: 100)
    try require(
      try v1Store.completedMigrationIdentifiers() == [MetadataStore.migrationV1],
      "v1 migration marker mismatch")
    try v1Store.close()

    let migratedStore = try MetadataStore(
      databaseURL: migrationURL,
      mode: .deleteQueue,
      historyLimit: 50)
    try require(
      try migratedStore.profile(id: profile.id) == profile, "profile changed during migration")
    try require(
      try migratedStore.workspace(id: workspace.id) == workspace,
      "workspace changed during migration")
    let migratedHistory = try migratedStore.history()
    try require(
      migratedHistory == [
        QueryHistoryRecord(
          id: legacyHistoryID,
          profileID: profile.id,
          executedAtMilliseconds: 100,
          operationKind: "query")
      ],
      "legacy history did not receive deterministic default")
    try require(
      try migratedStore.completedMigrationIdentifiers()
        == [MetadataStore.migrationV1, MetadataStore.migrationV2],
      "latest migration markers mismatch")
    scenarios.append(
      pass(
        "MG-01",
        [
          "v1_to_v2": "atomic",
          "profile_workspace_history_retained": "true",
        ]))

    let schemaSnapshot = try migratedStore.schemaSnapshot()
    let prohibitedSchemaTerms = [
      "password",
      "passphrase",
      "private_key",
      "api_key",
      "access_token",
      "refresh_token",
      "client_secret",
      "secret_value",
    ]
    let allColumnNames = schemaSnapshot.tables.values.flatMap { $0 }
    for prohibited in prohibitedSchemaTerms {
      try require(
        !allColumnNames.contains(where: { $0.lowercased().contains(prohibited) }),
        "prohibited secret column exists")
    }
    try require(
      schemaSnapshot.tables["connection_profiles"]
        == [
          "id",
          "display_name",
          "host",
          "port",
          "environment",
          "read_only",
          "credential_reference",
        ],
      "profile schema allowlist mismatch")
    scenarios.append(
      pass(
        "MD-01",
        [
          "schema_allowlist_recorded": "true",
          "prohibited_secret_columns": "0",
          "credential_reference_format": "random_uuid",
        ]))

    do {
      try migratedStore.runDeliberatelyFailingMigration()
      throw ProbeError.invariantFailed("deliberate migration unexpectedly succeeded")
    } catch MetadataStoreError.deliberateMigrationFailure {
      // Expected: GRDB must roll back both schema and marker changes.
    }
    try require(
      try !migratedStore.failedMigrationArtifactsExist(),
      "failed migration left partial artifacts")
    try require(
      try migratedStore.completedMigrationIdentifiers()
        == [MetadataStore.migrationV1, MetadataStore.migrationV2],
      "failed migration left a marker")
    scenarios.append(
      pass(
        "MG-02",
        [
          "partial_table": "absent",
          "partial_data": "absent",
          "migration_marker": "absent",
        ]))

    let futureURL = arguments.rootURL.appendingPathComponent("future.sqlite")
    let futureStore = try MetadataStore(
      databaseURL: futureURL,
      mode: .deleteQueue,
      historyLimit: 10)
    try futureStore.saveProfile(profile)
    try futureStore.seedFutureMigrationMarkerForProbe("future_v3")
    try futureStore.close()
    let futureBefore = try Data(contentsOf: futureURL)
    var refusedFuture = false
    do {
      let unexpected = try MetadataStore(
        databaseURL: futureURL,
        mode: .deleteQueue,
        historyLimit: 10)
      try unexpected.close()
    } catch let MetadataStoreError.futureMigration(identifiers) {
      refusedFuture = identifiers == ["future_v3"]
    }
    let futureAfter = try Data(contentsOf: futureURL)
    try require(refusedFuture, "future migration was not refused")
    try require(futureBefore == futureAfter, "future migration refusal mutated the database")
    scenarios.append(
      pass(
        "MG-03",
        [
          "unknown_marker_refused": "true",
          "database_bytes_unchanged": "true",
          "auto_rebuild": "false",
        ]))

    let crashURL = arguments.rootURL.appendingPathComponent("crash.sqlite")
    let crashSeedStore = try MetadataStore(
      databaseURL: crashURL,
      mode: .walPool,
      historyLimit: 1_000)
    try crashSeedStore.saveProfile(profile)
    try crashSeedStore.close()
    let crashMarker = UUID()
    try runCrashWriter(databaseURL: crashURL, marker: crashMarker)
    let recoveredStore = try MetadataStore(
      databaseURL: crashURL,
      mode: .walPool,
      historyLimit: 1_000)
    try require(
      try !recoveredStore.containsHistory(id: crashMarker),
      "uncommitted crash row survived")
    try recoveredStore.verifyIntegrity()
    try recoveredStore.close()
    scenarios.append(
      pass(
        "TX-01",
        [
          "child_exit": String(MetadataStore.crashWriterExitCode),
          "uncommitted_row_present": "false",
          "integrity": "ok",
        ]))

    let originalURL = arguments.rootURL.appendingPathComponent("corruption-original.sqlite")
    let corruptedURL = arguments.rootURL.appendingPathComponent("corruption-copy.sqlite")
    let originalStore = try MetadataStore(
      databaseURL: originalURL,
      mode: .deleteQueue,
      historyLimit: 10)
    try originalStore.saveProfile(profile)
    try originalStore.close()
    try FileManager.default.copyItem(at: originalURL, to: corruptedURL)
    let corruptedHeader = Data("not-a-sqlite-db!".utf8)
    let corruptedHandle = try FileHandle(forWritingTo: corruptedURL)
    try corruptedHandle.seek(toOffset: 0)
    try corruptedHandle.write(contentsOf: corruptedHeader)
    try corruptedHandle.close()
    var corruptionRefused = false
    do {
      let unexpected = try MetadataStore(
        databaseURL: corruptedURL,
        mode: .deleteQueue,
        historyLimit: 10)
      try unexpected.close()
    } catch MetadataStoreError.corruptDatabase {
      corruptionRefused = true
    }
    try require(corruptionRefused, "corrupt database did not fail closed")
    let corruptedAfter = try Data(contentsOf: corruptedURL)
    try require(
      corruptedAfter.starts(with: corruptedHeader),
      "corrupt database was deleted or rebuilt")
    let originalReopened = try MetadataStore(
      databaseURL: originalURL,
      mode: .deleteQueue,
      historyLimit: 10)
    try originalReopened.verifyIntegrity()
    try require(
      try originalReopened.profile(id: profile.id) == profile,
      "original database changed during corruption probe")
    try originalReopened.close()
    scenarios.append(
      pass(
        "CR-01",
        [
          "corrupt_copy_refused": "true",
          "corrupt_copy_rebuilt": "false",
          "original_integrity": "ok",
        ]))

    let concurrencyURL = arguments.rootURL.appendingPathComponent("concurrency.sqlite")
    let concurrencyStore = try MetadataStore(
      databaseURL: concurrencyURL,
      mode: .walPool,
      historyLimit: 1_000)
    try concurrencyStore.saveProfile(profile)
    let concurrency = try runBoundedConcurrency(
      store: concurrencyStore,
      profileID: profile.id,
      workerCount: MetadataStore.maximumReaderCount,
      writesPerWorker: 25)
    try require(concurrency.completedWrites == 100, "concurrency write count mismatch")
    try require(try concurrencyStore.history().count == 100, "concurrency row count mismatch")
    try concurrencyStore.verifyIntegrity()
    measurements["concurrency_workers"] = Int64(MetadataStore.maximumReaderCount)
    measurements["concurrency_completed_writes"] = Int64(concurrency.completedWrites)
    scenarios.append(
      pass(
        "CO-01",
        [
          "maximum_readers": String(MetadataStore.maximumReaderCount),
          "fixed_workers": String(MetadataStore.maximumReaderCount),
          "completed_writes": String(concurrency.completedWrites),
          "errors": "0",
        ]))

    let retentionURL = arguments.rootURL.appendingPathComponent("retention.sqlite")
    let retentionStore = try MetadataStore(
      databaseURL: retentionURL,
      mode: .deleteQueue,
      historyLimit: 10)
    try retentionStore.saveProfile(profile)
    for index in 0..<25 {
      try retentionStore.appendHistory(
        QueryHistoryRecord(
          id: UUID(),
          profileID: profile.id,
          executedAtMilliseconds: Int64(index),
          operationKind: "query"))
    }
    let retained = try retentionStore.history()
    try require(retained.count == 10, "retention limit mismatch")
    try require(
      retained.map(\.executedAtMilliseconds) == Array((15...24).reversed()).map(Int64.init),
      "retention ordering mismatch")
    try require(try retentionStore.profile(id: profile.id) == profile, "retention deleted profile")
    scenarios.append(
      pass(
        "RT-01",
        [
          "inserted": "25",
          "retained": "10",
          "policy": "newest_then_id",
          "profile_retained": "true",
        ]))

    let backupURL = arguments.rootURL.appendingPathComponent("metadata-backup.sqlite")
    try migratedStore.backup(to: backupURL)
    let backupStore = try MetadataStore(
      databaseURL: backupURL,
      mode: .deleteQueue,
      historyLimit: 50)
    try backupStore.verifyIntegrity()
    try require(try backupStore.profile(id: profile.id) == profile, "backup lost profile")
    try require(try backupStore.workspace(id: workspace.id) == workspace, "backup lost workspace")
    try backupStore.close()
    scenarios.append(
      pass(
        "BK-01",
        [
          "checkpointed_online_backup": "true",
          "backup_integrity": "ok",
          "profile_workspace_retained": "true",
        ]))

    let deleteMeasurement = try measureJournalMode(
      .deleteQueue,
      rootURL: arguments.rootURL,
      profile: profile)
    let walMeasurement = try measureJournalMode(
      .walPool,
      rootURL: arguments.rootURL,
      profile: profile)
    try require(deleteMeasurement.observedMode == "delete", "DELETE journal mode mismatch")
    try require(walMeasurement.observedMode == "wal", "WAL journal mode mismatch")
    measurements["delete_duration_nanoseconds"] = deleteMeasurement.durationNanoseconds
    measurements["delete_open_bytes"] = deleteMeasurement.openBytes
    measurements["wal_duration_nanoseconds"] = walMeasurement.durationNanoseconds
    measurements["wal_open_bytes"] = walMeasurement.openBytes
    scenarios.append(
      pass(
        "WL-01",
        [
          "delete_queue_measured": "true",
          "wal_pool_measured": "true",
          "iterations_each": "100",
          "production_mode_selected": "false",
        ]))

    let keychainResult = try exerciseCredentialBoundary(
      service: arguments.keychainService,
      reference: credentialReference,
      secretData: secretData,
      metadataStore: migratedStore,
      profile: profile,
      workspace: workspace)
    scenarios.append(contentsOf: keychainResult.scenarios)

    try require(try migratedStore.history().isEmpty, "history deletion did not complete")
    try require(
      try migratedStore.profile(id: profile.id) == profile, "history deletion removed profile")
    try require(
      try migratedStore.workspace(id: workspace.id) == workspace,
      "credential or history deletion removed workspace")

    let exportURL = arguments.rootURL.appendingPathComponent("connection-export.json")
    let snapshotURL = arguments.rootURL.appendingPathComponent("schema-snapshot.json")
    let logURL = arguments.rootURL.appendingPathComponent("probe.log")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try writeOwnerOnly(try encoder.encode(profile), to: exportURL)
    try writeOwnerOnly(try encoder.encode(schemaSnapshot), to: snapshotURL)
    try writeOwnerOnly(
      Data(
        "operation_id=synthetic adapter=local-metadata category=probe retryable=false\n".utf8),
      to: logURL)

    try migratedStore.close()
    try concurrencyStore.close()
    try retentionStore.close()

    try secureAndVerifyAllArtifacts(in: arguments.rootURL)
    scenarios.append(
      pass(
        "FP-01",
        [
          "root_directory_owner_only": "true",
          "all_artifacts_owner_only_or_stricter": "true",
          "wal_shm_checked_when_present": "true",
        ]))

    var schema: [String: [String]] = schemaSnapshot.tables
    schema["__indices"] = schemaSnapshot.indices
    schema["__foreign_keys"] = schemaSnapshot.foreignKeys
      .sorted(by: { $0.key < $1.key })
      .flatMap { table, references in
        references.map { "\(table).\($0)" }
      }

    return ProbeReport(
      schemaVersion: 1,
      evidenceKind: "disposable-metadata-keychain-probe",
      scenarios: scenarios.sorted(by: { $0.id < $1.id }),
      measurements: measurements,
      schema: schema)
  }

  private static func prepareRoot(_ rootURL: URL) throws {
    guard rootURL.isFileURL else {
      throw ProbeError.invalidArguments("root must be a file URL")
    }
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true)
    let existing = try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
    try require(existing.isEmpty, "root must start empty")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: rootURL.path)
  }

  private static func readOwnedCanary(_ url: URL) throws -> Data {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard
      let permissions = attributes[.posixPermissions] as? NSNumber,
      permissions.intValue & 0o077 == 0
    else {
      throw ProbeError.invariantFailed("canary file permissions are too broad")
    }
    let data = try Data(contentsOf: url)
    guard !data.isEmpty, data.count <= 256 else {
      throw ProbeError.invalidArguments("canary length is outside the bounded range")
    }
    return data
  }

  private static func runCrashWriter(databaseURL: URL, marker: UUID) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    process.arguments = [
      "crash-write",
      "--database",
      databaseURL.path,
      "--marker",
      marker.uuidString.lowercased(),
    ]
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError
    try process.run()
    process.waitUntilExit()
    _ = standardOutput.fileHandleForReading.readDataToEndOfFile()
    _ = standardError.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationReason == .exit else {
      throw ProbeError.childFailed(process.terminationStatus)
    }
    guard process.terminationStatus == MetadataStore.crashWriterExitCode else {
      throw ProbeError.childFailed(process.terminationStatus)
    }
  }

  private static func runBoundedConcurrency(
    store: MetadataStore,
    profileID: UUID,
    workerCount: Int,
    writesPerWorker: Int
  ) throws -> ConcurrentResult {
    let state = ConcurrentProbeState()
    let group = DispatchGroup()
    let queue = DispatchQueue(
      label: "com.dataforge.m0-007.concurrent",
      qos: .userInitiated,
      attributes: .concurrent)
    for worker in 0..<workerCount {
      group.enter()
      queue.async {
        defer { group.leave() }
        for iteration in 0..<writesPerWorker {
          do {
            try store.appendHistory(
              QueryHistoryRecord(
                id: UUID(),
                profileID: profileID,
                executedAtMilliseconds: Int64(worker * writesPerWorker + iteration),
                operationKind: "concurrency"))
            _ = try store.profile(id: profileID)
            state.recordSuccess()
          } catch {
            state.recordFailure()
            return
          }
        }
      }
    }
    guard group.wait(timeout: .now() + 15) == .success else {
      throw ProbeError.invariantFailed("bounded concurrency timed out")
    }
    let result = state.result
    try require(result.failures == 0, "bounded concurrency returned errors")
    return result
  }

  private static func measureJournalMode(
    _ mode: MetadataJournalMode,
    rootURL: URL,
    profile: ConnectionProfile
  ) throws -> JournalMeasurement {
    let filename = mode == .deleteQueue ? "journal-delete.sqlite" : "journal-wal.sqlite"
    let databaseURL = rootURL.appendingPathComponent(filename)
    let store = try MetadataStore(
      databaseURL: databaseURL,
      mode: mode,
      historyLimit: 100)
    try store.saveProfile(profile)
    let start = DispatchTime.now().uptimeNanoseconds
    for index in 0..<100 {
      try store.appendHistory(
        QueryHistoryRecord(
          id: UUID(),
          profileID: profile.id,
          executedAtMilliseconds: Int64(index),
          operationKind: "journal-measurement"))
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    let observed = try store.currentJournalMode()
    try store.secureKnownFiles()
    let openBytes = try totalDatabaseBytes(databaseURL)
    try store.close()
    guard elapsed <= UInt64(Int64.max), openBytes <= UInt64(Int64.max) else {
      throw ProbeError.invariantFailed("measurement overflow")
    }
    return JournalMeasurement(
      durationNanoseconds: Int64(elapsed),
      openBytes: Int64(openBytes),
      observedMode: observed)
  }

  private static func totalDatabaseBytes(_ databaseURL: URL) throws -> UInt64 {
    var total: UInt64 = 0
    for url in [
      databaseURL,
      URL(fileURLWithPath: databaseURL.path + "-wal"),
      URL(fileURLWithPath: databaseURL.path + "-shm"),
    ] where FileManager.default.fileExists(atPath: url.path) {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      guard let size = values.fileSize, size >= 0 else {
        throw ProbeError.invariantFailed("file size missing")
      }
      total += UInt64(size)
    }
    return total
  }

  private static func exerciseCredentialBoundary(
    service: String,
    reference: CredentialReference,
    secretData: Data,
    metadataStore: MetadataStore,
    profile: ConnectionProfile,
    workspace: WorkspaceRecord
  ) throws -> CredentialBoundaryResult {
    let model = InMemoryCredentialStore()
    let secret = SecretValue(bytes: secretData)
    try model.add(reference: reference, secret: secret)
    try expectKeychainError(.duplicate) {
      try model.add(reference: reference, secret: secret)
    }
    let missingReference = CredentialReference(rawValue: UUID())
    try expectKeychainError(.missing) {
      _ = try model.read(reference: missingReference)
    }
    model.forcedStatus = errSecInteractionNotAllowed
    try expectKeychainError(.locked) {
      try model.add(reference: missingReference, secret: secret)
    }
    model.forcedStatus = errSecAuthFailed
    try expectKeychainError(.denied) {
      try model.update(reference: reference, secret: secret)
    }
    model.forcedStatus = nil
    _ = try model.read(reference: reference)

    let actual = DataProtectionKeychainStore(service: service)
    do {
      try actual.cleanupAllOwnedItems()
    } catch KeychainStoreError.missingEntitlement {
      // A CLI without a signed entitlement can fail even for scoped cleanup.
    }

    var actualStatus: ScenarioStatus = .unsupported
    var actualCategory = "not-run"
    var actualMissingVerified = false
    var actualAttributesVerified = false
    do {
      try actual.add(reference: reference, secret: secret)
      actualCategory = "success"
      _ = try actual.read(reference: reference)
      try expectKeychainError(.duplicate) {
        try actual.add(reference: reference, secret: secret)
      }
      let attributes = try actual.attributes(reference: reference)
      try require(
        attributes.serviceMatches
          && attributes.accountMatches
          && attributes.accessibleWhenUnlockedThisDeviceOnly
          && !attributes.synchronizable,
        "actual Keychain attributes mismatch")
      actualAttributesVerified = true
      try actual.update(
        reference: reference,
        secret: SecretValue(bytes: Data(secretData.reversed())))
      _ = try actual.read(reference: reference)

      try metadataStore.deleteAllHistory()
      _ = try actual.read(reference: reference)
      try actual.delete(reference: reference)
      actualMissingVerified = try actual.verifyMissing(reference: reference)
      try require(actualMissingVerified, "actual Keychain item remained after deletion")
      try expectKeychainError(.missing) {
        _ = try actual.read(reference: reference)
      }
      try actual.cleanupAllOwnedItems()
      actualStatus = .pass
    } catch let error as KeychainStoreError {
      switch error {
      case .missingEntitlement, .locked, .denied:
        actualCategory = keychainCategory(error)
        actualMissingVerified = try actual.verifyMissing(reference: reference)
        try require(actualMissingVerified, "failed Keychain add did not verify missing")
        do {
          try actual.cleanupAllOwnedItems()
        } catch let cleanupError as KeychainStoreError {
          guard cleanupError == .missingEntitlement else {
            throw cleanupError
          }
        }
      default:
        throw error
      }
    }

    if actualStatus != .pass {
      try metadataStore.deleteAllHistory()
    }
    _ = try model.read(reference: reference)
    try model.delete(reference: reference)
    try expectKeychainError(.missing) {
      _ = try model.read(reference: reference)
    }
    try require(
      try metadataStore.profile(id: profile.id) == profile, "credential deletion removed profile")
    try require(
      try metadataStore.workspace(id: workspace.id) == workspace,
      "credential deletion removed workspace")

    let actualPass = actualStatus == .pass
    return CredentialBoundaryResult(scenarios: [
      ScenarioEvidence(
        id: "KC-01",
        status: actualStatus,
        observation: [
          "actual_data_protection_crud": actualPass ? "complete" : "unsupported",
          "status_category": actualCategory,
          "final_missing_verified": String(actualMissingVerified),
        ]),
      ScenarioEvidence(
        id: "KC-02",
        status: actualPass ? .pass : .partial,
        observation: [
          "model_duplicate_and_missing": "typed",
          "actual_duplicate_and_missing": actualPass ? "typed" : "unsupported",
          "plaintext_fallback": "false",
        ]),
      ScenarioEvidence(
        id: "KC-03",
        status: actualPass ? .pass : .unsupported,
        observation: [
          "data_protection_attributes_verified": String(actualAttributesVerified),
          "when_unlocked_this_device_only": String(actualAttributesVerified),
          "synchronizable": actualAttributesVerified ? "false" : "unverified",
        ]),
      ScenarioEvidence(
        id: "KC-04",
        status: .partial,
        observation: [
          "injected_locked_typed": "true",
          "injected_denied_typed": "true",
          "actual_session_lock_or_acl_changed": "false",
          "plaintext_fallback": "false",
        ]),
      ScenarioEvidence(
        id: "DL-01",
        status: actualPass ? .pass : .partial,
        observation: [
          "history_delete_preserved_credential": actualPass ? "actual" : "model",
          "credential_delete_preserved_profile": "true",
          "credential_delete_preserved_workspace": "true",
        ]),
    ])
  }

  private static func expectKeychainError(
    _ expected: KeychainStoreError,
    operation: () throws -> Void
  ) throws {
    do {
      try operation()
      throw ProbeError.invariantFailed("expected Keychain error was not thrown")
    } catch let error as KeychainStoreError {
      try require(error == expected, "wrong Keychain error category")
    }
  }

  private static func keychainCategory(_ error: KeychainStoreError) -> String {
    switch error {
    case .duplicate:
      "duplicate"
    case .missing:
      "missing"
    case .locked:
      "locked"
    case .denied:
      "denied"
    case .missingEntitlement:
      "missing-entitlement"
    case .invalidResult:
      "invalid-result"
    case .unexpectedStatus:
      "unexpected-status"
    }
  }

  private static func writeOwnerOnly(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path)
  }

  private static func secureAndVerifyAllArtifacts(in rootURL: URL) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: rootURL.path)
    let rootAttributes = try FileManager.default.attributesOfItem(atPath: rootURL.path)
    guard
      let rootPermissions = rootAttributes[.posixPermissions] as? NSNumber,
      rootPermissions.intValue & 0o077 == 0
    else {
      throw ProbeError.invariantFailed("root permissions are too broad")
    }

    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else {
      throw ProbeError.invariantFailed("artifact enumeration failed")
    }
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else {
        continue
      }
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url.path)
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard
        let permissions = attributes[.posixPermissions] as? NSNumber,
        permissions.intValue & 0o077 == 0
      else {
        throw ProbeError.invariantFailed("artifact permissions are too broad")
      }
    }
  }

  private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws
  {
    guard try condition() else {
      throw ProbeError.invariantFailed(message)
    }
  }

  private static func pass(_ id: String, _ observation: [String: String]) -> ScenarioEvidence {
    ScenarioEvidence(id: id, status: .pass, observation: observation)
  }
}

private struct ConcurrentResult {
  let completedWrites: Int
  let failures: Int
}

private final class ConcurrentProbeState: @unchecked Sendable {
  private let lock = NSLock()
  private var completedWrites = 0
  private var failures = 0

  func recordSuccess() {
    lock.lock()
    completedWrites += 1
    lock.unlock()
  }

  func recordFailure() {
    lock.lock()
    failures += 1
    lock.unlock()
  }

  var result: ConcurrentResult {
    lock.lock()
    defer { lock.unlock() }
    return ConcurrentResult(
      completedWrites: completedWrites,
      failures: failures)
  }
}

private struct JournalMeasurement {
  let durationNanoseconds: Int64
  let openBytes: Int64
  let observedMode: String
}

private struct CredentialBoundaryResult {
  let scenarios: [ScenarioEvidence]
}
