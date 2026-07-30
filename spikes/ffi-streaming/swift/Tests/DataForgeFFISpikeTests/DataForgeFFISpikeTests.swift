import CDataForgeFFI
import Foundation
import XCTest
@testable import DataForgeFFISpike

final class DataForgeFFISpikeTests: XCTestCase {
    private let fnvPrime: UInt64 = 0x100000001b3
    private let fnvOffset: UInt64 = 0xcbf29ce484222325

    override func tearDownWithError() throws {
        let stats = try DataForgeFFISpike.registryStats()
        XCTAssertEqual(stats.liveStreams, 0)
        XCTAssertEqual(stats.inFlightBytes, 0)
        XCTAssertEqual(stats.createdStreams, stats.releasedStreams)
        try super.tearDownWithError()
    }

    func testABIHandshakeAndLayout() throws {
        let negotiated = try DataForgeFFISpike.negotiate()
        XCTAssertEqual(negotiated.abiVersion, 1)
        XCTAssertEqual(negotiated.rowEncodingVersion, 1)
        XCTAssertEqual(negotiated.maxStreams, 128)
        XCTAssertEqual(negotiated.maxChunkRows, 1_000)
        XCTAssertEqual(negotiated.maxChunkBytes, 4 * 1024 * 1024)
        XCTAssertEqual(MemoryLayout<df_spike_abi_request_v1>.size, 32)
        XCTAssertEqual(MemoryLayout<df_spike_abi_info_v1>.size, 40)
        XCTAssertEqual(MemoryLayout<df_spike_stream_options_v1>.size, 40)
        XCTAssertEqual(MemoryLayout<df_spike_chunk_meta_v1>.size, 64)
        XCTAssertEqual(MemoryLayout<df_spike_stream_status_v1>.size, 48)
        XCTAssertEqual(MemoryLayout<df_spike_cancel_outcome_v1>.size, 24)
        XCTAssertEqual(MemoryLayout<df_spike_registry_stats_v1>.size, 48)
        XCTAssertEqual(MemoryLayout<df_spike_abi_request_v1>.alignment, 8)
        XCTAssertEqual(MemoryLayout<df_spike_abi_info_v1>.alignment, 8)
        XCTAssertEqual(MemoryLayout<df_spike_stream_options_v1>.alignment, 8)
        XCTAssertEqual(MemoryLayout<df_spike_chunk_meta_v1>.alignment, 8)
        XCTAssertEqual(MemoryLayout<df_spike_stream_status_v1>.alignment, 8)
        XCTAssertEqual(MemoryLayout<df_spike_cancel_outcome_v1>.alignment, 4)
        XCTAssertEqual(MemoryLayout<df_spike_registry_stats_v1>.alignment, 8)

        XCTAssertEqual(MemoryLayout<df_spike_abi_request_v1>.offset(of: \.required_features), 8)
        XCTAssertEqual(MemoryLayout<df_spike_abi_info_v1>.offset(of: \.max_chunk_bytes), 24)
        XCTAssertEqual(MemoryLayout<df_spike_stream_options_v1>.offset(of: \.seed), 16)
        XCTAssertEqual(MemoryLayout<df_spike_chunk_meta_v1>.offset(of: \.checksum), 40)
        XCTAssertEqual(MemoryLayout<df_spike_chunk_meta_v1>.offset(of: \.required_capacity), 48)
        XCTAssertEqual(MemoryLayout<df_spike_stream_status_v1>.offset(of: \.outstanding_sequence), 32)
        XCTAssertEqual(MemoryLayout<df_spike_cancel_outcome_v1>.offset(of: \.state), 12)
        XCTAssertEqual(MemoryLayout<df_spike_registry_stats_v1>.offset(of: \.released_streams), 32)
    }

    func testABIRejectsMismatchAndUnknownRequiredFeature() {
        var mismatch = df_spike_abi_request_v1(
            struct_size: UInt32(MemoryLayout<df_spike_abi_request_v1>.size),
            abi_version: 2,
            required_features: 0,
            optional_features: 0,
            reserved0: 0,
            reserved1: 0
        )
        var response = df_spike_abi_info_v1()
        XCTAssertEqual(df_spike_abi_negotiate_v1(&mismatch, &response), 4)

        mismatch.abi_version = 1
        mismatch.required_features = UInt64(1) << 63
        XCTAssertEqual(df_spike_abi_negotiate_v1(&mismatch, &response), 5)

        mismatch.required_features = 0
        mismatch.struct_size = 1
        XCTAssertEqual(df_spike_abi_negotiate_v1(&mismatch, &response), 4)
    }

