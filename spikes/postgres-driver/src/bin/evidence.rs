#![deny(unsafe_code)]

use dataforge_postgres_spike::{
    ConnectionOptions, ErrorCategory, FixtureConfig, MAX_CELL_BYTES, MAX_CHUNK_BYTES,
    MAX_CHUNK_ROWS, ManagedSession, SafeError, SpikeResult, build_tls_config, classify_connect,
    classify_postgres,
};
use futures_util::TryStreamExt;
use serde_json::{Value, json};
use std::env;
use std::ffi::OsString;
use std::io::{self, Write};
use std::net::{IpAddr, Ipv4Addr};
use std::path::Path;
use std::process::{Command, Output};
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::time::{sleep, timeout};
use tokio_postgres::config::SslMode;
use tokio_postgres::types::ToSql;
use tokio_postgres::{Config, NoTls};
use tokio_postgres_rustls::MakeRustlsConnect;

const ADAPTER: &str = "postgresql";
const INTERNAL_GUARD_PROBE_ARGUMENT: &str = "--internal-guard-probe";
const CLIENT_CERTIFICATE_USER: &str = "dataforge_test_client";
const WRONG_PASSWORD_CANARY: &[u8] = b"DF_TEST_SECRET_DO_NOT_LOG_m0_pg_wrong_password";
const FAKE_SERVER_USER: &str = "dataforge_test_fake_server";
const FAKE_SERVER_DATABASE: &str = "dataforge_test_fake_protocol";
const FAKE_STARTUP_MAX_BYTES: usize = 16 * 1024;
const FAKE_ADVERTISED_FRAME_BYTES: usize = 8 * 1024 * 1024;
const CHILD_OUTPUT_MAX_BYTES: usize = 16 * 1024;
const MILLION_ROWS: i64 = 1_000_000;
const SLOW_CONSUMER_DELAY: Duration = Duration::from_millis(1);

#[tokio::main(flavor = "multi_thread", worker_threads = 4)]
async fn main() {
    let result = match guard_probe_argument() {
        Ok(Some(probe)) => run_internal_guard_probe(probe).await,
        Ok(None) => run_evidence().await,
        Err(error) => Err(error),
    };

    if let Err(error) = result {
        let sink = EventSink::without_fixture_secret();
        if sink.error(&error).is_err() {
            eprintln!("DF-M0-002 failed; structured output was unavailable");
        }
        std::process::exit(1);
    }
}

async fn run_evidence() -> SpikeResult<()> {
    let fixture = FixtureConfig::from_environment()?;
    fixture.validate_fixture_paths().await?;
    let sink = EventSink::with_fixture_secret(fixture.owner_password());
    sink.pass(
        "fixture_guard_and_paths",
        json!({
            "configuration": "fail_closed",
            "fixture_paths": "contained_and_bounded",
            "private_key_permissions": "owner_only"
        }),
    )?;

    run_negative_guard_probes(&fixture, &sink).await?;
    run_password_tls_matrix(&fixture, &sink).await?;
    run_mutual_tls_matrix(&fixture, &sink).await?;
    run_stream_matrix(&fixture, &sink).await?;
    run_cancellation_matrix(&fixture, &sink).await?;
    run_transaction_matrix(&fixture, &sink).await?;
    run_fake_wire_matrix(&sink).await?;

    sink.limitation(
        "driver_request_queue",
        json!({
            "candidate": "tokio-postgres-0.7.18",
            "request_queue_bound": "none",
            "disposition": "requires_bounded_adapter_admission_or_candidate_rejection"
        }),
    )?;
    sink.limitation(
        "driver_logging_surface",
        json!({
            "debug_query_and_parameter_logging": "present_in_upstream_source",
            "connection_notice_logging": "present_in_upstream_source",
            "required_control": "disable_or_redact_tokio_postgres_targets_before_production",
            "disposition": "production_logging_policy_gate"
        }),
    )?;
    sink.limitation(
        "driver_credential_memory_copies",
        json!({
            "config_password_copy": "not_zeroized_by_upstream",
            "scram_state_copy": "not_zeroized_by_upstream",
            "spike_owned_copy": "zeroized_on_drop",
            "disposition": "residual_process_memory_risk_requires_review"
        }),
    )?;
    sink.pass(
        "structured_output_redaction",
        json!({
            "schema": "allowlisted",
            "fixture_secret_scan": "passed",
            "connection_string_scan": "passed",
            "raw_server_diagnostics": "excluded"
        }),
    )?;
    sink.pass(
        "df_m0_002_runtime_matrix",
        json!({
            "scope": "disposable_postgresql_only",
            "production_capability_claim": false,
            "known_blocking_limitations": 3
        }),
    )
}

fn guard_probe_argument() -> SpikeResult<Option<&'static str>> {
    let arguments = env::args_os().skip(1).collect::<Vec<_>>();
    match arguments.as_slice() {
        [] => Ok(None),
        [flag, probe] if flag == INTERNAL_GUARD_PROBE_ARGUMENT => match probe.to_str() {
            Some("missing_destructive_opt_in") => Ok(Some("missing_destructive_opt_in")),
            Some("non_localhost_target") => Ok(Some("non_localhost_target")),
            Some("fixture_path_escape") => Ok(Some("fixture_path_escape")),
            _ => Err(harness_error(
                "guard_probe",
                ErrorCategory::Configuration,
                "An internal guard probe was not recognized.",
            )),
        },
        _ => Err(harness_error(
            "harness_arguments",
            ErrorCategory::Configuration,
            "The evidence harness does not accept external arguments.",
        )),
    }
}

async fn run_internal_guard_probe(probe: &'static str) -> SpikeResult<()> {
    let rejected = match probe {
        "missing_destructive_opt_in" | "non_localhost_target" => {
            FixtureConfig::from_environment().err()
        }
        "fixture_path_escape" => match FixtureConfig::from_environment() {
            Ok(fixture) => fixture.validate_fixture_paths().await.err(),
            Err(error) => Some(error),
        },
        _ => {
            return Err(harness_error(
                "guard_probe",
                ErrorCategory::Configuration,
                "An internal guard probe was not recognized.",
            ));
        }
    };

    let error = rejected.ok_or_else(|| {
        harness_error(
            "guard_probe",
            ErrorCategory::Internal,
            "A deliberately invalid disposable target was accepted.",
        )
    })?;
    require(
        error.category == ErrorCategory::Configuration,
        "guard_probe",
        ErrorCategory::Internal,
        "An invalid disposable target produced the wrong error category.",
    )?;
    EventSink::without_fixture_secret().pass(
        "internal_guard_probe",
        json!({"probe": probe, "rejected": true}),
    )
}

