import Foundation
import Security

public enum KeychainStoreError: Error, Equatable, Sendable {
  case duplicate
  case missing
  case locked
  case denied
  case missingEntitlement
  case invalidResult
  case unexpectedStatus(OSStatus)

  static func map(_ status: OSStatus) -> KeychainStoreError {
    switch status {
    case errSecDuplicateItem:
      .duplicate
    case errSecItemNotFound:
      .missing
    case errSecInteractionNotAllowed:
      .locked
    case errSecAuthFailed, errSecUserCanceled:
      .denied
    case errSecMissingEntitlement:
      .missingEntitlement
    default:
      .unexpectedStatus(status)
    }
  }
}

public struct KeychainItemAttributes: Equatable, Sendable {
  public let serviceMatches: Bool
  public let accountMatches: Bool
  public let accessibleWhenUnlockedThisDeviceOnly: Bool
  public let synchronizable: Bool
}

public protocol CredentialStoring: Sendable {
  func add(reference: CredentialReference, secret: SecretValue) throws
  func read(reference: CredentialReference) throws -> SecretValue
  func update(reference: CredentialReference, secret: SecretValue) throws
  func delete(reference: CredentialReference) throws
}

public struct DataProtectionKeychainStore: CredentialStoring, Sendable {
  private let service: String

  public init(service: String) {
    self.service = service
  }

  public func add(reference: CredentialReference, secret: SecretValue) throws {
    let status = SecItemAdd(
      addQuery(reference: reference, secret: secret) as CFDictionary,
      nil)
    guard status == errSecSuccess else {
      throw KeychainStoreError.map(status)
    }
  }

  public func read(reference: CredentialReference) throws -> SecretValue {
    var query = baseQuery(reference: reference)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else {
      throw KeychainStoreError.map(status)
    }
    guard let data = result as? Data else {
      throw KeychainStoreError.invalidResult
    }
    return SecretValue(bytes: data)
  }

  public func update(reference: CredentialReference, secret: SecretValue) throws {
    let status = SecItemUpdate(
      baseQuery(reference: reference) as CFDictionary,
      [kSecValueData as String: secret.keychainDataCopy()] as CFDictionary)
    guard status == errSecSuccess else {
      throw KeychainStoreError.map(status)
    }
  }

  public func delete(reference: CredentialReference) throws {
    let status = SecItemDelete(baseQuery(reference: reference) as CFDictionary)
    guard status == errSecSuccess else {
      throw KeychainStoreError.map(status)
    }
  }

  public func attributes(reference: CredentialReference) throws -> KeychainItemAttributes {
    var query = baseQuery(reference: reference)
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else {
      throw KeychainStoreError.map(status)
    }
    guard let attributes = result as? [String: Any] else {
      throw KeychainStoreError.invalidResult
    }
    let accessible = attributes[kSecAttrAccessible as String] as CFTypeRef?
    let synchronizable = attributes[kSecAttrSynchronizable as String] as? Bool ?? false
    return KeychainItemAttributes(
      serviceMatches: attributes[kSecAttrService as String] as? String == service,
      accountMatches: attributes[kSecAttrAccount as String] as? String
        == reference.persistedValue,
      accessibleWhenUnlockedThisDeviceOnly: accessible.map {
        CFEqual($0, kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
      } ?? false,
      synchronizable: synchronizable)
  }

  public func cleanupAllOwnedItems() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecUseDataProtectionKeychain as String: true,
      // Cleanup is intentionally service-wide and covers both values so a
      // malformed earlier run cannot strand an owned synchronizable item.
      // The unique disposable service prevents touching unrelated items.
      kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainStoreError.map(status)
    }
  }

  public func verifyMissing(reference: CredentialReference) throws -> Bool {
    var query = baseQuery(reference: reference)
    query[kSecReturnData as String] = false
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    switch status {
    case errSecItemNotFound:
      return true
    case errSecSuccess:
      return false
    default:
      throw KeychainStoreError.map(status)
    }
  }

  func baseQuery(reference: CredentialReference) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: reference.persistedValue,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrSynchronizable as String: false,
    ]
  }

  func addQuery(
    reference: CredentialReference,
    secret: SecretValue
  ) -> [String: Any] {
    var query = baseQuery(reference: reference)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    query[kSecValueData as String] = secret.keychainDataCopy()
    return query
  }
}

public final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var items: [CredentialReference: SecretValue] = [:]
  private var forcedStatusStorage: OSStatus?

  // All mutable state, including injected failures, is protected by `lock`.
  // This is the invariant that supports the unchecked Sendable conformance.
  public var forcedStatus: OSStatus? {
    get { withLock { forcedStatusStorage } }
    set { withLock { forcedStatusStorage = newValue } }
  }

  public init() {}

  public func add(reference: CredentialReference, secret: SecretValue) throws {
    try withLock {
      try throwForcedStatus()
      guard items[reference] == nil else {
        throw KeychainStoreError.duplicate
      }
      items[reference] = secret
    }
  }

  public func read(reference: CredentialReference) throws -> SecretValue {
    try withLock {
      try throwForcedStatus()
      guard let secret = items[reference] else {
        throw KeychainStoreError.missing
      }
      return secret
    }
  }

  public func update(reference: CredentialReference, secret: SecretValue) throws {
    try withLock {
      try throwForcedStatus()
      guard items[reference] != nil else {
        throw KeychainStoreError.missing
      }
      items[reference] = secret
    }
  }

  public func delete(reference: CredentialReference) throws {
    try withLock {
      try throwForcedStatus()
      guard items.removeValue(forKey: reference) != nil else {
        throw KeychainStoreError.missing
      }
    }
  }

  private func throwForcedStatus() throws {
    if let forcedStatus = forcedStatusStorage {
      throw KeychainStoreError.map(forcedStatus)
    }
  }

  private func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
