import CDataForgeFFI
import Foundation

public enum SpikeStatus: Int32, Equatable, Sendable {
    case ok = 0
    case terminal = 1
    case cancelled = 2
    case invalidArgument = 3
    case abiMismatch = 4
    case unsupportedFeature = 5
    case invalidHandle = 6
    case staleHandle = 7
    case registryFull = 8
    case limitExceeded = 9
    case bufferTooSmall = 10
    case needsAck = 11
    case ackMismatch = 12
    case busy = 13
    case allocationFailed = 14
    case panic = 15
    case internalError = 16

    init(code: Int32) {
        self = SpikeStatus(rawValue: code) ?? .internalError
    }
}

public enum SpikeError: Error, Equatable, CustomStringConvertible, Sendable {
    case status(SpikeStatus)
    case unknownStatus(Int32)
    case malformedResponse

    public var description: String {
        switch self {
        case let .status(status):
            "FFI spike returned \(status)"
        case let .unknownStatus(code):
            "FFI spike returned unknown status \(code)"
        case .malformedResponse:
            "FFI spike returned a malformed response"
        }
    }
}

public struct NegotiatedABI: Equatable, Sendable {
    public let abiVersion: UInt32
    public let supportedFeatures: UInt64
    public let maxStreams: UInt32
    public let maxChunkRows: UInt32
    public let maxChunkBytes: UInt32
    public let rowEncodingVersion: UInt32
}

public struct StreamConfiguration: Equatable, Sendable {
    public let totalRows: UInt64
    public let seed: UInt64
    public let chunkRows: UInt32
    public let chunkBytes: UInt32

    public init(totalRows: UInt64, seed: UInt64 = 0, chunkRows: UInt32 = 200, chunkBytes: UInt32 = 64 * 1024) {
        self.totalRows = totalRows
        self.seed = seed
        self.chunkRows = chunkRows
        self.chunkBytes = chunkBytes
    }
}

public struct ChunkMetadata: Equatable, Sendable {
    public let sequence: UInt64
    public let firstRow: UInt64
    public let rowCount: UInt32
    public let byteCount: UInt32
    public let encodingVersion: UInt32
    public let flags: UInt32
    public let checksum: UInt64
}

public struct Chunk: Equatable, Sendable {
    public let bytes: [UInt8]
    public let metadata: ChunkMetadata
}

public enum CancelOutcome: Equatable, Sendable {
    case accepted
    case pendingAcknowledgement
    case alreadyRequested
    case tooLate
}

public struct StreamStatusSnapshot: Equatable, Sendable {
    public let state: UInt32
    public let terminalError: UInt32
    public let nextRow: UInt64
    public let totalRows: UInt64
    public let outstandingSequence: UInt64?
    public let lastError: UInt32
}

public struct RegistryStats: Equatable, Sendable {
    public let liveStreams: UInt32
    public let maxStreams: UInt32
    public let inFlightBytes: UInt64
    public let createdStreams: UInt64
    public let releasedStreams: UInt64
}

public enum DataForgeFFISpike {
    public static let abiVersion: UInt32 = 1
    public static let rowEncodingVersion: UInt32 = 1
    public static let featurePullAck: UInt64 = 1 << 0
    public static let featureCancellation: UInt64 = 1 << 1
    public static let featureTypedRows: UInt64 = 1 << 2
    public static let featurePanicContainment: UInt64 = 1 << 3
    public static let featureCallerBuffer: UInt64 = 1 << 4
    public static let requiredFeatures: UInt64 = featurePullAck
        | featureCancellation
        | featureTypedRows
        | featurePanicContainment
        | featureCallerBuffer

