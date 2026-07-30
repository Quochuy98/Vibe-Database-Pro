# DataForge for macOS

DataForge is the working codename for an independent, native macOS database client. The product is being designed for developers, DBAs, and data engineers who need safe connection management, query execution, data editing, schema tools, transfer workflows, and database observability without sacrificing credential security or data integrity.

> Status: architecture and product planning only. This repository does not yet contain production implementation. A separate, reviewed implementation request is required before production code is started.

## Product direction

- Native SwiftUI application shell with focused AppKit components for desktop-grade editor, outline, and grid behavior.
- Rust core behind capability-based database adapters for streaming query execution, cancellation, metadata normalization, and data-intensive pipelines.
- Versioned C ABI with explicit ownership, bounded chunk transfer, cancellation, and panic containment at the Swift/Rust boundary.
- PostgreSQL as the first complete vertical slice, followed by MySQL, MariaDB, and SQLite.
- SQLite for non-sensitive local metadata and macOS Keychain for every credential or secret.
- Direct Developer ID distribution, Hardened Runtime, notarization, and signed updates as the initial distribution model.
- Safety defaults for production connections, destructive statements, transactions, editable grids, imports, exports, and synchronization.

The baseline assumptions above remain subject to the Architecture Decision Record acceptance process and the Milestone 0 technical spikes.

## Planning documents

### Product and delivery

- [Product specification](docs/PRODUCT_SPEC.md)
- [Feature matrix](docs/FEATURE_MATRIX.md)
- [User flows](docs/USER_FLOWS.md)
- [UX wireframes](docs/UX_WIREFRAMES.md)
- [Roadmap](docs/ROADMAP.md)
- [Implementation backlog](docs/BACKLOG.md)
- [Risks and unknowns](docs/RISKS.md)

### Architecture and adapters

- [System architecture](docs/ARCHITECTURE.md)
- [Database adapter model](docs/DATABASE_ADAPTERS.md)
- [Architecture Decision Records](docs/adr/README.md)
- [DF-M0-001 C ABI streaming evidence](docs/reports/DF-M0-001-ffi-streaming-evidence.md)
- [DF-M0-002 PostgreSQL driver evidence](docs/reports/DF-M0-002-postgres-driver-evidence.md)
- [DF-M0-003 TextKit editor evidence](docs/reports/DF-M0-003-textkit-editor-evidence.md)
- [DF-M0-004 AppKit grid evidence](docs/reports/DF-M0-004-appkit-grid-evidence.md)
- [DF-M0-005 SSH tunnel/host-trust evidence](docs/reports/DF-M0-005-ssh-tunnel-evidence.md)

### Assurance and release

- [Security threat model](docs/SECURITY_THREAT_MODEL.md)
- [Database safety model](docs/DATABASE_SAFETY.md)
- [Test strategy](docs/TEST_STRATEGY.md)
- [Performance budget](docs/PERFORMANCE_BUDGET.md)
- [Distribution strategy](docs/DISTRIBUTION_STRATEGY.md)

## Governing rules

All work must follow [AGENTS.md](AGENTS.md). In particular:

1. Never trade data safety for delivery speed.
2. Never persist or log plaintext credentials.
3. Keep UI, application services, domain interfaces, core, and database drivers separated.
4. Stream and bound large data paths; never load an unbounded result set into memory.
5. Treat database writes, destructive SQL, transaction state, and row identity as safety-critical.
6. Add tests with every production change and use only disposable or isolated test databases.
7. Preserve an independent product identity and do not copy commercial source, assets, wording, or proprietary interaction design.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development gate and [SECURITY.md](SECURITY.md) for responsible disclosure and repository security policy.

## Current scope

The repository may contain documentation, decision records, specifications,
risk analysis, and tightly scoped disposable feasibility spikes. It must not
claim production implementation from a spike or import spike code into a
product target. The proposed first production task remains recorded in the
roadmap/backlog only after architecture, safety, test, and performance gates
are defined.

## License

The planning recommendation is a proprietary commercial application with a future Community/Pro seam, but no final license text has been selected or granted by this repository. Dependency candidates are evaluations, not approved dependencies. Legal and security review is required before adoption or distribution.
