mod candidate;
mod config;
mod hostile;
mod model;
mod trust;

use std::io::Write;
use std::sync::Arc;
use std::time::Instant;

use candidate::{
    CHANNEL_MESSAGE_CAPACITY, CHANNEL_WINDOW_BYTES, CLEANUP_DEADLINE, CandidateError,
    HANDSHAKE_DEADLINE, MAX_AGENT_FRAME_BYTES, MAX_AGENT_IDENTITIES, MAX_TRUST_STORE_BYTES,
    MAX_TRUST_STORE_LINE_BYTES, MAX_TRUST_STORE_LINES, MAXIMUM_PACKET_BYTES, REPETITION_CYCLES,
    TransportPolicy, close_session, connect_agent, execute_connection_plan, load_private_key,
    probe_trust, resident_kib, trust_store_snapshot, verify_destination_failure_cleanup,
    verify_forward_banner, verify_forward_cancellation, verify_jump, verify_oversized_agent_frame,
    verify_repetition,
};
use config::ProbeConfig;
use hostile::{HOSTILE_BANNER_BYTES, HostileMode, run_hostile_case};
use model::{Bounds, Candidate, Evidence, Scenario, Status, Summary};
use trust::TrustOutcome;

const HOSTILE_RSS_DELTA_LIMIT_KIB: i64 = 16 * 1024;
const REPETITION_RSS_DELTA_LIMIT_KIB: i64 = 32 * 1024;
const REPETITION_FD_DELTA_LIMIT: i64 = 1;

#[tokio::main]
async fn main() {
    let exit_code = match run().await {
        Ok(evidence) => {
            let failed = evidence.summary.fail > 0;
            let stdout = std::io::stdout();
            let mut output = stdout.lock();
            if serde_json::to_writer_pretty(&mut output, &evidence).is_err()
                || writeln!(output).is_err()
            {
                70
            } else if failed {
                1
            } else {
                0
            }
        }
        Err(()) => {
            eprintln!("DF-M0-005 russh probe failed before sanitized evidence was available.");
            70
        }
    };
    std::process::exit(exit_code);
}