async fn run_negative_guard_probes(
    fixture: &FixtureConfig,
    sink: &EventSink<'_>,
) -> SpikeResult<()> {
    for probe in [
        "missing_destructive_opt_in",
        "non_localhost_target",
        "fixture_path_escape",
    ] {
        let output = run_guard_probe_process(probe).await?;
        require(
            output.status.success(),
            "guard_probe",
            ErrorCategory::Internal,
            "A negative disposable-target guard probe did not reject safely.",
        )?;
        require(
            output.stdout.len() <= CHILD_OUTPUT_MAX_BYTES
                && output.stderr.len() <= CHILD_OUTPUT_MAX_BYTES,
            "guard_probe",
            ErrorCategory::LimitExceeded,
            "A guard probe emitted more diagnostic output than allowed.",
        )?;
        scan_bytes_for_secrets(&output.stdout, Some(fixture.owner_password()))?;
        scan_bytes_for_secrets(&output.stderr, Some(fixture.owner_password()))?;
    }

    sink.pass(
        "negative_fixture_guards",
        json!({
            "missing_destructive_opt_in": "rejected",
            "non_localhost_target": "rejected",
            "fixture_path_escape": "rejected"
        }),
    )
}

async fn run_guard_probe_process(probe: &'static str) -> SpikeResult<Output> {
    let executable = env::current_exe().map_err(|_| {
        harness_error(
            "guard_probe",
            ErrorCategory::Configuration,
            "The current evidence executable could not be located.",
        )
    })?;
    let probe_name = OsString::from(probe);
    tokio::task::spawn_blocking(move || {
        let mut command = Command::new(executable);
        command.arg(INTERNAL_GUARD_PROBE_ARGUMENT).arg(probe_name);
        match probe {
            "missing_destructive_opt_in" => {
                command.env_remove("DATAFORGE_TEST_ALLOW_DESTRUCTIVE");
            }
            "non_localhost_target" => {
                command.env("DATAFORGE_TEST_HOST", "not-localhost.invalid");
            }
            "fixture_path_escape" => {
                command.env("DATAFORGE_TEST_CA_CERT", "/dev/null");
            }
            _ => {
                return Err(harness_error(
                    "guard_probe",
                    ErrorCategory::Internal,
                    "An internal guard probe was not recognized.",
                ));
            }
        }
        command.output().map_err(|_| {
            harness_error(
                "guard_probe",
                ErrorCategory::Internal,
                "A disposable-target guard probe could not be started.",
            )
        })
    })
    .await
    .map_err(|_| {
        harness_error(
            "guard_probe",
            ErrorCategory::Internal,
            "A disposable-target guard probe task failed.",
        )
    })?
}

async fn run_password_tls_matrix(fixture: &FixtureConfig, sink: &EventSink<'_>) -> SpikeResult<()> {
    let valid = connect_session(
        fixture,
        fixture.host(),
        fixture.owner_user(),
        Some(fixture.owner_password()),
        fixture.ca_certificate(),
        None,
        true,
    )
    .await?;
    fixture.verify_server_guard(valid.client()?).await?;
    verify_typed_scalar_query(valid.client()?).await?;
    valid.shutdown().await?;
    sink.pass(
        "password_tls_custom_ca_channel_binding",
        json!({
            "tls": "required",
            "custom_ca": "verified",
            "hostname": "verified",
            "channel_binding": "required",
            "typed_decode": "passed"
        }),
    )?;

    expect_connection_failure(
        fixture,
        ConnectionOptions {
            hostname: fixture.host(),
            user: fixture.owner_user(),
            password: Some(WRONG_PASSWORD_CANARY),
            ca_path: fixture.ca_certificate(),
            client_identity: None,
            require_channel_binding: true,
        },
        &[ErrorCategory::Authentication],
        "password_tls_wrong_password",
        sink,
    )
    .await?;
    expect_connection_failure(
        fixture,
        ConnectionOptions {
            hostname: fixture.host(),
            user: fixture.owner_user(),
            password: Some(fixture.owner_password()),
            ca_path: fixture.bad_ca_certificate(),
            client_identity: None,
            require_channel_binding: true,
        },
        &[ErrorCategory::Tls],
        "password_tls_untrusted_ca",
        sink,
    )
    .await?;
    expect_connection_failure(
        fixture,
        ConnectionOptions {
            hostname: "127.0.0.1",
            user: fixture.owner_user(),
            password: Some(fixture.owner_password()),
            ca_path: fixture.ca_certificate(),
            client_identity: None,
            require_channel_binding: true,
        },
        &[ErrorCategory::Tls],
        "password_tls_wrong_hostname",
        sink,
    )
    .await
}

async fn run_mutual_tls_matrix(fixture: &FixtureConfig, sink: &EventSink<'_>) -> SpikeResult<()> {
    let valid = connect_session(
        fixture,
        fixture.host(),
        CLIENT_CERTIFICATE_USER,
        None,
        fixture.ca_certificate(),
        Some((fixture.client_certificate(), fixture.client_private_key())),
        false,
    )
    .await?;
    fixture.verify_server_guard(valid.client()?).await?;
    valid.shutdown().await?;
    sink.pass(
        "mutual_tls_valid_client_identity",
        json!({
            "custom_ca": "verified",
            "client_certificate": "verified",
            "hostname": "verified"
        }),
    )?;

    expect_connection_failure(
        fixture,
        ConnectionOptions {
            hostname: fixture.host(),
            user: CLIENT_CERTIFICATE_USER,
            password: None,
            ca_path: fixture.ca_certificate(),
            client_identity: None,
            require_channel_binding: false,
        },
        &[
            ErrorCategory::Authentication,
            ErrorCategory::Network,
            ErrorCategory::Tls,
        ],
        "mutual_tls_missing_client_identity",
        sink,
    )
    .await?;
    expect_connection_failure(
        fixture,
        ConnectionOptions {
            hostname: fixture.host(),
            user: CLIENT_CERTIFICATE_USER,
            password: None,
            ca_path: fixture.ca_certificate(),
            client_identity: Some((
                fixture.wrong_client_certificate(),
                fixture.wrong_client_private_key(),
            )),
            require_channel_binding: false,
        },
        &[
            ErrorCategory::Authentication,
            ErrorCategory::Network,
            ErrorCategory::Tls,
        ],
        "mutual_tls_wrong_client_identity",
        sink,
    )
    .await
}

async fn connect_session(
    fixture: &FixtureConfig,
    hostname: &str,
    user: &str,
    password: Option<&[u8]>,
    ca_path: &Path,
    client_identity: Option<(&Path, &Path)>,
    require_channel_binding: bool,
) -> SpikeResult<ManagedSession> {
    ManagedSession::connect(
        fixture,
        ConnectionOptions {
            hostname,
            user,
            password,
            ca_path,
            client_identity,
            require_channel_binding,
        },
    )
    .await
}

async fn expect_connection_failure(
    fixture: &FixtureConfig,
    options: ConnectionOptions<'_>,
    allowed_categories: &[ErrorCategory],
    case: &'static str,
    sink: &EventSink<'_>,
) -> SpikeResult<()> {
    match ManagedSession::connect(fixture, options).await {
        Ok(session) => {
            session.shutdown().await?;
            Err(harness_error(
                case,
                ErrorCategory::Internal,
                "A connection that must fail was accepted.",
            ))
        }
        Err(error) => {
            require(
                allowed_categories.contains(&error.category),
                case,
                ErrorCategory::Internal,
                "A rejected connection produced an unexpected error category.",
            )?;
            sink.pass(
                case,
                json!({
                    "rejected": true,
                    "category": category_name(error.category),
                    "retryable": error.retryable
                }),
            )
        }
    }
}

