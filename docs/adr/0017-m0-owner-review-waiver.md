# ADR-0017: Waive independent external review as an M0 exit gate

- **Status:** Accepted for planning by repository product-owner direction;
  production implementation still requires a separate explicit request
- **Date:** 2026-08-01
- **Supersedes:** Only the mandatory M0 external-review closure portions of
  ADR-0015 and ADR-0016
- **Does not supersede:** Dependency adoption, license, security, executable
  accessibility, database-safety, distribution or release gates
- **Related:** DF-M0-008, DF-M0-009, M0 external-review packet, R-04, R-18,
  R-20, R-21, R-25, R-29

## Context

DF-M0-008 and DF-M0-009 produced durable dependency and wireframe evidence but
made eight independent external-review lanes a prerequisite for closing M0.
The repository product owner subsequently directed that those reviews are not
required. The direct instruction has higher repository priority than the prior
planning documents.

That instruction cannot honestly be represented as eight completed reviews.
No engineering agent can supply qualified legal advice, manual VoiceOver
evidence or an independent security disposition. The decision therefore needs
an explicit owner waiver that preserves missing evidence instead of converting
unknown facts into approvals.

## Decision

1. **Remove the eight external-review lanes as an M0 exit prerequisite.** The
   lanes remain documented as optional future review scopes, with no reviewer,
   result or date fabricated.
2. **Close DF-M0-008 and DF-M0-009 at planning-artifact scope.** Their reports,
   matrices, owners and revisit triggers are complete enough to feed later
   milestones. This does not change `0 approve / 10 defer / 3 reject` or make
   any dependency distributable.
3. **Authorize M0 planning exit, not production implementation.** DF-M1-001
   still requires the separate implementation request mandated by
   `MASTER_PROMPT.md` and `CONTRIBUTING.md`.
4. **Keep adoption and release fail-closed.** Before an exact dependency is
   added or a release is distributed, its identity, graph, license/notices,
   advisories, integration, product-size and SBOM evidence must pass the
   dependency policy. Qualified legal review remains mandatory where license,
   redistribution, service, privacy or commercial terms require it.
5. **Move UI assurance to executable milestone gates.** M1/M2 must run the
   planned keyboard, accessibility, VoiceOver, appearance, localization,
   performance, credential-lifecycle and database-safety tests. The owner
   waiver is not an accessibility or security pass.
6. **Preserve dangerous-operation invariants.** No waiver may remove
   production/read-only context, destructive-query safeguards, exact row
   identity, transaction warnings, rollback/unknown-outcome behavior,
   credential redaction or bounded streaming.
7. **Revisit this decision** before the first production dependency adoption,
   before enabling SSH, and before the first externally distributed build.

## Residual risk and compensating controls

The project loses independent challenge of the planning dossier and static UX
contract. The residual risk is accepted only for moving from M0 planning to a
separately authorized M1 scaffold. It is not accepted for dependency adoption,
production database behavior or release.

Compensating controls are:

- all unapproved candidates remain deferred or rejected;
- SSH remains disabled;
- no production source or manifest is created by this decision;
- every M1/M2 production change requires executable success, failure, edge,
  cancellation and security evidence;
- database tests remain disposable and guarded; and
- release, signing, license and legal gates remain independent of M0 exit.

## Consequences

- The historical external-review packet becomes a waiver/disposition record.
- Eight review lanes are recorded as waived for M0, not completed.
- M0 planning exit is authorized by the owner decision.
- Production implementation authority remains false until a separate direct
  request is received.
- The absence of legal, security, accessibility and runtime evidence remains
  visible in the risk register and candidate dispositions.