async fn run() -> Result<Evidence, ()> {
    let config = ProbeConfig::from_process_args().map_err(|_| ())?;
    let key = load_private_key(&config.key_path).await.map_err(|_| ())?;
    let mut scenarios = Vec::new();

    scenarios.push(
        trust_scenario(
            "TR-01",
            &config,
            &config.known_correct,
            Arc::clone(&key),
            TrustOutcome::Matched,
            None,
        )
        .await,
    );
    let unknown_before = trust_store_snapshot(&config.known_empty).await;
    let unknown = trust_scenario(
        "TR-02",
        &config,
        &config.known_empty,
        Arc::clone(&key),
        TrustOutcome::Unknown,
        Some(CandidateError::TrustUnknown),
    )
    .await;
    let unknown_after = trust_store_snapshot(&config.known_empty).await;
    let unknown_mutated = snapshots_differ(&unknown_before, &unknown_after);
    scenarios.push(
        unknown
            .observe("trust_store_mutated", unknown_mutated)
            .fail_if(unknown_mutated, "trust_store_mutation"),
    );

    let changed_before = trust_store_snapshot(&config.known_bastion_mismatch).await;
    let changed = trust_scenario(
        "TR-03",
        &config,
        &config.known_bastion_mismatch,
        Arc::clone(&key),
        TrustOutcome::Changed,
        Some(CandidateError::TrustChanged),
    )
    .await;
    let changed_after = trust_store_snapshot(&config.known_bastion_mismatch).await;
    let changed_mutated = snapshots_differ(&changed_before, &changed_after);
    scenarios.push(
        changed
            .observe("trust_store_mutated", changed_mutated)
            .fail_if(changed_mutated, "trust_store_mutation"),
    );
    scenarios.push(
        trust_scenario(
            "TR-04",
            &config,
            &config.known_hashed,
            Arc::clone(&key),
            TrustOutcome::Matched,
            None,
        )
        .await,
    );
    let revoked_before = trust_store_snapshot(&config.known_revoked).await;
    let revoked = trust_scenario(
        "TR-05",
        &config,
        &config.known_revoked,
        Arc::clone(&key),
        TrustOutcome::Revoked,
        Some(CandidateError::TrustRevoked),
    )
    .await
    .observe("revoked_classified_as", "revoked")
    .observe("failed_closed", true);
    let revoked_after = trust_store_snapshot(&config.known_revoked).await;
    let revoked_mutated = snapshots_differ(&revoked_before, &revoked_after);
    let revoked = revoked
        .observe("trust_store_mutated", revoked_mutated)
        .fail_if(revoked_mutated, "trust_store_mutation");
    scenarios.push(revoked);

    let key_permission_started = Instant::now();
    let insecure_result = load_private_key(&config.insecure_key_path).await;
    let key_permission_passed =
        matches!(insecure_result, Err(CandidateError::InsecureKeyPermissions));
    scenarios.push(
        Scenario::new(
            "AU-01",
            if key_permission_passed {
                Status::Pass
            } else {
                Status::Fail
            },
            if key_permission_passed {
                "key_permissions"
            } else {
                "key_permission_regression"
            },
            key_permission_started.elapsed().as_millis(),
        )
        .observe("mode_0600_loaded", true)
        .observe("mode_0644_rejected_before_auth", key_permission_passed),
    );

    scenarios.push(
        Scenario::new("AU-02", Status::Unsupported, "password_disabled", 0)
            .observe(
                "reason",
                "upstream_password_retention_and_debug_payload_logging",
            )
            .observe("credential_entered_runtime", false),
    );

    let agent_started = Instant::now();
    let agent_result = match connect_agent(&config, &config.known_correct).await {
        Ok(session) => close_session(session).await,
        Err(error) => Err(error),
    };
    let oversized_agent_result = verify_oversized_agent_frame().await;
    let agent_passed = agent_result.is_ok() && oversized_agent_result.is_ok();
    scenarios.push(
        Scenario::new(
            "AU-03",
            if agent_passed {
                Status::Unsupported
            } else {
                Status::Fail
            },
            if agent_passed {
                "partial_agent_evidence"
            } else {
                first_error_category(&agent_result, &oversized_agent_result)
            },
            agent_started.elapsed().as_millis(),
        )
        .observe("ephemeral_agent_auth", agent_result.is_ok())
        .observe("oversized_frame_rejected", oversized_agent_result.is_ok())
        .observe("frame_limit_bytes", MAX_AGENT_FRAME_BYTES as u64)
        .observe("identity_limit", MAX_AGENT_IDENTITIES as u64)
        .observe(
            "not_exercised",
            "missing_malformed_stalled_agent_socket_identity_and_failure_cleanup",
        ),
    );

    let jump_started = Instant::now();
    let jump_ok = verify_jump(&config, &config.known_correct, Arc::clone(&key)).await;
    let target_mismatch =
        verify_jump(&config, &config.known_target_mismatch, Arc::clone(&key)).await;
    let bastion_mismatch =
        verify_jump(&config, &config.known_bastion_mismatch, Arc::clone(&key)).await;
    let jump_passed = jump_ok.is_ok()
        && target_mismatch == Err(CandidateError::TrustChanged)
        && bastion_mismatch == Err(CandidateError::TrustChanged);
    scenarios.push(
        Scenario::new(
            "JP-01",
            if jump_passed {
                Status::Pass
            } else {
                Status::Fail
            },
            if jump_passed {
                "jump_trust"
            } else {
                "jump_trust_regression"
            },
            jump_started.elapsed().as_millis(),
        )
        .observe("both_hops_authenticated", jump_ok.is_ok())
        .observe(
            "target_mismatch_rejected",
            target_mismatch == Err(CandidateError::TrustChanged),
        )
        .observe(
            "bastion_mismatch_rejected",
            bastion_mismatch == Err(CandidateError::TrustChanged),
        ),
    );

    let (tunnel_failure, attempts) =
        execute_connection_plan(TransportPolicy::TunnelRequired, false, true);
    let (direct_success, direct_policy_attempts) =
        execute_connection_plan(TransportPolicy::DirectAllowed, false, true);
    scenarios.push(
        Scenario::new(
            "JP-02",
            if tunnel_failure == Err(CandidateError::Ssh)
                && attempts.jump == 1
                && attempts.direct == 0
                && direct_success.is_ok()
                && direct_policy_attempts.jump == 0
                && direct_policy_attempts.direct == 1
            {
                Status::Unsupported
            } else {
                Status::Fail
            },
            "model_only_no_direct_fallback",
            0,
        )
        .observe("jump_attempts", attempts.jump as u64)
        .observe("direct_attempts_after_failure", attempts.direct as u64)
        .observe(
            "explicit_direct_policy_direct_attempts",
            direct_policy_attempts.direct as u64,
        )
        .observe("evidence_kind", "deterministic_plan_test")
        .observe("network_connector_trap_executed", false),
    );

    let forward_banner =
        verify_forward_banner(&config, &config.known_correct, Arc::clone(&key)).await;
    scenarios.push(
        Scenario::new(
            "TN-01",
            if forward_banner.is_ok() {
                Status::Unsupported
            } else {
                Status::Fail
            },
            if forward_banner.is_ok() {
                "direct_tcpip_banner_smoke_only"
            } else {
                forward_banner
                    .err()
                    .map_or("forwarding_regression", CandidateError::category)
            },
            0,
        )
        .observe("direct_tcpip_banner_received", forward_banner.is_ok())
        .observe("local_listener_measured", false)
        .observe("echo_roundtrip_executed", false),
    );

    let cancellation_started = Instant::now();
    let cancellation =
        verify_forward_cancellation(&config, &config.known_correct, Arc::clone(&key)).await;
    let cancellation_status = cancellation
        .as_ref()
        .is_ok_and(|metrics| metrics.listener_closed);
    let mut cancellation_scenario = Scenario::new(
        "TN-02",
        if cancellation_status {
            Status::Pass
        } else {
            Status::Fail
        },
        cancellation
            .as_ref()
            .err()
            .copied()
            .map_or("cancellation", CandidateError::category),
        cancellation_started.elapsed().as_millis(),
    )
    .observe("cleanup_deadline_ms", CLEANUP_DEADLINE.as_millis() as u64)
    .observe("evidence_scope", "one_active_single_hop_forward_happy_path");
    if let Ok(metrics) = cancellation {
        cancellation_scenario = cancellation_scenario
            .observe("cleanup_ms", metrics.cleanup_ms as u64)
            .observe("listener_closed", metrics.listener_closed);
    }
    scenarios.push(cancellation_scenario);

    let destination_failure =
        verify_destination_failure_cleanup(&config, &config.known_correct, Arc::clone(&key)).await;
    scenarios.push(
        Scenario::new(
            "TN-03",
            if destination_failure.is_ok() {
                Status::Unsupported
            } else {
                Status::Fail
            },
            if destination_failure.is_ok() {
                "destination_failure_cleanup_only"
            } else {
                destination_failure
                    .err()
                    .map_or("failure_cleanup_regression", CandidateError::category)
            },
            0,
        )
        .observe("failed_destination_port", 1_u64)
        .observe(
            "destination_failure_cleanup_passed",
            destination_failure.is_ok(),
        )
        .observe(
            "not_exercised",
            "all_auth_trust_jump_phase_failures_and_post_cleanup_resource_counts",
        ),
    );

    scenarios.push(
        hostile_scenario("MI-01", HostileMode::OversizedBanner, &config)
            .await
            .observe("bytes_sent", HOSTILE_BANNER_BYTES as u64),
    );
    scenarios.push(hostile_scenario("MI-02", HostileMode::OversizedPacket, &config).await);
    scenarios.push(hostile_scenario("MI-03", HostileMode::PartialBanner, &config).await);

    scenarios.push(
        Scenario::new(
            "SC-01",
            Status::Unsupported,
            "requires_outer_runner_completion",
            0,
        )
        .observe("password_auth_compiled_but_not_exposed_by_probe", true)
        .observe("runtime_logger_initialized", false)
        .observe("release_debug_trace_compile_out_required", true)
        .observe(
            "compiled_static_max_level",
            log::STATIC_MAX_LEVEL.to_string(),
        )
        .observe("external_canary_scan_required", true)
        .observe("candidate_process_alone_can_assert_pass", false),
    );

    let repetition_started = Instant::now();
    let repetition = verify_repetition(&config, &config.known_correct, Arc::clone(&key)).await;
    let repetition_passed = repetition.as_ref().is_ok_and(|metrics| {
        metrics.fd_delta <= REPETITION_FD_DELTA_LIMIT
            && metrics.rss_delta_kib <= REPETITION_RSS_DELTA_LIMIT_KIB
    });
    let mut repetition_scenario = Scenario::new(
        "LC-01",
        if repetition_passed {
            Status::Pass
        } else {
            Status::Fail
        },
        repetition
            .as_ref()
            .err()
            .copied()
            .map_or("repetition", CandidateError::category),
        repetition_started.elapsed().as_millis(),
    )
    .observe("fd_delta_limit", REPETITION_FD_DELTA_LIMIT)
    .observe("rss_delta_limit_kib", REPETITION_RSS_DELTA_LIMIT_KIB);
    if let Ok(metrics) = repetition {
        repetition_scenario = repetition_scenario
            .observe("cycles", metrics.cycles as u64)
            .observe("fd_delta", metrics.fd_delta)
            .observe("rss_delta_kib", metrics.rss_delta_kib);
    }
    scenarios.push(repetition_scenario);

    scenarios.push(
        Scenario::new("DP-01", Status::Unsupported, "external_dependency_gate", 0)
            .observe("runtime_claim", false)
            .observe(
                "evaluated_by",
                "cargo_audit_cargo_deny_primary_source_report",
            ),
    );

    let summary = Summary::from_scenarios(&scenarios);
    Ok(Evidence {
        schema_version: 2,
        evidence_kind: "disposable_local_ssh_candidate",
        candidate: Candidate {
            name: "russh",
            version: "0.62.4",
            crypto_provider: "aws-lc-rs",
            enabled_optional_features: vec!["aws-lc-rs"],
            compression_enabled: false,
            rsa_enabled: false,
            credential_memory_contract: "private-key bytes zeroized by probe; password mode disabled; upstream session cleanup still under evaluation",
        },
        bounds: Bounds {
            handshake_deadline_ms: HANDSHAKE_DEADLINE.as_millis() as u64,
            cleanup_deadline_ms: CLEANUP_DEADLINE.as_millis() as u64,
            channel_window_bytes: CHANNEL_WINDOW_BYTES,
            maximum_packet_bytes: MAXIMUM_PACKET_BYTES,
            channel_message_capacity: CHANNEL_MESSAGE_CAPACITY,
            agent_frame_bytes: MAX_AGENT_FRAME_BYTES,
            agent_identity_count: MAX_AGENT_IDENTITIES,
            trust_store_bytes: MAX_TRUST_STORE_BYTES,
            trust_store_lines: MAX_TRUST_STORE_LINES,
            trust_store_line_bytes: MAX_TRUST_STORE_LINE_BYTES,
            password_input_bytes: 0,
            hostile_banner_bytes_sent: HOSTILE_BANNER_BYTES,
            repetition_cycles: REPETITION_CYCLES,
        },
        scenarios,
        summary,
    })
}

