import Darwin
import Foundation
import GRDB

public enum MetadataJournalMode: String, Codable, Sendable {
  case deleteQueue
  case walPool
}

public enum MetadataSchemaTarget: Sendable {
  case v1
  case latest
}

public enum MetadataStoreError: Error, Equatable, Sendable {
  case invalidConfiguration
  case invalidStoredData
  case futureMigration([String])
  case incompatibleSchema
  case deliberateMigrationFailure
  case integrityCheckFailed
  case corruptDatabase
  case database(Int32)
  case file(Int)
  case destinationExists
}

public struct QueryHistoryRecord: Codable, Equatable, Sendable {
  public let id: UUID
  public let profileID: UUID
  public let executedAtMilliseconds: Int64
  public let operationKind: String

  public init(
    id: UUID,
    profileID: UUID,
    executedAtMilliseconds: Int64,
    operationKind: String
  ) {
    self.id = id
    self.profileID = profileID
    self.executedAtMilliseconds = executedAtMilliseconds
    self.operationKind = operationKind
  }
}

public struct MetadataSchemaSnapshot: Codable, Equatable, Sendable {
  public let tables: [String: [String]]
  public let indices: [String]
  public let foreignKeys: [String: [String]]

  public init(
    tables: [String: [String]],
    indices: [String],
    foreignKeys: [String: [String]]
  ) {
    self.tables = tables
    self.indices = indices
    self.foreignKeys = foreignKeys
  }
}

// GRDB's queue and pool serialize writes and bound readers. `databaseURL`,
// `journalMode`, and `historyLimit` are immutable after initialization, so no
// additional mutable state crosses threads through this wrapper.
public final class MetadataStore: @unchecked Sendable {
  public static let migrationV1 = "v1_metadata"
  public static let migrationV2 = "v2_history_kind"
  public static let maximumReaderCount = 4
  public static let crashWriterExitCode: Int32 = 86

  private static let knownMigrations = [migrationV1, migrationV2]

  private let databaseURL: URL
  private let writer: any DatabaseWriter
  private let journalMode: MetadataJournalMode
  private let historyLimit: Int