async fn verify_typed_scalar_query(client: &tokio_postgres::Client) -> SpikeResult<()> {
    let row = client
        .query_one(
            "SELECT 42::INT4, TRUE::BOOL, 'typed'::TEXT, md5('dataforge')::UUID, '{\"ok\":true}'::JSONB, NULL::TEXT",
            &[],
        )
        .await
        .map_err(|error| classify_postgres("typed_scalar_query", error))?;
    let integer: i32 = row
        .try_get(0)
        .map_err(|error| classify_postgres("typed_scalar_decode", error))?;
    let boolean: bool = row
        .try_get(1)
        .map_err(|error| classify_postgres("typed_scalar_decode", error))?;
    let text: &str = row
        .try_get(2)
        .map_err(|error| classify_postgres("typed_scalar_decode", error))?;
    let identifier: uuid::Uuid = row
        .try_get(3)
        .map_err(|error| classify_postgres("typed_scalar_decode", error))?;
    let document: Value = row
        .try_get(4)
        .map_err(|error| classify_postgres("typed_scalar_decode", error))?;
    let null_text: Option<&str> = row
        .try_get(5)
        .map_err(|error| classify_postgres("typed_scalar_decode", error))?;
    require(
        integer == 42
            && boolean
            && text == "typed"
            && identifier.as_bytes().len() == 16
            && document.get("ok").and_then(Value::as_bool) == Some(true)
            && null_text.is_none(),
        "typed_scalar_decode",
        ErrorCategory::Protocol,
        "PostgreSQL typed values did not round-trip as expected.",
    )
}

async fn run_stream_matrix(fixture: &FixtureConfig, sink: &EventSink<'_>) -> SpikeResult<()> {
    let session = connect_session(
        fixture,
        fixture.host(),
        fixture.owner_user(),
        Some(fixture.owner_password()),
        fixture.ca_certificate(),
        None,
        true,
    )
    .await?;
    fixture.verify_server_guard(session.client()?).await?;

    let started = Instant::now();
    let (stats, digest) = stream_one_million_rows(session.client()?).await?;
    let elapsed = started.elapsed();
    require(
        stats.total_rows == MILLION_ROWS as u64,
        "million_row_stream",
        ErrorCategory::Protocol,
        "The typed row stream ended before its expected row count.",
    )?;
    stats.validate("million_row_stream")?;
    sink.pass(
        "million_row_typed_query_raw_stream",
        json!({
            "rows": stats.total_rows,
            "chunks": stats.chunks,
            "maximum_chunk_rows": stats.maximum_rows,
            "maximum_chunk_bytes": stats.maximum_bytes,
            "row_cap": MAX_CHUNK_ROWS,
            "byte_cap": MAX_CHUNK_BYTES,
            "slow_consumer_delay_milliseconds_per_chunk": SLOW_CONSUMER_DELAY.as_millis(),
            "elapsed_milliseconds": elapsed.as_millis(),
            "digest": digest.to_string()
        }),
    )?;

    let byte_stats = stream_byte_capped_rows(session.client()?).await?;
    byte_stats.validate("byte_capped_stream")?;
    require(
        byte_stats.chunks > 1 && byte_stats.maximum_rows < MAX_CHUNK_ROWS,
        "byte_capped_stream",
        ErrorCategory::LimitExceeded,
        "The byte-oriented stream did not exercise the chunk byte cap.",
    )?;
    sink.pass(
        "stream_byte_cap",
        json!({
            "rows": byte_stats.total_rows,
            "chunks": byte_stats.chunks,
            "maximum_chunk_rows": byte_stats.maximum_rows,
            "maximum_chunk_bytes": byte_stats.maximum_bytes,
            "byte_cap": MAX_CHUNK_BYTES
        }),
    )?;

    verify_oversized_cell_rejection(session.client()?).await?;
    sink.pass(
        "oversized_cell_rejection",
        json!({
            "cell_cap": MAX_CELL_BYTES,
            "tested_size": MAX_CELL_BYTES + 1,
            "result": "rejected_before_chunk_admission"
        }),
    )?;
    session.shutdown().await
}

async fn stream_one_million_rows(
    client: &tokio_postgres::Client,
) -> SpikeResult<(ChunkStats, u64)> {
    let parameters: [&(dyn ToSql + Sync); 1] = [&MILLION_ROWS];
    let stream = client
        .query_raw(
            "SELECT gs::BIGINT, (gs % 2 = 0)::BOOL, (gs % 97)::INT4, gs::DOUBLE PRECISION / 10.0, CASE WHEN gs % 11 = 0 THEN NULL ELSE 'v'::TEXT END FROM generate_series(1, $1::BIGINT) AS gs",
            parameters,
        )
        .await
        .map_err(|error| classify_postgres("million_row_query_raw", error))?;
    futures_util::pin_mut!(stream);

    let mut chunks = ChunkAccumulator::default();
    let mut expected_identifier = 1_i64;
    let mut digest = 0xcbf2_9ce4_8422_2325_u64;
    while let Some(row) = stream
        .try_next()
        .await
        .map_err(|error| classify_postgres("million_row_stream", error))?
    {
        let identifier: i64 = row
            .try_get(0)
            .map_err(|error| classify_postgres("million_row_decode", error))?;
        let even: bool = row
            .try_get(1)
            .map_err(|error| classify_postgres("million_row_decode", error))?;
        let remainder: i32 = row
            .try_get(2)
            .map_err(|error| classify_postgres("million_row_decode", error))?;
        let scaled: f64 = row
            .try_get(3)
            .map_err(|error| classify_postgres("million_row_decode", error))?;
        let optional_text: Option<&str> = row
            .try_get(4)
            .map_err(|error| classify_postgres("million_row_decode", error))?;
        require(
            identifier == expected_identifier
                && even == (identifier % 2 == 0)
                && remainder == (identifier % 97) as i32
                && (scaled - identifier as f64 / 10.0).abs() < f64::EPSILON
                && optional_text.is_none() == (identifier % 11 == 0),
            "million_row_decode",
            ErrorCategory::Protocol,
            "A streamed typed row did not match its deterministic fixture.",
        )?;

        let text_bytes = optional_text.map_or(0, str::len);
        require_cell_limit(text_bytes, "million_row_decode")?;
        let row_bytes = 8_usize
            .checked_add(1)
            .and_then(|value| value.checked_add(4))
            .and_then(|value| value.checked_add(8))
            .and_then(|value| value.checked_add(1))
            .and_then(|value| value.checked_add(text_bytes))
            .ok_or_else(|| limit_error("million_row_decode", "A row size overflowed."))?;
        if chunks.push(row_bytes)? {
            sleep(SLOW_CONSUMER_DELAY).await;
        }
        digest = fnv_mix(digest, identifier as u64);
        digest = fnv_mix(digest, u64::from(even));
        digest = fnv_mix(digest, remainder as u64);
        digest = fnv_mix(digest, optional_text.is_some() as u64);
        expected_identifier = expected_identifier.checked_add(1).ok_or_else(|| {
            limit_error(
                "million_row_decode",
                "The expected row identifier overflowed.",
            )
        })?;
    }
    chunks.finish();
    Ok((chunks.stats, digest))
}

