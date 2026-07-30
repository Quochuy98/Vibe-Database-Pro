import Foundation

@main
private enum GridEvidenceMain {
  @MainActor
  static func main() async {
    do {
      let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
      let report = try await EvidenceRunner.run(arguments: arguments)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(report)
      guard let output = String(data: data, encoding: .utf8) else {
        throw EvidenceError.invariantFailed("JSON output was not UTF-8")
      }
      print(output)
    } catch {
      FileHandle.standardError.write(Data("grid evidence failed: \(error)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }

  private static func parseArguments(_ raw: [String]) throws -> EvidenceArguments {
    var fixture = "bf02"
    var rows = 1_000_000
    var samples = 10
    var scrollSeconds = 10.0
    var sourceRevision = "uncommitted"
    var index = 0

    while index < raw.count {
      switch raw[index] {
      case "--fixture":
        index += 1
        guard index < raw.count, ["bf02", "bf03"].contains(raw[index]) else {
          throw EvidenceError.invalidArguments("--fixture must be bf02 or bf03")
        }
        fixture = raw[index]
      case "--rows":
        index += 1
        guard index < raw.count, let parsed = Int(raw[index]), parsed > 0 else {
          throw EvidenceError.invalidArguments("--rows must be a positive integer")
        }
        rows = parsed
      case "--samples":
        index += 1
        guard index < raw.count, let parsed = Int(raw[index]), parsed >= 10 else {
          throw EvidenceError.invalidArguments("--samples must be at least 10")
        }
        samples = parsed
      case "--scroll-seconds":
        index += 1
        guard index < raw.count,
          let parsed = Double(raw[index]),
          parsed > 0,
          parsed <= 60
        else {
          throw EvidenceError.invalidArguments(
            "--scroll-seconds must be greater than 0 and at most 60"
          )
        }
        scrollSeconds = parsed
      case "--source-revision":
        index += 1
        guard index < raw.count, !raw[index].isEmpty else {
          throw EvidenceError.invalidArguments("--source-revision must not be empty")
        }
        sourceRevision = raw[index]
      default:
        throw EvidenceError.invalidArguments("unknown option \(raw[index])")
      }
      index += 1
    }

    return EvidenceArguments(
      fixture: fixture,
      rows: rows,
      samples: samples,
      scrollSeconds: scrollSeconds,
      sourceRevision: sourceRevision
    )
  }
}