    func testPullAckBackpressureAndChecksum() throws {
        let stream = try DataForgeStream(configuration: .init(totalRows: 10, seed: 7, chunkRows: 2, chunkBytes: 80))
        defer { closeForTest(stream) }

        let first = try XCTUnwrap(try stream.next())
        XCTAssertEqual(first.metadata.rowCount, 2)
        XCTAssertEqual(first.metadata.byteCount, UInt32(first.bytes.count))
        XCTAssertEqual(fnv1a(first.bytes), first.metadata.checksum)
        XCTAssertThrowsError(try stream.next()) { error in
            XCTAssertEqual(error as? SpikeError, .status(.needsAck))
        }
        let outstanding = try stream.status()
        XCTAssertEqual(outstanding.state, 2)
        XCTAssertEqual(outstanding.outstandingSequence, first.metadata.sequence)
        try stream.acknowledge(sequence: first.metadata.sequence)
        XCTAssertNil(try stream.status().outstandingSequence)
    }

    func testOneMillionTypedRowsStayOrderedAndBoundedByChunkCaps() throws {
        let stream = try DataForgeStream(configuration: .init(
            totalRows: 1_000_000,
            seed: 7,
            chunkRows: 1_000,
            chunkBytes: 4 * 1024 * 1024
        ))
        defer { closeForTest(stream) }

        var expectedRow: UInt64 = 0
        var digest = fnvOffset
        var chunks = 0
        while let chunk = try stream.next() {
            chunks += 1
            XCTAssertLessThanOrEqual(chunk.metadata.rowCount, 1_000)
            XCTAssertLessThanOrEqual(chunk.metadata.byteCount, 4 * 1024 * 1024)
            XCTAssertEqual(chunk.metadata.byteCount, UInt32(chunk.bytes.count))
            XCTAssertEqual(chunk.metadata.firstRow, expectedRow)
            XCTAssertEqual(fnv1a(chunk.bytes), chunk.metadata.checksum)
            let parsed = try parseRows(
                chunk.bytes,
                expectedFirstRow: expectedRow,
                seed: 7,
                initialDigest: digest
            )
            expectedRow += UInt64(parsed.rowCount)
            digest = parsed.digest
            try stream.acknowledge(sequence: chunk.metadata.sequence)
        }
        XCTAssertEqual(expectedRow, 1_000_000)
        XCTAssertEqual(chunks, 1_000)
        XCTAssertEqual(digest, expectedDigest(rowCount: 1_000_000, seed: 7))
        print("DF_M0_001 rows=\(expectedRow) chunks=\(chunks) digest=\(digest)")
        XCTAssertEqual(try stream.status().state, 3)
    }

    func testCancellationAtLifecycleBoundaries() throws {
        let beforeStart = try DataForgeStream(configuration: .init(totalRows: 10))
        XCTAssertEqual(try beforeStart.cancel(), .accepted)
        XCTAssertThrowsError(try beforeStart.next()) { error in
            XCTAssertEqual(error as? SpikeError, .status(.cancelled))
        }
        try beforeStart.close()

        let outstanding = try DataForgeStream(configuration: .init(totalRows: 10, chunkRows: 1, chunkBytes: 40))
        let chunk = try XCTUnwrap(try outstanding.next())
        XCTAssertEqual(try outstanding.cancel(), .pendingAcknowledgement)
        XCTAssertEqual(try outstanding.cancel(), .alreadyRequested)
        XCTAssertThrowsError(try outstanding.next()) { error in
            XCTAssertEqual(error as? SpikeError, .status(.cancelled))
        }
        try outstanding.acknowledge(sequence: chunk.metadata.sequence)
        XCTAssertEqual(try outstanding.status().state, 4)
        try outstanding.close()

        let completed = try DataForgeStream(configuration: .init(totalRows: 1, chunkRows: 1, chunkBytes: 40))
        let completedChunk = try XCTUnwrap(try completed.next())
        try completed.acknowledge(sequence: completedChunk.metadata.sequence)
        XCTAssertNil(try completed.next())
        XCTAssertEqual(try completed.cancel(), .tooLate)
        try completed.close()
    }