async fn stream_byte_capped_rows(client: &tokio_postgres::Client) -> SpikeResult<ChunkStats> {
    const ROWS: i64 = 30;
    const TEXT_BYTES: i32 = 300_000;
    let parameters: [&(dyn ToSql + Sync); 2] = [&ROWS, &TEXT_BYTES];
    let stream = client
        .query_raw(
            "SELECT gs::BIGINT, repeat('x', $2::INT4)::TEXT FROM generate_series(1, $1::BIGINT) AS gs",
            parameters,
        )
        .await
        .map_err(|error| classify_postgres("byte_capped_query_raw", error))?;
    futures_util::pin_mut!(stream);
    let mut chunks = ChunkAccumulator::default();
    while let Some(row) = stream
        .try_next()
        .await
        .map_err(|error| classify_postgres("byte_capped_stream", error))?
    {
        let _: i64 = row
            .try_get(0)
            .map_err(|error| classify_postgres("byte_capped_decode", error))?;
        let text: &str = row
            .try_get(1)
            .map_err(|error| classify_postgres("byte_capped_decode", error))?;
        require_cell_limit(text.len(), "byte_capped_decode")?;
        let row_bytes = 8_usize
            .checked_add(text.len())
            .ok_or_else(|| limit_error("byte_capped_decode", "A row size overflowed."))?;
        if chunks.push(row_bytes)? {
            sleep(SLOW_CONSUMER_DELAY).await;
        }
    }
    chunks.finish();
    require(
        chunks.stats.total_rows == ROWS as u64,
        "byte_capped_stream",
        ErrorCategory::Protocol,
        "The byte-capped stream ended before its expected row count.",
    )?;
    Ok(chunks.stats)
}

async fn verify_oversized_cell_rejection(client: &tokio_postgres::Client) -> SpikeResult<()> {
    let requested_bytes = i32::try_from(MAX_CELL_BYTES + 1).map_err(|_| {
        limit_error(
            "oversized_cell",
            "The oversized-cell fixture length is invalid.",
        )
    })?;
    let row = client
        .query_one("SELECT repeat('x', $1::INT4)::TEXT", &[&requested_bytes])
        .await
        .map_err(|error| classify_postgres("oversized_cell_query", error))?;
    let value: &str = row
        .try_get(0)
        .map_err(|error| classify_postgres("oversized_cell_decode", error))?;
    require(
        value.len() == MAX_CELL_BYTES + 1,
        "oversized_cell_decode",
        ErrorCategory::Protocol,
        "The oversized-cell fixture returned an unexpected length.",
    )?;
    match require_cell_limit(value.len(), "oversized_cell_admission") {
        Err(error) if error.category == ErrorCategory::LimitExceeded => Ok(()),
        Err(_) => Err(harness_error(
            "oversized_cell_admission",
            ErrorCategory::Internal,
            "The oversized cell produced the wrong error category.",
        )),
        Ok(()) => Err(harness_error(
            "oversized_cell_admission",
            ErrorCategory::Internal,
            "An oversized cell entered a result chunk.",
        )),
    }
}

async fn run_cancellation_matrix(fixture: &FixtureConfig, sink: &EventSink<'_>) -> SpikeResult<()> {
    let session = connect_session(
        fixture,
        fixture.host(),
        fixture.owner_user(),
        Some(fixture.owner_password()),
        fixture.ca_certificate(),
        None,
        true,
    )
    .await?;
    fixture.verify_server_guard(session.client()?).await?;
    let cancel_started = {
        let connector = cancellation_connector(fixture.ca_certificate()).await?;
        let cancel_token = session.client()?.cancel_token();
        let query = session.client()?.query_one("SELECT pg_sleep(30)", &[]);
        tokio::pin!(query);
        if timeout(Duration::from_millis(150), &mut query)
            .await
            .is_ok()
        {
            return Err(harness_error(
                "slow_query_cancellation",
                ErrorCategory::Internal,
                "The slow-query fixture completed before cancellation.",
            ));
        }
        let cancel_started = Instant::now();
        cancel_token
            .cancel_query(connector)
            .await
            .map_err(|error| classify_connect("cancel_request", error))?;
        let cancellation_error = timeout(Duration::from_secs(5), &mut query)
            .await
            .map_err(|_| {
                harness_error(
                    "slow_query_cancellation",
                    ErrorCategory::Timeout,
                    "The cancelled query did not reach a terminal state.",
                )
            })?
            .err()
            .ok_or_else(|| {
                harness_error(
                    "slow_query_cancellation",
                    ErrorCategory::Internal,
                    "The slow query completed successfully after its cancel request.",
                )
            })?;
        let cancellation_error = classify_postgres("slow_query_cancellation", cancellation_error);
        require(
            cancellation_error.category == ErrorCategory::Cancellation,
            "slow_query_cancellation",
            ErrorCategory::Internal,
            "The server did not confirm slow-query cancellation.",
        )?;
        cancel_started
    };
    verify_session_query(session.client()?, "post_cancel_session_query").await?;
    sink.pass(
        "slow_query_cancel_and_session_reuse",
        json!({
            "cancel_outcome": "server_confirmed_query_cancelled",
            "terminal_milliseconds": cancel_started.elapsed().as_millis(),
            "same_session_after_cancel": "usable"
        }),
    )?;

    let race_outcome = {
        let race_connector = cancellation_connector(fixture.ca_certificate()).await?;
        let race_token = session.client()?.cancel_token();
        let race_query = session.client()?.query_one("SELECT 1::INT4", &[]);
        let race_cancel = race_token.cancel_query(race_connector);
        let (query_result, cancel_result) = tokio::join!(race_query, race_cancel);
        cancel_result.map_err(|error| classify_connect("cancel_race_request", error))?;
        match query_result {
            Ok(row) => {
                let value: i32 = row
                    .try_get(0)
                    .map_err(|error| classify_postgres("cancel_race_decode", error))?;
                require(
                    value == 1,
                    "cancel_race_decode",
                    ErrorCategory::Protocol,
                    "The cancellation-race success value was invalid.",
                )?;
                "completed_before_cancel"
            }
            Err(error) => {
                let error = classify_postgres("cancel_race_query", error);
                require(
                    error.category == ErrorCategory::Cancellation,
                    "cancel_race_query",
                    ErrorCategory::Internal,
                    "The cancellation race produced an invalid terminal outcome.",
                )?;
                "server_confirmed_cancelled"
            }
        }
    };
    verify_session_query(session.client()?, "post_cancel_race_session_query").await?;
    sink.pass(
        "cancellation_race",
        json!({
            "allowed_outcome": race_outcome,
            "cancel_request_is_completion_proof": false,
            "same_session_after_race": "usable"
        }),
    )?;
    session.shutdown().await
}

async fn cancellation_connector(ca_path: &Path) -> SpikeResult<MakeRustlsConnect> {
    let tls = build_tls_config(ca_path, None).await?;
    Ok(MakeRustlsConnect::new(tls))
}