    public static func negotiate(requiredFeatures: UInt64 = DataForgeFFISpike.requiredFeatures) throws -> NegotiatedABI {
        var request = df_spike_abi_request_v1(
            struct_size: UInt32(MemoryLayout<df_spike_abi_request_v1>.size),
            abi_version: abiVersion,
            required_features: requiredFeatures,
            optional_features: 0,
            reserved0: 0,
            reserved1: 0
        )
        var response = df_spike_abi_info_v1()
        let code = df_spike_abi_negotiate_v1(&request, &response)
        try throwIfFailure(code)
        guard response.struct_size >= UInt32(MemoryLayout<df_spike_abi_info_v1>.size),
              response.abi_version == abiVersion,
              response.supported_features & requiredFeatures == requiredFeatures,
              response.row_encoding_version == rowEncodingVersion
        else {
            throw SpikeError.malformedResponse
        }
        return NegotiatedABI(
            abiVersion: response.abi_version,
            supportedFeatures: response.supported_features,
            maxStreams: response.max_streams,
            maxChunkRows: response.max_chunk_rows,
            maxChunkBytes: response.max_chunk_bytes,
            rowEncodingVersion: response.row_encoding_version
        )
    }

    public static func registryStats() throws -> RegistryStats {
        var response = df_spike_registry_stats_v1()
        let code = df_spike_get_registry_stats_v1(&response)
        try throwIfFailure(code)
        guard response.struct_size >= UInt32(MemoryLayout<df_spike_registry_stats_v1>.size),
              response.abi_version == abiVersion
        else {
            throw SpikeError.malformedResponse
        }
        return RegistryStats(
            liveStreams: response.live_streams,
            maxStreams: response.max_streams,
            inFlightBytes: response.in_flight_bytes,
            createdStreams: response.created_streams,
            releasedStreams: response.released_streams
        )
    }

    public static func panicProbe() throws {
        let code = df_spike_panic_probe_v1()
        try throwIfFailure(code)
    }

    static func throwIfFailure(_ code: Int32) throws {
        guard code == SpikeStatus.ok.rawValue else {
            if let status = SpikeStatus(rawValue: code) {
                throw SpikeError.status(status)
            }
            throw SpikeError.unknownStatus(code)
        }
    }
}

public final class DataForgeStream {
    public let configuration: StreamConfiguration
    private var handle: UInt64?
    private var outstandingSequence: UInt64?

    public init(configuration: StreamConfiguration) throws {
        self.configuration = configuration
        var options = df_spike_stream_options_v1(
            struct_size: UInt32(MemoryLayout<df_spike_stream_options_v1>.size),
            abi_version: DataForgeFFISpike.abiVersion,
            total_rows: configuration.totalRows,
            seed: configuration.seed,
            requested_chunk_rows: configuration.chunkRows,
            requested_chunk_bytes: configuration.chunkBytes,
            reserved0: 0,
            reserved1: 0
        )
        var createdHandle: UInt64 = 0
        let code = df_spike_stream_create_v1(&options, &createdHandle)
        try DataForgeFFISpike.throwIfFailure(code)
        guard createdHandle != 0 else {
            throw SpikeError.malformedResponse
        }
        self.handle = createdHandle
    }

    deinit {
        closeWithoutThrowing()
    }

    public func next() throws -> Chunk? {
        let streamHandle = try requireHandle()
        var capacity = max(Int(configuration.chunkBytes), 40)
        while true {
            var buffer = [UInt8](repeating: 0, count: capacity)
            var metadata = df_spike_chunk_meta_v1()
            let code = buffer.withUnsafeMutableBytes { rawBuffer -> Int32 in
                let pointer = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return df_spike_stream_next_v1(
                    streamHandle,
                    pointer,
                    UInt64(rawBuffer.count),
                    &metadata
                )
            }
            if code == SpikeStatus.terminal.rawValue {
                return nil
            }
            if code == SpikeStatus.cancelled.rawValue {
                throw SpikeError.status(.cancelled)
            }
            if code == SpikeStatus.bufferTooSmall.rawValue {
                let required = Int(metadata.required_capacity)
                guard required > capacity, required <= 4 * 1024 * 1024 else {
                    throw SpikeError.malformedResponse
                }
                capacity = required
                continue
            }
            try DataForgeFFISpike.throwIfFailure(code)
            let byteCount = Int(metadata.byte_count)
            guard metadata.struct_size >= UInt32(MemoryLayout<df_spike_chunk_meta_v1>.size),
                  metadata.abi_version == DataForgeFFISpike.abiVersion,
                  byteCount <= buffer.count,
                  metadata.row_count > 0,
                  metadata.sequence > 0
            else {
                throw SpikeError.malformedResponse
            }
            let chunk = Chunk(
                bytes: Array(buffer.prefix(byteCount)),
                metadata: ChunkMetadata(
                    sequence: metadata.sequence,
                    firstRow: metadata.first_row,
                    rowCount: metadata.row_count,
                    byteCount: metadata.byte_count,
                    encodingVersion: metadata.encoding_version,
                    flags: metadata.flags,
                    checksum: metadata.checksum
                )
            )
            outstandingSequence = metadata.sequence
            return chunk
        }
    }

