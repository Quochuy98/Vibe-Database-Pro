import Foundation

public struct CredentialReference: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public var persistedValue: String {
    rawValue.uuidString.lowercased()
  }
}

public enum ConnectionEnvironment: String, Codable, Sendable {
  case development
  case staging
  case production
}

public struct ConnectionProfile: Codable, Equatable, Sendable {
  public let id: UUID
  public let displayName: String
  public let host: String
  public let port: Int
  public let environment: ConnectionEnvironment
  public let readOnly: Bool
  public let credentialReference: CredentialReference

  public init(
    id: UUID,
    displayName: String,
    host: String,
    port: Int,
    environment: ConnectionEnvironment,
    readOnly: Bool,
    credentialReference: CredentialReference
  ) {
    self.id = id
    self.displayName = displayName
    self.host = host
    self.port = port
    self.environment = environment
    self.readOnly = readOnly
    self.credentialReference = credentialReference
  }
}

public struct WorkspaceRecord: Codable, Equatable, Sendable {
  public let id: UUID
  public let profileID: UUID
  public let title: String
  public let updatedAtMilliseconds: Int64

  public init(
    id: UUID,
    profileID: UUID,
    title: String,
    updatedAtMilliseconds: Int64
  ) {
    self.id = id
    self.profileID = profileID
    self.title = title
    self.updatedAtMilliseconds = updatedAtMilliseconds
  }
}

public struct SecretValue: Sendable, CustomDebugStringConvertible {
  private let storage: Data

  public init(bytes: Data) {
    storage = bytes
  }

  public var debugDescription: String {
    "<redacted secret>"
  }

  func keychainDataCopy() -> Data {
    storage
  }

  func matches(_ candidate: Data) -> Bool {
    guard storage.count == candidate.count else {
      return false
    }
    return zip(storage, candidate).reduce(into: UInt8(0)) { difference, pair in
      difference |= pair.0 ^ pair.1
    } == 0
  }
}