async fn verify_session_query(
    client: &tokio_postgres::Client,
    operation: &'static str,
) -> SpikeResult<()> {
    let row = client
        .query_one("SELECT 1::INT4", &[])
        .await
        .map_err(|error| classify_postgres(operation, error))?;
    let value: i32 = row
        .try_get(0)
        .map_err(|error| classify_postgres(operation, error))?;
    require(
        value == 1,
        operation,
        ErrorCategory::Protocol,
        "The post-cancellation session probe returned an invalid value.",
    )
}

async fn run_transaction_matrix(fixture: &FixtureConfig, sink: &EventSink<'_>) -> SpikeResult<()> {
    let mut session = connect_session(
        fixture,
        fixture.host(),
        fixture.owner_user(),
        Some(fixture.owner_password()),
        fixture.ca_certificate(),
        None,
        true,
    )
    .await?;
    fixture.verify_server_guard(session.client()?).await?;

    transaction_commit_success(&mut session, fixture.run_marker()).await?;
    sink.pass(
        "transaction_explicit_commit",
        json!({"write": "committed", "verification": "row_present"}),
    )?;
    transaction_constraint_failure(&mut session, fixture.run_marker()).await?;
    sink.pass(
        "transaction_constraint_failure",
        json!({
            "constraint_error": "typed",
            "transaction_state": "aborted_until_explicit_rollback",
            "verification": "row_absent"
        }),
    )?;
    transaction_explicit_rollback(&mut session, fixture.run_marker()).await?;
    sink.pass(
        "transaction_explicit_rollback",
        json!({"write": "rolled_back", "verification": "row_absent"}),
    )?;
    transaction_cancel_and_rollback(&mut session, fixture, fixture.run_marker()).await?;
    sink.pass(
        "transaction_cancel_and_rollback",
        json!({
            "cancel_outcome": "server_confirmed_query_cancelled",
            "transaction_state": "aborted_until_explicit_rollback",
            "verification": "row_absent"
        }),
    )?;
    session.shutdown().await?;

    transaction_connection_loss_unknown(fixture, sink).await
}

async fn transaction_commit_success(session: &mut ManagedSession, marker: &str) -> SpikeResult<()> {
    const IDENTIFIER: i64 = 10_001;
    let transaction = session
        .client_mut()?
        .transaction()
        .await
        .map_err(|error| classify_postgres("transaction_begin", error))?;
    let affected = transaction
        .execute(
            "INSERT INTO dataforge_transaction_probe (id, run_marker, note) VALUES ($1, $2, $3)",
            &[&IDENTIFIER, &marker, &"commit"],
        )
        .await
        .map_err(|error| classify_postgres("transaction_insert", error))?;
    require(
        affected == 1,
        "transaction_insert",
        ErrorCategory::Transaction,
        "The transaction write affected an unexpected row count.",
    )?;
    transaction
        .commit()
        .await
        .map_err(|error| classify_postgres("transaction_commit", error))?;
    require_probe_count(session.client()?, IDENTIFIER, marker, 1).await
}

async fn transaction_constraint_failure(
    session: &mut ManagedSession,
    marker: &str,
) -> SpikeResult<()> {
    const IDENTIFIER: i64 = 10_002;
    let transaction = session
        .client_mut()?
        .transaction()
        .await
        .map_err(|error| classify_postgres("constraint_transaction_begin", error))?;
    transaction
        .execute(
            "INSERT INTO dataforge_transaction_probe (id, run_marker, note) VALUES ($1, $2, $3)",
            &[&IDENTIFIER, &marker, &"constraint"],
        )
        .await
        .map_err(|error| classify_postgres("constraint_transaction_insert", error))?;
    let duplicate_error = transaction
        .execute(
            "INSERT INTO dataforge_transaction_probe (id, run_marker, note) VALUES ($1, $2, $3)",
            &[&IDENTIFIER, &marker, &"duplicate"],
        )
        .await
        .err()
        .ok_or_else(|| {
            harness_error(
                "constraint_transaction_duplicate",
                ErrorCategory::Internal,
                "A duplicate primary key was accepted.",
            )
        })?;
    let duplicate_error = classify_postgres("constraint_transaction_duplicate", duplicate_error);
    require(
        duplicate_error.category == ErrorCategory::Constraint,
        "constraint_transaction_duplicate",
        ErrorCategory::Internal,
        "A duplicate primary key produced the wrong error category.",
    )?;

    let aborted_error = transaction
        .query_one("SELECT 1::INT4", &[])
        .await
        .err()
        .ok_or_else(|| {
            harness_error(
                "constraint_transaction_aborted",
                ErrorCategory::Internal,
                "A failed PostgreSQL transaction accepted a subsequent query.",
            )
        })?;
    let aborted_error = classify_postgres("constraint_transaction_aborted", aborted_error);
    require(
        aborted_error.category == ErrorCategory::Transaction,
        "constraint_transaction_aborted",
        ErrorCategory::Internal,
        "The aborted transaction produced the wrong error category.",
    )?;
    transaction
        .rollback()
        .await
        .map_err(|error| classify_postgres("constraint_transaction_rollback", error))?;
    require_probe_count(session.client()?, IDENTIFIER, marker, 0).await
}

async fn transaction_explicit_rollback(
    session: &mut ManagedSession,
    marker: &str,
) -> SpikeResult<()> {
    const IDENTIFIER: i64 = 10_003;
    let transaction = session
        .client_mut()?
        .transaction()
        .await
        .map_err(|error| classify_postgres("rollback_transaction_begin", error))?;
    transaction
        .execute(
            "INSERT INTO dataforge_transaction_probe (id, run_marker, note) VALUES ($1, $2, $3)",
            &[&IDENTIFIER, &marker, &"rollback"],
        )
        .await
        .map_err(|error| classify_postgres("rollback_transaction_insert", error))?;
    transaction
        .rollback()
        .await
        .map_err(|error| classify_postgres("transaction_rollback", error))?;
    require_probe_count(session.client()?, IDENTIFIER, marker, 0).await
}

