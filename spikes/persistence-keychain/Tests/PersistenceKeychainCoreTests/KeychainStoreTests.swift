import Foundation
import Security
import XCTest

@testable import PersistenceKeychainCore

final class ModelsTests: XCTestCase {
  func testCredentialReferenceUsesCanonicalPersistedValue() throws {
    let reference = CredentialReference(
      rawValue: try XCTUnwrap(
        UUID(uuidString: "A0B1C2D3-E4F5-4678-9123-456789ABCDEF")))

    XCTAssertEqual(reference.persistedValue, "a0b1c2d3-e4f5-4678-9123-456789abcdef")
  }

  func testConnectionProfileEncodingContainsMetadataAndNoSecretField() throws {
    let profile = ConnectionProfile(
      id: try XCTUnwrap(
        UUID(uuidString: "10000000-0000-4000-8000-000000000001")),
      displayName: "Synthetic local profile",
      host: "127.0.0.1",
      port: 5432,
      environment: .development,
      readOnly: true,
      credentialReference: CredentialReference(
        rawValue: try XCTUnwrap(
          UUID(uuidString: "20000000-0000-4000-8000-000000000002"))))

    let encoded = try JSONEncoder().encode(profile)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertEqual(
      Set(object.keys),
      [
        "id",
        "displayName",
        "host",
        "port",
        "environment",
        "readOnly",
        "credentialReference",
      ])

    let encodedText = try XCTUnwrap(String(data: encoded, encoding: .utf8)).lowercased()
    for prohibitedName in [
      "password",
      "passphrase",
      "privatekey",
      "apikey",
      "accesstoken",
      "refreshtoken",
      "clientsecret",
    ] {
      XCTAssertFalse(encodedText.contains(prohibitedName), prohibitedName)
    }
  }

  func testSecretValueIsRedactedAndDoesNotConformToPersistenceOrEqualityProtocols() {
    let canary = Data([0x6D, 0x30, 0x2D, 0x73, 0x79, 0x6E, 0x74, 0x68, 0x65, 0x74, 0x69, 0x63])
    let secret = SecretValue(bytes: canary)

    XCTAssertEqual(String(describing: secret), "<redacted secret>")
    XCTAssertEqual(String(reflecting: secret), "<redacted secret>")
    XCTAssertEqual(secret.debugDescription, "<redacted secret>")
    XCTAssertFalse(String(describing: secret).contains(String(decoding: canary, as: UTF8.self)))
    XCTAssertNil((secret as Any) as? any Encodable)
    XCTAssertNil((secret as Any) as? any Decodable)
    XCTAssertNil((secret as Any) as? any Equatable)
  }
}

final class KeychainStoreTests: XCTestCase {
  func testStatusMappingProducesTypedCredentialErrors() {
    let cases: [(OSStatus, KeychainStoreError)] = [
      (errSecDuplicateItem, .duplicate),
      (errSecItemNotFound, .missing),
      (errSecInteractionNotAllowed, .locked),
      (errSecAuthFailed, .denied),
      (errSecUserCanceled, .denied),
      (errSecMissingEntitlement, .missingEntitlement),
      (-9_999, .unexpectedStatus(-9_999)),
    ]

    for (status, expected) in cases {
      XCTAssertEqual(KeychainStoreError.map(status), expected)
    }
  }

  func testDataProtectionQueryIsFullyScopedWithoutAccessingKeychain() throws {
    let service = "com.dataforge.m0-007.synthetic.unit-test"
    let reference = CredentialReference(
      rawValue: try XCTUnwrap(
        UUID(uuidString: "30000000-0000-4000-8000-000000000003")))
    let store = DataProtectionKeychainStore(service: service)
    let query = store.baseQuery(reference: reference)

    let itemClass = try XCTUnwrap(query[kSecClass as String] as CFTypeRef?)
    XCTAssertTrue(CFEqual(itemClass, kSecClassGenericPassword))
    XCTAssertEqual(query[kSecAttrService as String] as? String, service)
    XCTAssertEqual(
      query[kSecAttrAccount as String] as? String,
      reference.persistedValue)
    XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
    XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
    XCTAssertNil(query[kSecValueData as String])

    let addQuery = store.addQuery(
      reference: reference,
      secret: SecretValue(bytes: Data([0x70])))
    let accessibility = try XCTUnwrap(
      addQuery[kSecAttrAccessible as String] as CFTypeRef?)
    XCTAssertTrue(CFEqual(accessibility, kSecAttrAccessibleWhenUnlockedThisDeviceOnly))
    XCTAssertEqual(addQuery[kSecAttrSynchronizable as String] as? Bool, false)
  }