    func testFaultInjectionAndPanicContainment() throws {
        XCTAssertThrowsError(try DataForgeFFISpike.panicProbe()) { error in
            XCTAssertEqual(error as? SpikeError, .status(.panic))
        }

        let stream = try DataForgeStream(configuration: .init(totalRows: 2, chunkRows: 1, chunkBytes: 40))
        defer { closeForTest(stream) }
        try stream.armAllocationFailureForNextChunk()
        XCTAssertThrowsError(try stream.next()) { error in
            XCTAssertEqual(error as? SpikeError, .status(.allocationFailed))
        }
        let chunk = try XCTUnwrap(try stream.next())
        try stream.acknowledge(sequence: chunk.metadata.sequence)
        try stream.armPanicForNextChunk()
        XCTAssertThrowsError(try stream.next()) { error in
            XCTAssertEqual(error as? SpikeError, .status(.panic))
        }
        XCTAssertEqual(try stream.status().state, 5)
        XCTAssertEqual(try stream.cancel(), .tooLate)
    }

    func testSecretLikeCanaryIsNotReadOrMutatedByFaultPaths() throws {
        let fallbackCanary = ["DF_SECRET_CANARY", "M0_001", "DO_NOT_LOG", "7F3A9C"].joined(separator: "_")
        let canary = ProcessInfo.processInfo.environment["DATAFORGE_SECRET_CANARY"] ?? fallbackCanary
        var destination = Array(canary.utf8)
        destination.append(contentsOf: repeatElement(0xA5, count: max(0, 128 - destination.count)))
        let original = destination
        var options = df_spike_stream_options_v1(
            struct_size: UInt32(MemoryLayout<df_spike_stream_options_v1>.size),
            abi_version: DataForgeFFISpike.abiVersion,
            total_rows: 2,
            seed: 7,
            requested_chunk_rows: 1,
            requested_chunk_bytes: 40,
            reserved0: 0,
            reserved1: 0
        )
        var handle: UInt64 = 0
        XCTAssertEqual(df_spike_stream_create_v1(&options, &handle), SpikeStatus.ok.rawValue)
        XCTAssertNotEqual(handle, 0)

        var metadata = df_spike_chunk_meta_v1()
        XCTAssertEqual(df_spike_stream_arm_allocation_failure_v1(handle), SpikeStatus.ok.rawValue)
        let allocationStatus = destination.withUnsafeMutableBytes { bytes in
            df_spike_stream_next_v1(
                handle,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                UInt64(bytes.count),
                &metadata
            )
        }
        XCTAssertEqual(allocationStatus, SpikeStatus.allocationFailed.rawValue)
        XCTAssertTrue(destination == original)

        XCTAssertEqual(df_spike_stream_arm_panic_v1(handle), SpikeStatus.ok.rawValue)
        let panicStatus = destination.withUnsafeMutableBytes { bytes in
            df_spike_stream_next_v1(
                handle,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                UInt64(bytes.count),
                &metadata
            )
        }
        XCTAssertEqual(panicStatus, SpikeStatus.panic.rawValue)
        XCTAssertTrue(destination == original)
        XCTAssertEqual(df_spike_stream_release_v1(handle), SpikeStatus.ok.rawValue)
    }

