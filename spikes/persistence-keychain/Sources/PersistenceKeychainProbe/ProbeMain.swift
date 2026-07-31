import Foundation
import PersistenceKeychainCore

@main
private enum PersistenceKeychainProbeMain {
  static func main() {
    do {
      let command = try parseCommand(Array(CommandLine.arguments.dropFirst()))
      switch command {
      case .run(let arguments):
        let report = try PersistenceProbe.run(arguments: arguments)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
      case .crashWrite(let databaseURL, let marker):
        guard let markerID = UUID(uuidString: marker) else {
          throw ProbeError.invalidArguments("crash marker must be a UUID")
        }
        let store = try MetadataStore(
          databaseURL: databaseURL,
          mode: .walPool,
          historyLimit: 1_000)
        store.terminateDuringUncommittedHistoryInsert(marker: markerID)
      case .cleanupKeychain(let service):
        let store = DataProtectionKeychainStore(service: service)
        try store.cleanupAllOwnedItems()
      }
    } catch let error as ProbeError {
      FileHandle.standardError.write(
        Data("DF-M0-007 probe failed: \(error.category)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    } catch let error as MetadataStoreError {
      FileHandle.standardError.write(
        Data("DF-M0-007 probe failed: metadata-\(error.category)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    } catch let error as KeychainStoreError {
      FileHandle.standardError.write(
        Data("DF-M0-007 probe failed: keychain-\(error.category)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    } catch {
      FileHandle.standardError.write(
        Data("DF-M0-007 probe failed: internal\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }
}

extension ProbeError {
  fileprivate var category: String {
    switch self {
    case .invalidArguments:
      "configuration"
    case .invariantFailed:
      "invariant"
    case .childFailed:
      "child"
    }
  }
}

extension MetadataStoreError {
  fileprivate var category: String {
    switch self {
    case .invalidConfiguration:
      "configuration"
    case .invalidStoredData:
      "stored-data"
    case .futureMigration:
      "future-migration"
    case .incompatibleSchema:
      "incompatible-schema"
    case .deliberateMigrationFailure:
      "deliberate-migration"
    case .integrityCheckFailed:
      "integrity"
    case .corruptDatabase:
      "corrupt"
    case .database:
      "database"
    case .file:
      "file"
    case .destinationExists:
      "destination-exists"
    }
  }
}

extension KeychainStoreError {
  fileprivate var category: String {
    switch self {
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
}