async fn transaction_cancel_and_rollback(
    session: &mut ManagedSession,
    fixture: &FixtureConfig,
    marker: &str,
) -> SpikeResult<()> {
    const IDENTIFIER: i64 = 10_004;
    let connector = cancellation_connector(fixture.ca_certificate()).await?;
    let transaction = session
        .client_mut()?
        .transaction()
        .await
        .map_err(|error| classify_postgres("cancel_transaction_begin", error))?;
    transaction
        .execute(
            "INSERT INTO dataforge_transaction_probe (id, run_marker, note) VALUES ($1, $2, $3)",
            &[&IDENTIFIER, &marker, &"cancel"],
        )
        .await
        .map_err(|error| classify_postgres("cancel_transaction_insert", error))?;
    let cancel_token = transaction.cancel_token();
    {
        let query = transaction.query_one("SELECT pg_sleep(30)", &[]);
        tokio::pin!(query);
        if timeout(Duration::from_millis(150), &mut query)
            .await
            .is_ok()
        {
            return Err(harness_error(
                "cancel_transaction_query",
                ErrorCategory::Internal,
                "The transaction slow-query fixture completed before cancellation.",
            ));
        }
        cancel_token
            .cancel_query(connector)
            .await
            .map_err(|error| classify_connect("cancel_transaction_request", error))?;
        let cancelled = timeout(Duration::from_secs(5), &mut query)
            .await
            .map_err(|_| {
                harness_error(
                    "cancel_transaction_query",
                    ErrorCategory::Timeout,
                    "The cancelled transaction query did not terminate.",
                )
            })?
            .err()
            .ok_or_else(|| {
                harness_error(
                    "cancel_transaction_query",
                    ErrorCategory::Internal,
                    "The transaction query completed successfully after cancellation.",
                )
            })?;
        let cancelled = classify_postgres("cancel_transaction_query", cancelled);
        require(
            cancelled.category == ErrorCategory::Cancellation,
            "cancel_transaction_query",
            ErrorCategory::Internal,
            "The transaction query did not report confirmed cancellation.",
        )?;
    }
    let aborted = transaction
        .query_one("SELECT 1::INT4", &[])
        .await
        .err()
        .ok_or_else(|| {
            harness_error(
                "cancel_transaction_aborted",
                ErrorCategory::Internal,
                "A cancelled PostgreSQL transaction was not aborted.",
            )
        })?;
    let aborted = classify_postgres("cancel_transaction_aborted", aborted);
    require(
        aborted.category == ErrorCategory::Transaction,
        "cancel_transaction_aborted",
        ErrorCategory::Internal,
        "The cancelled transaction produced the wrong aborted-state category.",
    )?;
    transaction
        .rollback()
        .await
        .map_err(|error| classify_postgres("cancel_transaction_rollback", error))?;
    require_probe_count(session.client()?, IDENTIFIER, marker, 0).await
}

async fn transaction_connection_loss_unknown(
    fixture: &FixtureConfig,
    sink: &EventSink<'_>,
) -> SpikeResult<()> {
    const IDENTIFIER: i64 = 10_005;
    let mut target = connect_session(
        fixture,
        fixture.host(),
        fixture.owner_user(),
        Some(fixture.owner_password()),
        fixture.ca_certificate(),
        None,
        true,
    )
    .await?;
    let control = connect_session(
        fixture,
        fixture.host(),
        fixture.owner_user(),
        Some(fixture.owner_password()),
        fixture.ca_certificate(),
        None,
        true,
    )
    .await?;
    fixture.verify_server_guard(target.client()?).await?;
    fixture.verify_server_guard(control.client()?).await?;
    let backend = target
        .client()?
        .query_one("SELECT pg_backend_pid()", &[])
        .await
        .map_err(|error| classify_postgres("lost_transaction_backend", error))?;
    let backend_identifier: i32 = backend
        .try_get(0)
        .map_err(|error| classify_postgres("lost_transaction_backend_decode", error))?;

    let transaction = target
        .client_mut()?
        .transaction()
        .await
        .map_err(|error| classify_postgres("lost_transaction_begin", error))?;
    transaction
        .execute(
            "INSERT INTO dataforge_transaction_probe (id, run_marker, note) VALUES ($1, $2, $3)",
            &[&IDENTIFIER, &fixture.run_marker(), &"lost"],
        )
        .await
        .map_err(|error| classify_postgres("lost_transaction_insert", error))?;
    let termination = control
        .client()?
        .query_one(
            "SELECT pg_terminate_backend($1::INT4)",
            &[&backend_identifier],
        )
        .await
        .map_err(|error| classify_postgres("lost_transaction_terminate", error))?;
    let terminated: bool = termination
        .try_get(0)
        .map_err(|error| classify_postgres("lost_transaction_terminate_decode", error))?;
    require(
        terminated,
        "lost_transaction_terminate",
        ErrorCategory::Database,
        "The disposable backend could not be terminated.",
    )?;
    let lost_error = timeout(
        Duration::from_secs(5),
        transaction.query_one("SELECT 1::INT4", &[]),
    )
    .await
    .map_err(|_| {
        harness_error(
            "lost_transaction_observe",
            ErrorCategory::Timeout,
            "The terminated transaction connection did not report loss.",
        )
    })?
    .err()
    .ok_or_else(|| {
        harness_error(
            "lost_transaction_observe",
            ErrorCategory::Internal,
            "A query succeeded after its transaction backend was terminated.",
        )
    })?;
    let lost_error = classify_postgres("lost_transaction_observe", lost_error);
    require(
        lost_error.category == ErrorCategory::Network,
        "lost_transaction_observe",
        ErrorCategory::Internal,
        "Connection loss produced the wrong client error category.",
    )?;
    drop(transaction);
    let driver_error = target.observe_driver_after_loss().await?;
    require(
        driver_error.category == ErrorCategory::Network,
        "lost_transaction_driver",
        ErrorCategory::Internal,
        "The connection driver did not preserve network-loss evidence.",
    )?;

    require_probe_count(control.client()?, IDENTIFIER, fixture.run_marker(), 0).await?;
    sink.pass(
        "transaction_connection_loss",
        json!({
            "client_transaction_outcome": "unknown_lost",
            "automatic_retry": false,
            "automatic_commit": false,
            "separate_server_observation": "uncommitted_row_absent",
            "server_observation_is_client_certainty": false
        }),
    )?;
    control.shutdown().await
}

async fn require_probe_count(
    client: &tokio_postgres::Client,
    identifier: i64,
    marker: &str,
    expected: i64,
) -> SpikeResult<()> {
    let row = client
        .query_one(
            "SELECT COUNT(*)::BIGINT FROM dataforge_transaction_probe WHERE id = $1 AND run_marker = $2",
            &[&identifier, &marker],
        )
        .await
        .map_err(|error| classify_postgres("transaction_verify", error))?;
    let actual: i64 = row
        .try_get(0)
        .map_err(|error| classify_postgres("transaction_verify_decode", error))?;
    require(
        actual == expected,
        "transaction_verify",
        ErrorCategory::Transaction,
        "The server-side transaction result did not match the expected state.",
    )
}

async fn run_fake_wire_matrix(sink: &EventSink<'_>) -> SpikeResult<()> {
    run_fake_wire_case(b'R', 3, false, "malformed_backend_frame").await?;
    sink.pass(
        "fake_wire_malformed_frame",
        json!({
            "target": "127.0.0.1_ephemeral_only",
            "advertised_length": 3,
            "result": "controlled_connection_error"
        }),
    )?;

    run_fake_wire_case(
        b'R',
        FAKE_ADVERTISED_FRAME_BYTES as u32,
        false,
        "oversized_header_only_backend_frame",
    )
    .await?;
    sink.pass(
        "fake_wire_oversized_header_only",
        json!({
            "target": "127.0.0.1_ephemeral_only",
            "advertised_length_bytes": FAKE_ADVERTISED_FRAME_BYTES,
            "payload_bytes_sent": 0,
            "result": "controlled_connection_error_without_eager_full_frame_allocation",
            "evidence_scope": "header_only_probe_does_not_measure_allocation"
        }),
    )?;

    run_fake_wire_case(
        b'?',
        FAKE_ADVERTISED_FRAME_BYTES as u32,
        true,
        "oversized_streamed_backend_frame",
    )
    .await?;
    sink.limitation(
        "fake_wire_oversized_streamed_frame",
        json!({
            "target": "127.0.0.1_ephemeral_only",
            "advertised_length_bytes": FAKE_ADVERTISED_FRAME_BYTES,
            "payload_bytes_sent": FAKE_ADVERTISED_FRAME_BYTES - 4,
            "probe_memory_risk": "bounded_to_safe_8_mib_full_payload",
            "driver_preallocation_cap": "not_present_before_frame_delivery",
            "application_chunk_cap_prevents_allocation": false,
            "codec_behavior": "full_backend_frame_is_buffered_before_application_admission",
            "disposition": "blocking_malicious_server_allocation_risk"
        }),
    )
}

