import DataForgeFFISpike
import Foundation

private struct Sample {
    let elapsedMilliseconds: Double
    let chunkMilliseconds: [Double]
    let rows: UInt64
    let chunks: UInt64
    let payloadBytes: UInt64
    let checksumDigest: UInt64
}

@main
private enum DataForgeFFIBenchmark {
    private static let measuredSampleCount = 10
    private static let totalRows: UInt64 = 1_000_000
    private static let expectedChunks: UInt64 = 1_000

    static func main() throws {
        if CommandLine.arguments.dropFirst().contains("--idle") {
            let negotiated = try DataForgeFFISpike.negotiate()
            print("DF_M0_001_IDLE abi=\(negotiated.abiVersion) max_chunk_bytes=\(negotiated.maxChunkBytes)")
            Thread.sleep(forTimeInterval: 0.25)
            return
        }

        _ = try runSample() // Warm-up; deliberately excluded from statistics.

        var samples: [Sample] = []
        samples.reserveCapacity(measuredSampleCount)
        for _ in 0..<measuredSampleCount {
            samples.append(try runSample())
        }

        guard let reference = samples.first,
              samples.allSatisfy({
                  $0.rows == totalRows
                      && $0.chunks == expectedChunks
                      && $0.payloadBytes == reference.payloadBytes
                      && $0.checksumDigest == reference.checksumDigest
              })
        else {
            throw SpikeError.malformedResponse
        }

        let elapsed = samples.map(\.elapsedMilliseconds)
        let chunkLatency = samples.flatMap(\.chunkMilliseconds)
        let elapsedMedian = percentile(elapsed, fraction: 0.50)
        let rowsPerSecond = Double(totalRows) / (elapsedMedian / 1_000)
        let crossBoundaryCopies = reference.chunks
        let wrapperCopies = reference.chunks
        let copiedBytes = try multiply(reference.payloadBytes, by: 2)
        let stats = try DataForgeFFISpike.registryStats()
        guard stats.liveStreams == 0, stats.inFlightBytes == 0 else {
            throw SpikeError.malformedResponse
        }

        print(
            String(
                format: "DF_M0_001_BENCHMARK samples=%d warmups=1 rows=%llu chunks=%llu payload_bytes=%llu checksum=%llu e2e_ms_median=%.3f e2e_ms_p95=%.3f e2e_ms_worst=%.3f chunk_ms_median=%.6f chunk_ms_p95=%.6f chunk_ms_worst=%.6f rows_per_second=%.0f",
                measuredSampleCount,
                reference.rows,
                reference.chunks,
                reference.payloadBytes,
                reference.checksumDigest,
                elapsedMedian,
                percentile(elapsed, fraction: 0.95),
                elapsed.max() ?? 0,
                percentile(chunkLatency, fraction: 0.50),
                percentile(chunkLatency, fraction: 0.95),
                chunkLatency.max() ?? 0,
                rowsPerSecond
            )
        )
        print(
            "DF_M0_001_COPY_MODEL encoding_writes=1 ffi_copy_operations=\(crossBoundaryCopies) wrapper_copy_operations=\(wrapperCopies) full_payload_copy_passes=2 copied_bytes_per_sample=\(copiedBytes) retained_rust_chunk_bytes=\(stats.inFlightBytes)"
        )
    }

    private static func runSample() throws -> Sample {
        let stream = try DataForgeStream(
            configuration: .init(
                totalRows: totalRows,
                seed: 7,
                chunkRows: 1_000,
                chunkBytes: 4 * 1024 * 1024
            )
        )

        let clock = ContinuousClock()
        let sampleStart = clock.now
        var rows: UInt64 = 0
        var chunks: UInt64 = 0
        var payloadBytes: UInt64 = 0
        var checksumDigest: UInt64 = 0
        var chunkMilliseconds: [Double] = []
        chunkMilliseconds.reserveCapacity(Int(expectedChunks))

        while true {
            let chunkStart = clock.now
            guard let chunk = try stream.next() else { break }
            try stream.acknowledge(sequence: chunk.metadata.sequence)
            let chunkEnd = clock.now

            rows = try add(rows, UInt64(chunk.metadata.rowCount))
            chunks = try add(chunks, 1)
            payloadBytes = try add(payloadBytes, UInt64(chunk.metadata.byteCount))
            checksumDigest ^= chunk.metadata.checksum
            chunkMilliseconds.append(milliseconds(chunkStart.duration(to: chunkEnd)))
        }
        let sampleEnd = clock.now
        try stream.close()

        return Sample(
            elapsedMilliseconds: milliseconds(sampleStart.duration(to: sampleEnd)),
            chunkMilliseconds: chunkMilliseconds,
            rows: rows,
            chunks: chunks,
            payloadBytes: payloadBytes,
            checksumDigest: checksumDigest
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func percentile(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(Double(sorted.count) * fraction)))
        return sorted[min(rank - 1, sorted.count - 1)]
    }

    private static func add(_ left: UInt64, _ right: UInt64) throws -> UInt64 {
        let (sum, overflow) = left.addingReportingOverflow(right)
        guard !overflow else { throw SpikeError.malformedResponse }
        return sum
    }

    private static func multiply(_ value: UInt64, by multiplier: UInt64) throws -> UInt64 {
        let (product, overflow) = value.multipliedReportingOverflow(by: multiplier)
        guard !overflow else { throw SpikeError.malformedResponse }
        return product
    }
}
