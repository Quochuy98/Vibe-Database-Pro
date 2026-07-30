# ADR-0005: Store all credentials in macOS Keychain

Status: Accepted for planning; security review required before implementation

Date: 2026-07-29

## Context

Connections may use database passwords, SSH passwords/keys/passphrases, API/OAuth tokens, client certificate identities and cloud secrets. Plaintext persistence, routine exports, logging and crash capture are prohibited.

## Options considered

1. macOS Keychain through Security.framework.
2. Encrypted values in local SQLite with an application master key.
3. UserDefaults/files.
4. External password-manager-only integration.

## Decision

Use Security.framework Keychain Services and the data-protection Keychain for every small secret. Non-sensitive SQLite metadata contains only a random credential-reference ID. Secrets are retrieved as short-lived, non-`Codable`, non-loggable credential leases immediately before use. Synchronization is off unless a later explicit user-facing decision permits a specific type.

## Reasons

- Keychain is the platform security boundary intended for passwords, keys, certificates and tokens.
- It provides encryption and per-application access controls without inventing key management.
- A reference separates portable connection metadata from non-exportable credentials.

## Trade-offs and risks

- Keychain prompts, lock state, ACL/access-group changes and background helper access need careful UX.
- Secrets necessarily exist briefly in process memory for protocols that require them.
- Migration between app signing identities can break access.
- Secure Enclave cannot store arbitrary imported database passwords/keys.

## Rules and consequences

- Never fall back to plaintext when Keychain is locked/unavailable.
- No secret in `UserDefaults`, SQLite, JSON export, log, crash report, telemetry, test fixture/snapshot/screenshot or long-lived clipboard.
- Connection export excludes credentials by default; production credentials are never exported.
- Keychain errors are typed and actionable without exposing secret attributes.
- Background automation has a separately reviewed access group/accessibility policy and cannot weaken interactive storage.
- Memory copies are minimized and zeroized where practical; redaction tests use seeded canaries.

## Validation before implementation

- Add/read/update/delete, duplicate, denied, locked, missing, ACL/signature migration and cancellation tests.
- Seeded secret never appears in persisted metadata, logs, diagnostics, crash envelope or export.
- Helper access is denied unless explicitly approved and code-signed as expected.
- Threat-model review of accessibility class and user-presence policy per credential kind.

## Revisit when

Enterprise managed-secret integration is required. It may add a credential-provider port, but may not replace safe Keychain defaults with plaintext persistence.