  public init(
    databaseURL: URL,
    mode: MetadataJournalMode,
    historyLimit: Int,
    schemaTarget: MetadataSchemaTarget = .latest
  ) throws {
    guard databaseURL.isFileURL, historyLimit > 0, historyLimit <= 100_000 else {
      throw MetadataStoreError.invalidConfiguration
    }

    self.databaseURL = databaseURL.standardizedFileURL
    journalMode = mode
    self.historyLimit = historyLimit

    do {
      let directoryURL = databaseURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directoryURL.path)

      var configuration = Configuration()
      configuration.foreignKeysEnabled = true
      configuration.busyMode = .timeout(2)
      configuration.maximumReaderCount = Self.maximumReaderCount
      configuration.label = "DF-M0-007 disposable metadata"

      switch mode {
      case .deleteQueue:
        writer = try DatabaseQueue(
          path: databaseURL.path,
          configuration: configuration)
      case .walPool:
        configuration.journalMode = .wal
        writer = try DatabasePool(
          path: databaseURL.path,
          configuration: configuration)
      }

      try Self.refuseUnknownOrIncompatibleMigrations(
        in: writer,
        target: schemaTarget)
      let migrator = Self.makeMigrator()
      switch schemaTarget {
      case .v1:
        try migrator.migrate(writer, upTo: Self.migrationV1)
      case .latest:
        try migrator.migrate(writer)
      }

      if mode == .deleteQueue {
        try writer.writeWithoutTransaction { database in
          let observed = try String.fetchOne(
            database,
            sql: "PRAGMA journal_mode = DELETE")
          guard observed?.lowercased() == "delete" else {
            throw MetadataStoreError.invalidConfiguration
          }
        }
      }
      try secureKnownFiles()
    } catch {
      throw Self.map(error)
    }
  }

  public func saveProfile(_ profile: ConnectionProfile) throws {
    guard
      !profile.displayName.isEmpty,
      !profile.host.isEmpty,
      (1...65_535).contains(profile.port)
    else {
      throw MetadataStoreError.invalidConfiguration
    }

    try perform {
      try writer.write { database in
        try database.execute(
          sql: """
            INSERT INTO connection_profiles (
                id,
                display_name,
                host,
                port,
                environment,
                read_only,
                credential_reference
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                host = excluded.host,
                port = excluded.port,
                environment = excluded.environment,
                read_only = excluded.read_only,
                credential_reference = excluded.credential_reference
            """,
          arguments: [
            profile.id.uuidString.lowercased(),
            profile.displayName,
            profile.host,
            profile.port,
            profile.environment.rawValue,
            profile.readOnly,
            profile.credentialReference.persistedValue,
          ])
      }
      try secureKnownFiles()
    }
  }

  public func profile(id: UUID) throws -> ConnectionProfile? {
    try perform {
      try writer.read { database in
        guard
          let row = try Row.fetchOne(
            database,
            sql: """
              SELECT
                  id,
                  display_name,
                  host,
                  port,
                  environment,
                  read_only,
                  credential_reference
              FROM connection_profiles
              WHERE id = ?
              """,
            arguments: [id.uuidString.lowercased()])
        else {
          return nil
        }
        return try Self.decodeProfile(row)
      }
    }
  }

  public func allProfiles() throws -> [ConnectionProfile] {
    try perform {
      try writer.read { database in
        try Row.fetchAll(
          database,
          sql: """
            SELECT
                id,
                display_name,
                host,
                port,
                environment,
                read_only,
                credential_reference
            FROM connection_profiles
            ORDER BY id
            """
        )
        .map(Self.decodeProfile)
      }
    }
  }

  public func saveWorkspace(_ workspace: WorkspaceRecord) throws {
    guard !workspace.title.isEmpty else {
      throw MetadataStoreError.invalidConfiguration
    }
    try perform {
      try writer.write { database in
        try database.execute(
          sql: """
            INSERT INTO workspaces (
                id,
                profile_id,
                title,
                updated_at_milliseconds
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                profile_id = excluded.profile_id,
                title = excluded.title,
                updated_at_milliseconds = excluded.updated_at_milliseconds
            """,
          arguments: [
            workspace.id.uuidString.lowercased(),
            workspace.profileID.uuidString.lowercased(),
            workspace.title,
            workspace.updatedAtMilliseconds,
          ])
      }
      try secureKnownFiles()
    }
  }

  public func workspace(id: UUID) throws -> WorkspaceRecord? {
    try perform {
      try writer.read { database in
        guard
          let row = try Row.fetchOne(
            database,
            sql: """
              SELECT id, profile_id, title, updated_at_milliseconds
              FROM workspaces
              WHERE id = ?
              """,
            arguments: [id.uuidString.lowercased()])
        else {
          return nil
        }
        return try Self.decodeWorkspace(row)
      }
    }
  }

  public func appendHistory(_ record: QueryHistoryRecord) throws {
    guard !record.operationKind.isEmpty, record.operationKind.count <= 64 else {
      throw MetadataStoreError.invalidConfiguration
    }
    try perform {
      try writer.write { database in
        try database.execute(
          sql: """
            INSERT INTO query_history (
                id,
                profile_id,
                executed_at_milliseconds,
                operation_kind
            ) VALUES (?, ?, ?, ?)
            """,
          arguments: [
            record.id.uuidString.lowercased(),
            record.profileID.uuidString.lowercased(),
            record.executedAtMilliseconds,
            record.operationKind,
          ])
        try database.execute(
          sql: """
            DELETE FROM query_history
            WHERE id IN (
                SELECT id
                FROM query_history
                ORDER BY executed_at_milliseconds DESC, id DESC
                LIMIT -1 OFFSET ?
            )
            """,
          arguments: [historyLimit])
      }
      try secureKnownFiles()
    }
  }

  public func history() throws -> [QueryHistoryRecord] {
    try perform {
      try writer.read { database in
        try Row.fetchAll(
          database,
          sql: """
            SELECT id, profile_id, executed_at_milliseconds, operation_kind
            FROM query_history
            ORDER BY executed_at_milliseconds DESC, id DESC
            """
        )
        .map(Self.decodeHistory)
      }
    }
  }

  public func deleteAllHistory() throws {
    try perform {
      try writer.write { database in
        try database.execute(sql: "DELETE FROM query_history")
      }
      try secureKnownFiles()
    }
  }

  public func insertV1HistoryForProbe(
    id: UUID,
    profileID: UUID,
    executedAtMilliseconds: Int64
  ) throws {
    try perform {
      try writer.write { database in
        let columns = try database.columns(in: "query_history").map(\.name)
        guard !columns.contains("operation_kind") else {
          throw MetadataStoreError.incompatibleSchema
        }
        try database.execute(
          sql: """
            INSERT INTO query_history (
                id,
                profile_id,
                executed_at_milliseconds
            ) VALUES (?, ?, ?)
            """,
          arguments: [
            id.uuidString.lowercased(),
            profileID.uuidString.lowercased(),
            executedAtMilliseconds,
          ])
      }
      try secureKnownFiles()
    }
  }

  public func completedMigrationIdentifiers() throws -> [String] {
    try perform {
      let migrator = Self.makeMigrator()
      return try writer.read(migrator.completedMigrations)
    }
  }

  public func seedFutureMigrationMarkerForProbe(_ identifier: String) throws {
    guard identifier.hasPrefix("future_"), identifier.count <= 64 else {
      throw MetadataStoreError.invalidConfiguration
    }
    try perform {
      try writer.write { database in
        try database.execute(
          sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
          arguments: [identifier])
      }
      try secureKnownFiles()
    }
  }

  public func runDeliberatelyFailingMigration() throws {
    var migrator = Self.makeMigrator()
    migrator.registerMigration("probe_deliberate_failure") { database in
      try database.create(table: "partial_migration_probe") { table in
        table.column("marker", .text).notNull()
      }
      try database.execute(
        sql: "INSERT INTO partial_migration_probe (marker) VALUES (?)",
        arguments: ["synthetic"])
      throw MetadataStoreError.deliberateMigrationFailure
    }
    do {
      try migrator.migrate(writer)
      throw MetadataStoreError.integrityCheckFailed
    } catch {
      throw Self.map(error)
    }
  }

  public func failedMigrationArtifactsExist() throws -> Bool {
    try perform {
      try writer.read { database in
        let tableExists = try database.tableExists("partial_migration_probe")
        let markerExists =
          try Bool.fetchOne(
            database,
            sql: """
              SELECT EXISTS(
                  SELECT 1
                  FROM grdb_migrations
                  WHERE identifier = 'probe_deliberate_failure'
              )
              """) ?? false
        return tableExists || markerExists
      }
    }
  }

  public func containsHistory(id: UUID) throws -> Bool {
    try perform {
      try writer.read { database in
        try Bool.fetchOne(
          database,
          sql: "SELECT EXISTS(SELECT 1 FROM query_history WHERE id = ?)",
          arguments: [id.uuidString.lowercased()]) ?? false
      }
    }
  }

  public func terminateDuringUncommittedHistoryInsert(marker: UUID) -> Never {
    do {
      try writer.writeWithoutTransaction { database in
        try database.beginTransaction()
        try database.execute(
          sql: """
            INSERT INTO query_history (
                id,
                profile_id,
                executed_at_milliseconds,
                operation_kind
            )
            SELECT ?, id, ?, ?
            FROM connection_profiles
            ORDER BY id
            LIMIT 1
            """,
          arguments: [
            marker.uuidString.lowercased(),
            Int64.max - 1,
            "uncommitted-crash-probe",
          ])
        guard database.changesCount == 1 else {
          Darwin._exit(85)
        }
        Darwin._exit(Self.crashWriterExitCode)
      }
    } catch {
      Darwin._exit(84)
    }
    Darwin._exit(83)
  }

  public func verifyIntegrity() throws {
    try perform {
      try writer.read { database in
        let results = try String.fetchAll(
          database,
          sql: "PRAGMA integrity_check")
        guard results == ["ok"] else {
          throw MetadataStoreError.integrityCheckFailed
        }
        try database.checkForeignKeys()
      }
    }
  }

  public func backup(to destinationURL: URL) throws {
    guard destinationURL.isFileURL else {
      throw MetadataStoreError.invalidConfiguration
    }
    guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
      throw MetadataStoreError.destinationExists
    }

    try perform {
      if journalMode == .walPool {
        _ = try writer.writeWithoutTransaction { database in
          try database.checkpoint(.truncate)
        }
      }
      var configuration = Configuration()
      configuration.foreignKeysEnabled = true
      configuration.busyMode = .timeout(2)
      let destination = try DatabaseQueue(
        path: destinationURL.path,
        configuration: configuration)
      try writer.backup(to: destination)
      try destination.read { database in
        let results = try String.fetchAll(
          database,
          sql: "PRAGMA integrity_check")
        guard results == ["ok"] else {
          throw MetadataStoreError.integrityCheckFailed
        }
        try database.checkForeignKeys()
      }
      try destination.close()
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: destinationURL.path)
    }
  }

  public func schemaSnapshot() throws -> MetadataSchemaSnapshot {
    try perform {
      try writer.read { database in
        let tableNames = try String.fetchAll(
          database,
          sql: """
            SELECT name
            FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """)
        var tables: [String: [String]] = [:]
        var foreignKeys: [String: [String]] = [:]
        for tableName in tableNames {
          tables[tableName] = try database.columns(in: tableName).map(\.name)
          foreignKeys[tableName] = try database.foreignKeys(on: tableName)
            .flatMap { key in
              key.mapping.map { mapping in
                "\(mapping.origin)->\(key.destinationTable).\(mapping.destination)"
              }
            }
            .sorted()
        }
        let indices = try String.fetchAll(
          database,
          sql: """
            SELECT name
            FROM sqlite_master
            WHERE type = 'index' AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """)
        return MetadataSchemaSnapshot(
          tables: tables,
          indices: indices,
          foreignKeys: foreignKeys)
      }
    }
  }

  public func currentJournalMode() throws -> String {
    try perform {
      try writer.read { database in
        guard
          let mode = try String.fetchOne(
            database,
            sql: "PRAGMA journal_mode")
        else {
          throw MetadataStoreError.invalidStoredData
        }
        return mode.lowercased()
      }
    }
  }

  public func secureKnownFiles() throws {
    do {
      for url in knownDatabaseFiles() where FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o600],
          ofItemAtPath: url.path)
      }
    } catch {
      throw Self.map(error)
    }
  }

  public func filePermissionSnapshot() throws -> [String: Int] {
    try perform {
      var result: [String: Int] = [:]
      let labels = ["main", "wal", "shm"]
      for (label, url) in zip(labels, knownDatabaseFiles())
      where FileManager.default.fileExists(atPath: url.path) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
          throw MetadataStoreError.invalidStoredData
        }
        result[label] = permissions.intValue & 0o777
      }
      return result
    }
  }

  public func close() throws {
    try perform {
      try secureKnownFiles()
      try writer.close()
    }
  }

  private func knownDatabaseFiles() -> [URL] {
    [
      databaseURL,
      URL(fileURLWithPath: databaseURL.path + "-wal"),
      URL(fileURLWithPath: databaseURL.path + "-shm"),
    ]
  }

  private func perform<T>(_ body: () throws -> T) throws -> T {
    do {
      return try body()
    } catch {
      throw Self.map(error)
    }
  }

  private static func refuseUnknownOrIncompatibleMigrations(
    in writer: any DatabaseWriter,
    target: MetadataSchemaTarget
  ) throws {
    let migrator = makeMigrator()
    let applied = try writer.read(migrator.appliedIdentifiers)
    let unknown = applied.subtracting(knownMigrations).sorted()
    guard unknown.isEmpty else {
      throw MetadataStoreError.futureMigration(unknown)
    }
    if target == .v1, applied.contains(migrationV2) {
      throw MetadataStoreError.incompatibleSchema
    }
  }

  private static func makeMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.eraseDatabaseOnSchemaChange = false
    migrator.registerMigration(migrationV1) { database in
      try database.create(table: "connection_profiles") { table in
        table.column("id", .text).primaryKey()
        table.column("display_name", .text).notNull()
        table.column("host", .text).notNull()
        table.column("port", .integer).notNull()
        table.column("environment", .text).notNull()
        table.column("read_only", .boolean).notNull()
        table.column("credential_reference", .text).notNull()
        table.check(sql: "port BETWEEN 1 AND 65535")
        table.check(sql: "environment IN ('development', 'staging', 'production')")
      }
      try database.create(
        index: "connection_profiles_credential_reference",
        on: "connection_profiles",
        columns: ["credential_reference"])

      try database.create(table: "workspaces") { table in
        table.column("id", .text).primaryKey()
        table.column("profile_id", .text)
          .notNull()
          .references("connection_profiles", onDelete: .cascade)
        table.column("title", .text).notNull()
        table.column("updated_at_milliseconds", .integer).notNull()
      }
      try database.create(
        index: "workspaces_profile_id",
        on: "workspaces",
        columns: ["profile_id"])

      try database.create(table: "query_history") { table in
        table.column("id", .text).primaryKey()
        table.column("profile_id", .text)
          .notNull()
          .references("connection_profiles", onDelete: .cascade)
        table.column("executed_at_milliseconds", .integer).notNull()
      }
      try database.create(
        index: "query_history_profile_id",
        on: "query_history",
        columns: ["profile_id"])
    }
    migrator.registerMigration(migrationV2) { database in
      try database.alter(table: "query_history") { table in
        table.add(
          column: "operation_kind",
          .text
        )
        .notNull()
        .defaults(to: "query")
      }
      try database.create(
        index: "query_history_retention",
        on: "query_history",
        columns: ["executed_at_milliseconds", "id"])
    }
    return migrator
  }

  private static func decodeProfile(_ row: Row) throws -> ConnectionProfile {
    let idString: String = row["id"]
    let displayName: String = row["display_name"]
    let host: String = row["host"]
    let port: Int = row["port"]
    let environmentString: String = row["environment"]
    let readOnly: Bool = row["read_only"]
    let credentialString: String = row["credential_reference"]
    guard
      let id = UUID(uuidString: idString),
      let environment = ConnectionEnvironment(rawValue: environmentString),
      let credentialID = UUID(uuidString: credentialString)
    else {
      throw MetadataStoreError.invalidStoredData
    }
    return ConnectionProfile(
      id: id,
      displayName: displayName,
      host: host,
      port: port,
      environment: environment,
      readOnly: readOnly,
      credentialReference: CredentialReference(rawValue: credentialID))
  }

  private static func decodeWorkspace(_ row: Row) throws -> WorkspaceRecord {
    let idString: String = row["id"]
    let profileString: String = row["profile_id"]
    let title: String = row["title"]
    let updatedAt: Int64 = row["updated_at_milliseconds"]
    guard
      let id = UUID(uuidString: idString),
      let profileID = UUID(uuidString: profileString)
    else {
      throw MetadataStoreError.invalidStoredData
    }
    return WorkspaceRecord(
      id: id,
      profileID: profileID,
      title: title,
      updatedAtMilliseconds: updatedAt)
  }

  private static func decodeHistory(_ row: Row) throws -> QueryHistoryRecord {
    let idString: String = row["id"]
    let profileString: String = row["profile_id"]
    let executedAt: Int64 = row["executed_at_milliseconds"]
    let operationKind: String = row["operation_kind"]
    guard
      let id = UUID(uuidString: idString),
      let profileID = UUID(uuidString: profileString)
    else {
      throw MetadataStoreError.invalidStoredData
    }
    return QueryHistoryRecord(
      id: id,
      profileID: profileID,
      executedAtMilliseconds: executedAt,
      operationKind: operationKind)
  }

  private static func map(_ error: Error) -> MetadataStoreError {
    if let error = error as? MetadataStoreError {
      return error
    }
    if let error = error as? DatabaseError {
      switch error.resultCode.rawValue {
      case 11, 26:
        return .corruptDatabase
      default:
        return .database(error.resultCode.rawValue)
      }
    }
    let cocoaError = error as NSError
    return .file(cocoaError.code)
  }
}
