import Foundation

enum ScenarioStatus: String, Codable {
  case pass
  case partial
  case unsupported
  case fail
}

struct ScenarioEvidence: Codable {
  let id: String
  let status: ScenarioStatus
  let observation: [String: String]
}

struct ProbeReport: Codable {
  let schemaVersion: Int
  let evidenceKind: String
  let scenarios: [ScenarioEvidence]
  let measurements: [String: Int64]
  let schema: [String: [String]]
}

enum ProbeError: Error, CustomStringConvertible {
  case invalidArguments(String)
  case invariantFailed(String)
  case childFailed(Int32)

  var description: String {
    switch self {
    case .invalidArguments(let message):
      "invalid arguments: \(message)"
    case .invariantFailed(let message):
      "invariant failed: \(message)"
    case .childFailed(let status):
      "crash-writer child returned unexpected status \(status)"
    }
  }
}

struct RunArguments {
  let rootURL: URL
  let secretFileURL: URL
  let keychainService: String
}

enum ProbeCommand {
  case run(RunArguments)
  case crashWrite(databaseURL: URL, marker: String)
  case cleanupKeychain(service: String)
}

func parseCommand(_ raw: [String]) throws -> ProbeCommand {
  guard let command = raw.first else {
    throw ProbeError.invalidArguments("expected run, crash-write, or cleanup-keychain")
  }

  switch command {
  case "run":
    let values = try parseOptions(
      Array(raw.dropFirst()), allowed: ["--root", "--secret-file", "--service"])
    let root = try requiredOption("--root", from: values)
    let secretFile = try requiredOption("--secret-file", from: values)
    let service = try requiredOption("--service", from: values)
    guard root.hasPrefix("/"), secretFile.hasPrefix("/") else {
      throw ProbeError.invalidArguments("filesystem paths must be absolute")
    }
    guard service.hasPrefix("com.dataforge.m0-007.") else {
      throw ProbeError.invalidArguments("service must use the disposable DF-M0-007 prefix")
    }
    return .run(
      RunArguments(
        rootURL: URL(fileURLWithPath: root, isDirectory: true),
        secretFileURL: URL(fileURLWithPath: secretFile),
        keychainService: service))

  case "crash-write":
    let values = try parseOptions(Array(raw.dropFirst()), allowed: ["--database", "--marker"])
    let database = try requiredOption("--database", from: values)
    let marker = try requiredOption("--marker", from: values)
    guard database.hasPrefix("/"), UUID(uuidString: marker) != nil else {
      throw ProbeError.invalidArguments(
        "crash-write requires an absolute database path and UUID marker")
    }
    return .crashWrite(databaseURL: URL(fileURLWithPath: database), marker: marker.lowercased())

  case "cleanup-keychain":
    let values = try parseOptions(Array(raw.dropFirst()), allowed: ["--service"])
    let service = try requiredOption("--service", from: values)
    guard service.hasPrefix("com.dataforge.m0-007.") else {
      throw ProbeError.invalidArguments("service must use the disposable DF-M0-007 prefix")
    }
    return .cleanupKeychain(service: service)

  default:
    throw ProbeError.invalidArguments("unknown command")
  }
}

private func parseOptions(_ raw: [String], allowed: Set<String>) throws -> [String: String] {
  guard raw.count.isMultiple(of: 2) else {
    throw ProbeError.invalidArguments("every option requires exactly one value")
  }

  var values: [String: String] = [:]
  var index = 0
  while index < raw.count {
    let key = raw[index]
    let value = raw[index + 1]
    guard allowed.contains(key), values[key] == nil, !value.isEmpty else {
      throw ProbeError.invalidArguments("unknown, duplicate, or empty option")
    }
    values[key] = value
    index += 2
  }
  return values
}

private func requiredOption(_ key: String, from values: [String: String]) throws -> String {
  guard let value = values[key] else {
    throw ProbeError.invalidArguments("missing required option \(key)")
  }
  return value
}
