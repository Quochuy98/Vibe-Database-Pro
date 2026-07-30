import Foundation
import Darwin

@_silgen_name("dataforge_distribution_core_version")
private func dataforgeDistributionCoreVersion() -> UInt32

private enum ProbeError: Error, CustomStringConvertible {
    case unexpectedCoreVersion(UInt32)
    case helperFailed(Int32)
    case helperOutput(String)
    case helperOutputTooLarge
    case missingBundle

    var description: String {
        switch self {
        case let .unexpectedCoreVersion(version):
            return "unexpected core probe version \(version)"
        case let .helperFailed(status):
            return "helper exited with status \(status)"
        case let .helperOutput(output):
            return "unexpected bounded helper output: \(output)"
        case .helperOutputTooLarge:
            return "helper output exceeded the 256-byte probe limit"
        case .missingBundle:
            return "probe must run from its generated app bundle"
        }
    }
}

@main
private struct DataForgeDistributionProbe {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("probe-error: \(error)\n".utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func run() throws {
        let version = dataforgeDistributionCoreVersion()
        guard version == 0x0001_0000 else {
            throw ProbeError.unexpectedCoreVersion(version)
        }

        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw ProbeError.missingBundle
        }

        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("DataForgeDistributionHelper")
        let pipe = Pipe()
        let process = Process()
        process.executableURL = helperURL
        process.arguments = []
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        let data = try pipe.fileHandleForReading.read(upToCount: 257) ?? Data()
        if data.count > 256 {
            pipe.fileHandleForReading.closeFile()
            process.terminate()
            process.waitUntilExit()
            throw ProbeError.helperOutputTooLarge
        }
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == Int32(EXIT_SUCCESS) else {
            throw ProbeError.helperFailed(process.terminationStatus)
        }
        guard output == "dataforge-distribution-helper-ok" else {
            throw ProbeError.helperOutput(output)
        }

        print("dataforge-distribution-probe-ok core=65536 helper=ok")
    }
}