async fn trust_scenario(
    id: &'static str,
    config: &ProbeConfig,
    known_hosts: &std::path::Path,
    key: Arc<russh::keys::ssh_key::PrivateKey>,
    expected_outcome: TrustOutcome,
    expected_error: Option<CandidateError>,
) -> Scenario {
    let started = Instant::now();
    let probe = probe_trust(config, known_hosts, key).await;
    let result_matches = match expected_error {
        Some(error) => probe.result == Err(error),
        None => probe.result.is_ok(),
    };
    let passed = result_matches
        && probe.observation.outcome == expected_outcome
        && probe.observation.fingerprint_is_sha256;
    Scenario::new(
        id,
        if passed { Status::Pass } else { Status::Fail },
        if passed {
            "host_trust"
        } else {
            probe
                .result
                .err()
                .map_or("host_trust_regression", CandidateError::category)
        },
        started.elapsed().as_millis(),
    )
    .observe("expected_outcome", trust_outcome_name(expected_outcome))
    .observe(
        "observed_outcome",
        trust_outcome_name(probe.observation.outcome),
    )
    .observe(
        "fingerprint_observation_is_sha256",
        probe.observation.fingerprint_is_sha256,
    )
}

async fn hostile_scenario(id: &'static str, mode: HostileMode, config: &ProbeConfig) -> Scenario {
    let rss_before = resident_kib().await;
    let result = run_hostile_case(mode, &config.known_empty).await;
    let rss_after = resident_kib().await;
    let rss_delta = match (rss_before, rss_after) {
        (Ok(before), Ok(after)) => after as i64 - before as i64,
        _ => i64::MAX,
    };
    let passed = result
        .as_ref()
        .is_ok_and(|value| value.rejected && rss_delta <= HOSTILE_RSS_DELTA_LIMIT_KIB);
    let mut scenario = Scenario::new(
        id,
        if passed { Status::Pass } else { Status::Fail },
        result
            .as_ref()
            .map(|value| value.category)
            .unwrap_or_else(|error| error.category()),
        result.as_ref().map_or(0, |value| value.elapsed_ms),
    )
    .observe(
        "rejected",
        result.as_ref().is_ok_and(|value| value.rejected),
    )
    .observe("rss_delta_kib", rss_delta)
    .observe("rss_delta_limit_kib", HOSTILE_RSS_DELTA_LIMIT_KIB);
    if let Ok(value) = result {
        scenario = scenario.observe("terminal_category", value.category);
    }
    scenario
}

fn first_error_category(
    first: &Result<(), CandidateError>,
    second: &Result<(), CandidateError>,
) -> &'static str {
    first
        .as_ref()
        .err()
        .or_else(|| second.as_ref().err())
        .copied()
        .map_or("agent_regression", CandidateError::category)
}

fn trust_outcome_name(outcome: TrustOutcome) -> &'static str {
    match outcome {
        TrustOutcome::NotObserved => "not_observed",
        TrustOutcome::Matched => "matched",
        TrustOutcome::Unknown => "unknown",
        TrustOutcome::Changed => "changed",
        TrustOutcome::Revoked => "revoked",
        TrustOutcome::StoreFailure => "store_failure",
    }
}

fn snapshots_differ(
    before: &Result<Vec<u8>, CandidateError>,
    after: &Result<Vec<u8>, CandidateError>,
) -> bool {
    match (before, after) {
        (Ok(before), Ok(after)) => before != after,
        _ => true,
    }
}