  func testInMemoryStoreSupportsExplicitCRUD() throws {
    let store = InMemoryCredentialStore()
    let reference = CredentialReference(rawValue: UUID())
    let first = Data([0x01, 0x02, 0x03])
    let second = Data([0x04, 0x05, 0x06])

    try store.add(reference: reference, secret: SecretValue(bytes: first))
    XCTAssertTrue(try store.read(reference: reference).matches(first))

    try store.update(reference: reference, secret: SecretValue(bytes: second))
    XCTAssertTrue(try store.read(reference: reference).matches(second))

    try store.delete(reference: reference)
    assertThrows(.missing) {
      _ = try store.read(reference: reference)
    }
  }

  func testDuplicateAddFailsWithoutReplacingExistingSecret() throws {
    let store = InMemoryCredentialStore()
    let reference = CredentialReference(rawValue: UUID())
    let original = Data([0x10, 0x11])
    let replacement = Data([0x20, 0x21])

    try store.add(reference: reference, secret: SecretValue(bytes: original))
    assertThrows(.duplicate) {
      try store.add(reference: reference, secret: SecretValue(bytes: replacement))
    }

    let retained = try store.read(reference: reference)
    XCTAssertTrue(retained.matches(original))
    XCTAssertFalse(retained.matches(replacement))
  }

  func testMissingReadUpdateAndDeleteAreExplicit() {
    let store = InMemoryCredentialStore()
    let reference = CredentialReference(rawValue: UUID())

    assertThrows(.missing) {
      _ = try store.read(reference: reference)
    }
    assertThrows(.missing) {
      try store.update(reference: reference, secret: SecretValue(bytes: Data([0x30])))
    }
    assertThrows(.missing) {
      try store.delete(reference: reference)
    }
  }

  func testLockedAddFailsClosedWithoutFallbackBytes() {
    let store = InMemoryCredentialStore()
    let reference = CredentialReference(rawValue: UUID())

    store.forcedStatus = errSecInteractionNotAllowed
    assertThrows(.locked) {
      try store.add(reference: reference, secret: SecretValue(bytes: Data([0x40])))
    }

    store.forcedStatus = nil
    assertThrows(.missing) {
      _ = try store.read(reference: reference)
    }
  }

  func testMissingEntitlementAddFailsClosedWithoutFallbackBytes() {
    let store = InMemoryCredentialStore()
    let reference = CredentialReference(rawValue: UUID())

    store.forcedStatus = errSecMissingEntitlement
    assertThrows(.missingEntitlement) {
      try store.add(reference: reference, secret: SecretValue(bytes: Data([0x41])))
    }

    store.forcedStatus = nil
    assertThrows(.missing) {
      _ = try store.read(reference: reference)
    }
  }

  func testDeniedUpdateAndDeletePreserveExistingSecret() throws {
    let store = InMemoryCredentialStore()
    let reference = CredentialReference(rawValue: UUID())
    let original = Data([0x50, 0x51])
    let replacement = Data([0x60, 0x61])
    try store.add(reference: reference, secret: SecretValue(bytes: original))

    store.forcedStatus = errSecAuthFailed
    assertThrows(.denied) {
      try store.update(reference: reference, secret: SecretValue(bytes: replacement))
    }
    assertThrows(.denied) {
      try store.delete(reference: reference)
    }

    store.forcedStatus = nil
    let retained = try store.read(reference: reference)
    XCTAssertTrue(retained.matches(original))
    XCTAssertFalse(retained.matches(replacement))
  }

  func testUnexpectedInjectedStatusIsNotCollapsedIntoMissing() {
    let store = InMemoryCredentialStore()
    let reference = CredentialReference(rawValue: UUID())
    store.forcedStatus = -9_999

    assertThrows(.unexpectedStatus(-9_999)) {
      _ = try store.read(reference: reference)
    }
  }

  private func assertThrows(
    _ expected: KeychainStoreError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () throws -> Void
  ) {
    XCTAssertThrowsError(try operation(), file: file, line: line) { error in
      XCTAssertEqual(error as? KeychainStoreError, expected, file: file, line: line)
    }
  }
}