async fn run_fake_wire_case(
    tag: u8,
    advertised_length: u32,
    send_payload: bool,
    operation: &'static str,
) -> SpikeResult<()> {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0))
        .await
        .map_err(|_| network_error(operation, "The fake wire listener could not start."))?;
    let address = listener
        .local_addr()
        .map_err(|_| network_error(operation, "The fake wire listener address was unavailable."))?;
    require(
        address.ip() == IpAddr::V4(Ipv4Addr::LOCALHOST),
        operation,
        ErrorCategory::Configuration,
        "The fake wire listener was not restricted to IPv4 localhost.",
    )?;
    let server = tokio::spawn(async move {
        let (mut stream, peer) = listener
            .accept()
            .await
            .map_err(|_| network_error(operation, "The fake wire server could not accept."))?;
        if peer.ip() != IpAddr::V4(Ipv4Addr::LOCALHOST) {
            return Err(network_error(
                operation,
                "The fake wire peer was not an IPv4 localhost client.",
            ));
        }
        read_bounded_startup_packet(&mut stream, operation).await?;
        let mut frame = [0_u8; 5];
        frame[0] = tag;
        frame[1..].copy_from_slice(&advertised_length.to_be_bytes());
        stream
            .write_all(&frame)
            .await
            .map_err(|_| network_error(operation, "The fake wire frame could not be sent."))?;
        if send_payload {
            let mut remaining = usize::try_from(advertised_length)
                .map_err(|_| limit_error(operation, "The fake frame length overflowed."))?
                .checked_sub(4)
                .ok_or_else(|| limit_error(operation, "The fake frame length was invalid."))?;
            let zeros = [0_u8; 64 * 1024];
            while remaining > 0 {
                let count = remaining.min(zeros.len());
                stream.write_all(&zeros[..count]).await.map_err(|_| {
                    network_error(operation, "The fake wire payload could not be sent.")
                })?;
                remaining -= count;
            }
        }
        stream
            .shutdown()
            .await
            .map_err(|_| network_error(operation, "The fake wire server could not close."))
    });

    let mut config = Config::new();
    config
        .host("127.0.0.1")
        .port(address.port())
        .user(FAKE_SERVER_USER)
        .dbname(FAKE_SERVER_DATABASE)
        .ssl_mode(SslMode::Disable)
        .connect_timeout(Duration::from_secs(2));
    let client_result = timeout(Duration::from_secs(3), config.connect(NoTls)).await;
    let server_result = timeout(Duration::from_secs(3), server)
        .await
        .map_err(|_| {
            harness_error(
                operation,
                ErrorCategory::Timeout,
                "The fake wire server did not terminate.",
            )
        })?
        .map_err(|_| {
            harness_error(
                operation,
                ErrorCategory::Internal,
                "The fake wire server task failed.",
            )
        })?;
    server_result?;
    match client_result {
        Ok(Err(_)) => Ok(()),
        Err(_) => Err(harness_error(
            operation,
            ErrorCategory::Timeout,
            "The PostgreSQL candidate did not terminate a fake wire connection.",
        )),
        Ok(Ok((client, connection))) => {
            drop(client);
            drop(connection);
            Err(harness_error(
                operation,
                ErrorCategory::Protocol,
                "The PostgreSQL candidate accepted a malformed fake server frame.",
            ))
        }
    }
}

async fn read_bounded_startup_packet(
    stream: &mut TcpStream,
    operation: &'static str,
) -> SpikeResult<()> {
    let mut length_bytes = [0_u8; 4];
    stream
        .read_exact(&mut length_bytes)
        .await
        .map_err(|_| network_error(operation, "The fake server could not read startup length."))?;
    let length = u32::from_be_bytes(length_bytes) as usize;
    if !(8..=FAKE_STARTUP_MAX_BYTES).contains(&length) {
        return Err(limit_error(
            operation,
            "The fake-server startup packet exceeded its safe bound.",
        ));
    }
    let remaining = length.checked_sub(4).ok_or_else(|| {
        limit_error(
            operation,
            "The fake-server startup packet length was invalid.",
        )
    })?;
    let mut startup = vec![0_u8; remaining];
    stream
        .read_exact(&mut startup)
        .await
        .map_err(|_| network_error(operation, "The fake server could not read startup data."))?;
    Ok(())
}

#[derive(Default)]
struct ChunkAccumulator {
    current_rows: usize,
    current_bytes: usize,
    stats: ChunkStats,
}

impl ChunkAccumulator {
    fn push(&mut self, row_bytes: usize) -> SpikeResult<bool> {
        if row_bytes > MAX_CHUNK_BYTES {
            return Err(limit_error(
                "stream_chunk_admission",
                "A row cannot fit within the chunk byte cap.",
            ));
        }
        let next_bytes = self.current_bytes.checked_add(row_bytes).ok_or_else(|| {
            limit_error(
                "stream_chunk_admission",
                "The result chunk byte count overflowed.",
            )
        })?;
        let flushed = if self.current_rows == MAX_CHUNK_ROWS || next_bytes > MAX_CHUNK_BYTES {
            self.flush();
            true
        } else {
            false
        };
        self.current_rows = self.current_rows.checked_add(1).ok_or_else(|| {
            limit_error(
                "stream_chunk_admission",
                "The result chunk row count overflowed.",
            )
        })?;
        self.current_bytes = self.current_bytes.checked_add(row_bytes).ok_or_else(|| {
            limit_error(
                "stream_chunk_admission",
                "The result chunk byte count overflowed.",
            )
        })?;
        self.stats.total_rows = self.stats.total_rows.checked_add(1).ok_or_else(|| {
            limit_error(
                "stream_chunk_admission",
                "The result stream row count overflowed.",
            )
        })?;
        Ok(flushed)
    }

    fn finish(&mut self) {
        self.flush();
    }

    fn flush(&mut self) {
        if self.current_rows == 0 {
            return;
        }
        self.stats.chunks += 1;
        self.stats.maximum_rows = self.stats.maximum_rows.max(self.current_rows);
        self.stats.maximum_bytes = self.stats.maximum_bytes.max(self.current_bytes);
        self.current_rows = 0;
        self.current_bytes = 0;
    }
}

#[derive(Clone, Copy, Default)]
struct ChunkStats {
    total_rows: u64,
    chunks: u64,
    maximum_rows: usize,
    maximum_bytes: usize,
}

impl ChunkStats {
    fn validate(self, operation: &'static str) -> SpikeResult<()> {
        require(
            self.chunks > 0
                && self.maximum_rows <= MAX_CHUNK_ROWS
                && self.maximum_bytes <= MAX_CHUNK_BYTES,
            operation,
            ErrorCategory::LimitExceeded,
            "A result chunk exceeded its row or byte cap.",
        )
    }
}

