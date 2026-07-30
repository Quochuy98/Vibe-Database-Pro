# DF-M0-004 sanitized raw evidence

These JSON files are the complete machine-readable output from the disposable
grid evidence runner at source commit
`7acdec023b1debab1daf4af354f8b9968ee9f32b`:

- `bf02-1000000.json`
- `bf02-10000000.json`
- `bf03-100000.json`

Each file contains one unreported warm-up plus ten measured samples, including
every forced-layout/theme latency value and every scripted scroll-step value.
The timings are diagnostic proxies unless the field explicitly describes the
synthetic cancellation coordinator. They are not Core Animation presented
frames or VoiceOver evidence.

The files contain only deterministic fixture identity/counts, timing and
resource inventories, and coarse host/toolchain-independent environment
fields emitted by the runner. They must not contain usernames, absolute paths,
serial numbers, credentials, SQL, row payloads or customer data.

The evidence report records each file's byte length and SHA-256 after the three
JSON documents parse successfully. Transient Instruments traces remain outside
Git because they include local process/device metadata.