    public func acknowledge(sequence: UInt64? = nil) throws {
        let streamHandle = try requireHandle()
        let sequenceToAck = sequence ?? outstandingSequence
        guard let sequenceToAck else {
            throw SpikeError.status(.ackMismatch)
        }
        let code = df_spike_stream_ack_v1(streamHandle, sequenceToAck)
        try DataForgeFFISpike.throwIfFailure(code)
        if outstandingSequence == sequenceToAck {
            outstandingSequence = nil
        }
    }

    @discardableResult
    public func cancel() throws -> CancelOutcome {
        let streamHandle = try requireHandle()
        var response = df_spike_cancel_outcome_v1()
        let code = df_spike_stream_cancel_v1(streamHandle, &response)
        try DataForgeFFISpike.throwIfFailure(code)
        switch response.outcome {
        case 1:
            return .accepted
        case 2:
            return .pendingAcknowledgement
        case 3:
            return .alreadyRequested
        case 4:
            return .tooLate
        default:
            throw SpikeError.malformedResponse
        }
    }

    public func status() throws -> StreamStatusSnapshot {
        let streamHandle = try requireHandle()
        var response = df_spike_stream_status_v1()
        let code = df_spike_stream_get_status_v1(streamHandle, &response)
        try DataForgeFFISpike.throwIfFailure(code)
        guard response.struct_size >= UInt32(MemoryLayout<df_spike_stream_status_v1>.size),
              response.abi_version == DataForgeFFISpike.abiVersion
        else {
            throw SpikeError.malformedResponse
        }
        return StreamStatusSnapshot(
            state: response.state,
            terminalError: response.terminal_error,
            nextRow: response.next_row,
            totalRows: response.total_rows,
            outstandingSequence: response.outstanding_sequence == 0 ? nil : response.outstanding_sequence,
            lastError: response.last_error
        )
    }

    public func armAllocationFailureForNextChunk() throws {
        let streamHandle = try requireHandle()
        let code = df_spike_stream_arm_allocation_failure_v1(streamHandle)
        try DataForgeFFISpike.throwIfFailure(code)
    }

    public func armPanicForNextChunk() throws {
        let streamHandle = try requireHandle()
        let code = df_spike_stream_arm_panic_v1(streamHandle)
        try DataForgeFFISpike.throwIfFailure(code)
    }

    public func close() throws {
        guard handle != nil else { return }
        if let outstandingSequence {
            try acknowledge(sequence: outstandingSequence)
        }
        let streamHandle = try requireHandle()
        let code = df_spike_stream_release_v1(streamHandle)
        try DataForgeFFISpike.throwIfFailure(code)
        handle = nil
    }

    private func closeWithoutThrowing() {
        guard let streamHandle = handle else { return }
        if let outstandingSequence {
            _ = df_spike_stream_ack_v1(streamHandle, outstandingSequence)
        }
        let code = df_spike_stream_release_v1(streamHandle)
        if code != SpikeStatus.ok.rawValue {
            assertionFailure("FFI spike stream cleanup failed with status \(code)")
        }
    }

    private func requireHandle() throws -> UInt64 {
        guard let handle else {
            throw SpikeError.status(.staleHandle)
        }
        return handle
    }
}