struct EventSink<'a> {
    fixture_secret: Option<&'a [u8]>,
}

impl<'a> EventSink<'a> {
    fn with_fixture_secret(secret: &'a [u8]) -> Self {
        Self {
            fixture_secret: Some(secret),
        }
    }

    const fn without_fixture_secret() -> Self {
        Self {
            fixture_secret: None,
        }
    }

    fn pass(&self, operation: &'static str, evidence: Value) -> SpikeResult<()> {
        self.emit(json!({
            "event": "evidence_case",
            "operation_id": operation,
            "adapter": ADAPTER,
            "status": "pass",
            "evidence": evidence
        }))
    }

    fn limitation(&self, operation: &'static str, evidence: Value) -> SpikeResult<()> {
        self.emit(json!({
            "event": "evidence_case",
            "operation_id": operation,
            "adapter": ADAPTER,
            "status": "limitation",
            "evidence": evidence
        }))
    }

    fn error(&self, error: &SafeError) -> SpikeResult<()> {
        let sqlstate = error.sqlstate.as_deref().and_then(allowlisted_sqlstate);
        self.emit(json!({
            "event": "evidence_terminal",
            "operation_id": error.operation,
            "adapter": ADAPTER,
            "status": "fail",
            "error": {
                "category": category_name(error.category),
                "retryable": error.retryable,
                "user_safe_message": error.user_message,
                "sqlstate": sqlstate
            }
        }))
    }

    fn emit(&self, event: Value) -> SpikeResult<()> {
        let encoded = serialize_checked_event(&event, self.fixture_secret)?;
        let stdout = io::stdout();
        let mut output = stdout.lock();
        output.write_all(&encoded).map_err(|_| {
            harness_error(
                "structured_output",
                ErrorCategory::Internal,
                "Structured evidence output could not be written.",
            )
        })?;
        output.write_all(b"\n").map_err(|_| {
            harness_error(
                "structured_output",
                ErrorCategory::Internal,
                "Structured evidence output could not be completed.",
            )
        })
    }
}

fn serialize_checked_event(event: &Value, fixture_secret: Option<&[u8]>) -> SpikeResult<Vec<u8>> {
    let encoded = serde_json::to_vec(event).map_err(|_| {
        harness_error(
            "structured_output",
            ErrorCategory::Internal,
            "Structured evidence output could not be encoded.",
        )
    })?;
    scan_bytes_for_secrets(&encoded, fixture_secret)?;
    Ok(encoded)
}

fn scan_bytes_for_secrets(bytes: &[u8], fixture_secret: Option<&[u8]>) -> SpikeResult<()> {
    let leaked = [
        WRONG_PASSWORD_CANARY,
        b"postgresql://".as_slice(),
        b"postgres://".as_slice(),
        b"password=".as_slice(),
        b"BEGIN PRIVATE KEY".as_slice(),
    ]
    .into_iter()
    .any(|needle| contains_bytes(bytes, needle))
        || fixture_secret
            .filter(|secret| !secret.is_empty())
            .is_some_and(|secret| contains_bytes(bytes, secret));
    require(
        !leaked,
        "structured_output_redaction",
        ErrorCategory::Internal,
        "A forbidden secret or connection string reached evidence output.",
    )
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack
            .windows(needle.len())
            .any(|window| window == needle)
}

fn allowlisted_sqlstate(value: &str) -> Option<&str> {
    (value.len() == 5 && value.bytes().all(|byte| byte.is_ascii_alphanumeric())).then_some(value)
}

const fn category_name(category: ErrorCategory) -> &'static str {
    match category {
        ErrorCategory::Configuration => "configuration",
        ErrorCategory::Authentication => "authentication",
        ErrorCategory::Network => "network",
        ErrorCategory::Tls => "tls",
        ErrorCategory::Timeout => "timeout",
        ErrorCategory::Cancellation => "cancellation",
        ErrorCategory::Database => "database",
        ErrorCategory::QuerySyntax => "query_syntax",
        ErrorCategory::Constraint => "constraint",
        ErrorCategory::Transaction => "transaction",
        ErrorCategory::Protocol => "protocol",
        ErrorCategory::LimitExceeded => "limit_exceeded",
        ErrorCategory::Internal => "internal",
    }
}

fn require(
    condition: bool,
    operation: &'static str,
    category: ErrorCategory,
    message: &'static str,
) -> SpikeResult<()> {
    if condition {
        Ok(())
    } else {
        Err(harness_error(operation, category, message))
    }
}

fn require_cell_limit(length: usize, operation: &'static str) -> SpikeResult<()> {
    require(
        length <= MAX_CELL_BYTES,
        operation,
        ErrorCategory::LimitExceeded,
        "A result cell exceeded the inline cell limit.",
    )
}

const fn harness_error(
    operation: &'static str,
    category: ErrorCategory,
    message: &'static str,
) -> SafeError {
    SafeError::new(operation, category, false, message)
}

const fn limit_error(operation: &'static str, message: &'static str) -> SafeError {
    harness_error(operation, ErrorCategory::LimitExceeded, message)
}

const fn network_error(operation: &'static str, message: &'static str) -> SafeError {
    SafeError::new(operation, ErrorCategory::Network, true, message)
}

fn fnv_mix(digest: u64, value: u64) -> u64 {
    (digest ^ value).wrapping_mul(0x0000_0100_0000_01b3)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunk_accumulator_enforces_both_limits() -> SpikeResult<()> {
        let mut accumulator = ChunkAccumulator::default();
        for _ in 0..=MAX_CHUNK_ROWS {
            accumulator.push(1)?;
        }
        accumulator.finish();
        assert_eq!(accumulator.stats.total_rows, (MAX_CHUNK_ROWS + 1) as u64);
        assert_eq!(accumulator.stats.chunks, 2);
        assert_eq!(accumulator.stats.maximum_rows, MAX_CHUNK_ROWS);

        let mut bytes = ChunkAccumulator::default();
        bytes.push(MAX_CHUNK_BYTES - 1)?;
        assert!(bytes.push(2)?);
        bytes.finish();
        assert_eq!(bytes.stats.chunks, 2);
        bytes.stats.validate("chunk_accumulator_test")
    }

    #[test]
    fn structured_event_rejects_fixture_secret_and_connection_url() {
        let secret = b"DF_TEST_SECRET_fixture_only";
        let secret_event = json!({"value": "DF_TEST_SECRET_fixture_only"});
        let url_event = json!({"value": "postgresql://localhost/test"});
        assert!(serialize_checked_event(&secret_event, Some(secret)).is_err());
        assert!(serialize_checked_event(&url_event, Some(secret)).is_err());
        let safe_event = json!({"value": "redacted"});
        assert!(serialize_checked_event(&safe_event, Some(secret)).is_ok());
    }

    #[test]
    fn sqlstate_allowlist_rejects_server_control_characters() {
        assert_eq!(allowlisted_sqlstate("23505"), Some("23505"));
        assert_eq!(allowlisted_sqlstate("57P01"), Some("57P01"));
        assert_eq!(allowlisted_sqlstate("12\n34"), None);
        assert_eq!(allowlisted_sqlstate("too-long"), None);
    }
}