    func testLimitsAndRegistryBound() throws {
        XCTAssertThrowsError(try DataForgeStream(configuration: .init(totalRows: 1, chunkRows: 1_001, chunkBytes: 40))) { error in
            XCTAssertEqual(error as? SpikeError, .status(.limitExceeded))
        }
        XCTAssertThrowsError(try DataForgeStream(configuration: .init(totalRows: 1, chunkRows: 1, chunkBytes: 4 * 1024 * 1024 + 1))) { error in
            XCTAssertEqual(error as? SpikeError, .status(.limitExceeded))
        }

        var streams: [DataForgeStream] = []
        streams.reserveCapacity(128)
        for _ in 0..<128 {
            streams.append(try DataForgeStream(configuration: .init(totalRows: 0, chunkRows: 1, chunkBytes: 40)))
        }
        XCTAssertThrowsError(try DataForgeStream(configuration: .init(totalRows: 0, chunkRows: 1, chunkBytes: 40))) { error in
            XCTAssertEqual(error as? SpikeError, .status(.registryFull))
        }
        for stream in streams {
            try stream.close()
        }
        let stats = try DataForgeFFISpike.registryStats()
        XCTAssertEqual(stats.liveStreams, 0)
        XCTAssertEqual(stats.inFlightBytes, 0)
    }

    private struct ParsedRows {
        let rowCount: Int
        let digest: UInt64
    }

    private enum ParseError: Error {
        case malformed
        case wrongValue
    }

    private func parseRows(
        _ bytes: [UInt8],
        expectedFirstRow: UInt64,
        seed: UInt64,
        initialDigest: UInt64
    ) throws -> ParsedRows {
        var offset = 0
        var row = expectedFirstRow
        var digest = initialDigest
        var count = 0
        while offset < bytes.count {
            guard offset + 24 <= bytes.count else { throw ParseError.malformed }
            let index = readUInt64(bytes, offset)
            let valueBits = readUInt64(bytes, offset + 8)
            let textLength = Int(readUInt32(bytes, offset + 16))
            let boolValue = bytes[offset + 20] != 0
            let nullValue = bytes[offset + 21] != 0
            guard bytes[offset + 22] == 0, bytes[offset + 23] == 0,
                  index == row,
                  valueBits == (index ^ seed),
                  boolValue == (index & 1 == 1),
                  nullValue == (index % 10 == 0)
            else { throw ParseError.wrongValue }
            let expectedTextLength = nullValue ? 0 : 16
            guard textLength == expectedTextLength,
                  offset + 24 + textLength <= bytes.count
            else { throw ParseError.malformed }
            if textLength == 16 {
                guard decodeHex(bytes, offset + 24, textLength) == index else {
                    throw ParseError.wrongValue
                }
            }
            offset += 24 + textLength
            row += 1
            count += 1
            digest = mix(digest, index: index, valueBits: valueBits, boolValue: boolValue, nullValue: nullValue)
        }
        return ParsedRows(rowCount: count, digest: digest)
    }

    private func expectedDigest(rowCount: UInt64, seed: UInt64) -> UInt64 {
        var digest = fnvOffset
        for index in 0..<rowCount {
            digest = mix(
                digest,
                index: index,
                valueBits: index ^ seed,
                boolValue: index & 1 == 1,
                nullValue: index % 10 == 0
            )
        }
        return digest
    }

    private func mix(_ initial: UInt64, index: UInt64, valueBits: UInt64, boolValue: Bool, nullValue: Bool) -> UInt64 {
        var digest = initial
        digest ^= index
        digest &*= fnvPrime
        digest ^= valueBits
        digest &*= fnvPrime
        digest ^= boolValue ? 1 : 0
        digest &*= fnvPrime
        digest ^= nullValue ? 1 : 0
        digest &*= fnvPrime
        return digest
    }

    private func fnv1a(_ bytes: [UInt8]) -> UInt64 {
        var hash = fnvOffset
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= fnvPrime
        }
        return hash
    }

    private func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private func readUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(bytes[offset + index]) << UInt64(index * 8)
        }
        return value
    }

    private func decodeHex(_ bytes: [UInt8], _ offset: Int, _ length: Int) -> UInt64? {
        guard length == 16 else { return nil }
        var value: UInt64 = 0
        for index in 0..<length {
            let byte = bytes[offset + index]
            let digit: UInt64
            switch byte {
            case 48...57:
                digit = UInt64(byte - 48)
            case 97...102:
                digit = UInt64(byte - 97 + 10)
            default:
                return nil
            }
            value = (value << 4) | digit
        }
        return value
    }

    private func closeForTest(_ stream: DataForgeStream, file: StaticString = #filePath, line: UInt = #line) {
        do {
            try stream.close()
        } catch {
            XCTFail("stream cleanup failed: \(error)", file: file, line: line)
        }
    }
}
