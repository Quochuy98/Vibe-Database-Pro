# DF-M0-004 sanitized raw evidence

These JSON files preserve the complete measurements from the disposable grid
evidence runner at source commit
`7acdec023b1debab1daf4af354f8b9968ee9f32b`:

- `bf02-1000000.json`
- `bf02-10000000.json`
- `bf03-100000.json`

Each file contains one unreported warm-up plus ten measured samples, including
every forced-layout/theme latency value and every scripted scroll-step value.
The timings are diagnostic proxies unless the field explicitly describes the
synthetic cancellation coordinator. They are not Core Animation presented
frames or VoiceOver evidence.

Post-run review correction on 2026-08-01 changed only the explanatory
`accessibility.note` in the two BF-02 records: those fixtures have no frozen
projection and their automated metadata smoke reports one logical table. No
timing, count, boolean, fixture checksum, source identity or disposition was
changed. BF-03 retains its different note because that two-projection fixture
has three frozen columns and fails the one-logical-table metadata smoke.

The historical `cellReuseWithinTwoTimesVisibleBudget` name is potentially
misleading. Source commit `7acdec0…f32b` computes it exactly as
`peakAvailableCellViews > 0 && createdCellViews <=
peakAvailableCellViews * 2`. It uses the available view graph after the cold
layout/reset as a steady-scroll allocation-churn denominator.
`peakGeometricallyVisibleCells` is instead the denominator for
`horizontalViewExpansionRatio`. Thus the recorded `true` reuse booleans do not
claim a two-dimensional viewport bound and do not change the 2.16× BF-02 or
45.45× BF-03 expansion results.

The files contain only deterministic fixture identity/counts, timing and
resource inventories, and coarse host/toolchain-independent environment
fields emitted by the runner. They must not contain usernames, absolute paths,
serial numbers, credentials, SQL, row payloads or customer data.

The evidence report records each file's byte length and SHA-256 after the three
JSON documents parse successfully. Transient Instruments traces remain outside
Git because they include local process/device metadata.
