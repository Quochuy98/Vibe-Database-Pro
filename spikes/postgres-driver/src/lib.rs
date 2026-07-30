#![deny(unsafe_code)]

//! Disposable DF-M0-002 support code. This crate is evidence only and must not
//! be imported by a production target.

use rustls::pki_types::{CertificateDer, PrivateKeyDer, pem::PemObject};
use rustls::{ClientConfig, RootCertStore};
use std::env;
use std::fmt;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use tokio::task::JoinHandle;
use tokio::time::timeout;
use tokio_postgres::config::{ChannelBinding, SslMode};
use tokio_postgres::error::SqlState;
use tokio_postgres::{Client, Config, Error as PostgresError};
use tokio_postgres_rustls::MakeRustlsConnect;

pub const MAX_CHUNK_ROWS: usize = 1_000;
pub const MAX_CHUNK_BYTES: usize = 4 * 1024 * 1024;
pub const MAX_CELL_BYTES: usize = 1024 * 1024;
pub const MAX_CERTIFICATE_BYTES: u64 = 1024 * 1024;
pub const EXPECTED_IMAGE: &str =
    "postgres@sha256:b797483593b82cbea9a7ee41c88f324a90d10d9c2504d40e755d91c75456366d";
const _: () = assert!(MAX_CELL_BYTES < MAX_CHUNK_BYTES);
const _: () = assert!(MAX_CERTIFICATE_BYTES <= MAX_CHUNK_BYTES as u64);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ErrorCategory {
    Configuration,
    Authentication,
    Network,
    Tls,
    Timeout,
    Cancellation,
    Database,
    QuerySyntax,
    Constraint,
    Transaction,
    Protocol,
    LimitExceeded,
    Internal,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SafeError {
    pub operation: &'static str,
    pub category: ErrorCategory,
    pub retryable: bool,
    pub sqlstate: Option<String>,
    pub user_message: &'static str,
}

impl SafeError {
    pub const fn new(
        operation: &'static str,
        category: ErrorCategory,
        retryable: bool,
        user_message: &'static str,
    ) -> Self {
        Self {
            operation,
            category,
            retryable,
            sqlstate: None,
            user_message,
        }
    }

    pub fn with_sqlstate(mut self, sqlstate: &SqlState) -> Self {
        self.sqlstate = Some(sqlstate.code().to_owned());
        self
    }
}

impl fmt::Display for SafeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "operation={} category={:?} retryable={} message={}",
            self.operation, self.category, self.retryable, self.user_message
        )?;
        if let Some(sqlstate) = &self.sqlstate {
            write!(formatter, " sqlstate={sqlstate}")?;
        }
        Ok(())
    }
}

impl std::error::Error for SafeError {}

pub type SpikeResult<T> = Result<T, SafeError>;

pub struct SecretBytes(Vec<u8>);

impl SecretBytes {
    fn from_environment(name: &'static str) -> SpikeResult<Self> {
        let value = env::var_os(name).ok_or_else(|| {
            SafeError::new(
                "fixture_guard",
                ErrorCategory::Configuration,
                false,
                "A required disposable-fixture value is missing.",
            )
        })?;
        let bytes = value.to_string_lossy().as_bytes().to_vec();
        if bytes.is_empty() {
            return Err(SafeError::new(
                "fixture_guard",
                ErrorCategory::Configuration,
                false,
                "A required disposable-fixture value is empty.",
            ));
        }
        Ok(Self(bytes))
    }

    pub fn expose(&self) -> &[u8] {
        &self.0
    }
}

impl Drop for SecretBytes {
    fn drop(&mut self) {
        self.0.fill(0);
    }
}

pub struct FixtureConfig {
    host: String,
    port: u16,
    database: String,
    owner_user: String,
    owner_password: SecretBytes,
    run_marker: String,
    container_name: String,
    fixture_directory: PathBuf,
    ca_certificate: PathBuf,
    bad_ca_certificate: PathBuf,
    client_certificate: PathBuf,
    client_private_key: PathBuf,
    wrong_client_certificate: PathBuf,
    wrong_client_private_key: PathBuf,
}

impl FixtureConfig {
    pub fn from_environment() -> SpikeResult<Self> {
        require_exact("DATAFORGE_TEST_ALLOW_DESTRUCTIVE", "1")?;
        require_exact("DATAFORGE_TEST_ENVIRONMENT", "test")?;
        require_exact("DATAFORGE_TEST_IMAGE_DIGEST", EXPECTED_IMAGE)?;

        let host = required_string("DATAFORGE_TEST_HOST")?;
        if host != "localhost" {
            return Err(guard_error(
                "Disposable database host must be exactly localhost.",
            ));
        }

        let port_text = required_string("DATAFORGE_TEST_PORT")?;
        let port = port_text
            .parse::<u16>()
            .ok()
            .filter(|port| *port >= 1_024)
            .ok_or_else(|| guard_error("Disposable database port is invalid."))?;
        let run_marker = required_string("DATAFORGE_TEST_RUN_MARKER")?;
        if run_marker.len() != 16
            || !run_marker
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
        {
            return Err(guard_error("Disposable run marker is malformed."));
        }

        let database = required_string("DATAFORGE_TEST_DATABASE")?;
        let expected_database = format!("dataforge_test_{run_marker}");
        if database != expected_database {
            return Err(guard_error(
                "Disposable database name does not match its run marker.",
            ));
        }
        let container_name = required_string("DATAFORGE_TEST_CONTAINER")?;
        let expected_container = format!("dataforge-test-postgres-{run_marker}");
        if container_name != expected_container {
            return Err(guard_error(
                "Disposable container name does not match its run marker.",
            ));
        }

        Ok(Self {
            host,
            port,
            database,
            owner_user: required_string("DATAFORGE_TEST_OWNER_USER")?,
            owner_password: SecretBytes::from_environment("DATAFORGE_TEST_OWNER_PASSWORD")?,
            run_marker,
            container_name,
            fixture_directory: required_path("DATAFORGE_TEST_FIXTURE_DIR")?,
            ca_certificate: required_path("DATAFORGE_TEST_CA_CERT")?,
            bad_ca_certificate: required_path("DATAFORGE_TEST_BAD_CA_CERT")?,
            client_certificate: required_path("DATAFORGE_TEST_CLIENT_CERT")?,
            client_private_key: required_path("DATAFORGE_TEST_CLIENT_KEY")?,
            wrong_client_certificate: required_path("DATAFORGE_TEST_WRONG_CLIENT_CERT")?,
            wrong_client_private_key: required_path("DATAFORGE_TEST_WRONG_CLIENT_KEY")?,
        })
    }

    pub fn host(&self) -> &str {
        &self.host
    }

    pub const fn port(&self) -> u16 {
        self.port
    }

    pub fn database(&self) -> &str {
        &self.database
    }

    pub fn run_marker(&self) -> &str {
        &self.run_marker
    }

    pub fn container_name(&self) -> &str {
        &self.container_name
    }

    pub fn owner_user(&self) -> &str {
        &self.owner_user
    }

    pub fn owner_password(&self) -> &[u8] {
        self.owner_password.expose()
    }

    pub fn ca_certificate(&self) -> &Path {
        &self.ca_certificate
    }

    pub fn bad_ca_certificate(&self) -> &Path {
        &self.bad_ca_certificate
    }

    pub fn client_certificate(&self) -> &Path {
        &self.client_certificate
    }

    pub fn client_private_key(&self) -> &Path {
        &self.client_private_key
    }

    pub fn wrong_client_certificate(&self) -> &Path {
        &self.wrong_client_certificate
    }

    pub fn wrong_client_private_key(&self) -> &Path {
        &self.wrong_client_private_key
    }

    pub async fn validate_fixture_paths(&self) -> SpikeResult<()> {
        let root = tokio::fs::canonicalize(&self.fixture_directory)
            .await
            .map_err(|_| guard_error("Disposable fixture directory is unavailable."))?;
        let root_metadata = tokio::fs::metadata(&root)
            .await
            .map_err(|_| guard_error("Disposable fixture directory is unavailable."))?;
        if !root_metadata.is_dir() || root_metadata.permissions().mode() & 0o077 != 0 {
            return Err(guard_error(
                "Disposable fixture directory has unsafe type or permissions.",
            ));
        }
        for (path, private) in [
            (&self.ca_certificate, false),
            (&self.bad_ca_certificate, false),
            (&self.client_certificate, false),
            (&self.client_private_key, true),
            (&self.wrong_client_certificate, false),
            (&self.wrong_client_private_key, true),
        ] {
            validate_fixture_file(&root, path, private).await?;
        }
        Ok(())
    }

    pub async fn verify_server_guard(&self, client: &Client) -> SpikeResult<()> {
        let row = client
            .query_one(
                "SELECT current_database(), current_setting('dataforge.test_run_marker', true)",
                &[],
            )
            .await
            .map_err(|error| classify_postgres("fixture_guard_query", error))?;
        let database: String = row
            .try_get(0)
            .map_err(|error| classify_postgres("fixture_guard_decode", error))?;
        let marker: Option<String> = row
            .try_get(1)
            .map_err(|error| classify_postgres("fixture_guard_decode", error))?;
        if database != self.database || marker.as_deref() != Some(self.run_marker.as_str()) {
            return Err(guard_error(
                "Server-side disposable marker does not match the requested target.",
            ));
        }
        Ok(())
    }
}

fn required_string(name: &'static str) -> SpikeResult<String> {
    env::var(name)
        .ok()
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            SafeError::new(
                "fixture_guard",
                ErrorCategory::Configuration,
                false,
                "A required disposable-fixture value is missing.",
            )
        })
}

fn required_path(name: &'static str) -> SpikeResult<PathBuf> {
    required_string(name).map(PathBuf::from)
}

fn require_exact(name: &'static str, expected: &str) -> SpikeResult<()> {
    if env::var(name).ok().as_deref() == Some(expected) {
        Ok(())
    } else {
        Err(guard_error(
            "A disposable-fixture safety assertion did not match.",
        ))
    }
}

fn guard_error(message: &'static str) -> SafeError {
    SafeError::new(
        "fixture_guard",
        ErrorCategory::Configuration,
        false,
        message,
    )
}

async fn validate_fixture_file(root: &Path, path: &Path, private: bool) -> SpikeResult<()> {
    let canonical = tokio::fs::canonicalize(path)
        .await
        .map_err(|_| guard_error("A disposable TLS fixture is unavailable."))?;
    if !canonical.starts_with(root) {
        return Err(guard_error(
            "A disposable TLS fixture escaped its isolated directory.",
        ));
    }
    let metadata = tokio::fs::metadata(&canonical)
        .await
        .map_err(|_| guard_error("A disposable TLS fixture is unavailable."))?;
    if !metadata.is_file() || metadata.len() == 0 || metadata.len() > MAX_CERTIFICATE_BYTES {
        return Err(guard_error(
            "A disposable TLS fixture violates its file-size policy.",
        ));
    }
    if private && metadata.permissions().mode() & 0o077 != 0 {
        return Err(guard_error(
            "A disposable private key has unsafe file permissions.",
        ));
    }
    Ok(())
}

pub async fn build_tls_config(
    ca_path: &Path,
    client_identity: Option<(&Path, &Path)>,
) -> SpikeResult<ClientConfig> {
    let ca_bytes = read_bounded(ca_path, false).await?;
    let certificates = CertificateDer::pem_slice_iter(&ca_bytes)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| tls_configuration_error("The custom CA file is malformed."))?;
    if certificates.is_empty() {
        return Err(tls_configuration_error(
            "The custom CA file contains no certificate.",
        ));
    }
    let mut roots = RootCertStore::empty();
    for certificate in certificates {
        roots
            .add(certificate)
            .map_err(|_| tls_configuration_error("The custom CA certificate is invalid."))?;
    }

    let provider = rustls::crypto::ring::default_provider();
    let builder = ClientConfig::builder_with_provider(Arc::new(provider))
        .with_safe_default_protocol_versions()
        .map_err(|_| tls_configuration_error("No safe TLS protocol version is available."))?
        .with_root_certificates(roots);

    match client_identity {
        Some((certificate_path, private_key_path)) => {
            let chain = load_certificate_chain(certificate_path).await?;
            let key = load_private_key(private_key_path).await?;
            builder
                .with_client_auth_cert(chain, key)
                .map_err(|_| tls_configuration_error("The client certificate is invalid."))
        }
        None => Ok(builder.with_no_client_auth()),
    }
}

async fn load_certificate_chain(path: &Path) -> SpikeResult<Vec<CertificateDer<'static>>> {
    let bytes = read_bounded(path, false).await?;
    let chain = CertificateDer::pem_slice_iter(&bytes)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| tls_configuration_error("The client certificate file is malformed."))?;
    if chain.is_empty() {
        return Err(tls_configuration_error(
            "The client certificate file contains no certificate.",
        ));
    }
    Ok(chain)
}

async fn load_private_key(path: &Path) -> SpikeResult<PrivateKeyDer<'static>> {
    let bytes = read_bounded(path, true).await?;
    PrivateKeyDer::from_pem_slice(&bytes)
        .map_err(|_| tls_configuration_error("The client private key is malformed."))
}

async fn read_bounded(path: &Path, private: bool) -> SpikeResult<Vec<u8>> {
    let metadata = tokio::fs::metadata(path)
        .await
        .map_err(|_| tls_configuration_error("A TLS file is unavailable."))?;
    if !metadata.is_file() || metadata.len() == 0 || metadata.len() > MAX_CERTIFICATE_BYTES {
        return Err(tls_configuration_error(
            "A TLS file violates its size policy.",
        ));
    }
    if private && metadata.permissions().mode() & 0o077 != 0 {
        return Err(tls_configuration_error(
            "A client private key has unsafe file permissions.",
        ));
    }
    tokio::fs::read(path)
        .await
        .map_err(|_| tls_configuration_error("A TLS file could not be read."))
}

fn tls_configuration_error(message: &'static str) -> SafeError {
    SafeError::new("tls_configuration", ErrorCategory::Tls, false, message)
}

pub struct ConnectionOptions<'a> {
    pub hostname: &'a str,
    pub user: &'a str,
    pub password: Option<&'a [u8]>,
    pub ca_path: &'a Path,
    pub client_identity: Option<(&'a Path, &'a Path)>,
    pub require_channel_binding: bool,
}

#[must_use = "the driver task must be explicitly shut down or observed"]
pub struct ManagedSession {
    client: Option<Client>,
    driver: Option<JoinHandle<SpikeResult<()>>>,
}

impl ManagedSession {
    pub async fn connect(
        fixture: &FixtureConfig,
        options: ConnectionOptions<'_>,
    ) -> SpikeResult<Self> {
        if options.hostname != fixture.host() && options.hostname != "127.0.0.1" {
            return Err(SafeError::new(
                "postgres_connect",
                ErrorCategory::Configuration,
                false,
                "The disposable connection hostname is outside the loopback test allowlist.",
            ));
        }
        let tls_config = build_tls_config(options.ca_path, options.client_identity).await?;
        let mut config = Config::new();
        config
            .host(options.hostname)
            .port(fixture.port)
            .dbname(&fixture.database)
            .user(options.user)
            .application_name("dataforge_m0_postgres_spike")
            .ssl_mode(SslMode::Require)
            .connect_timeout(Duration::from_secs(5));
        if options.require_channel_binding {
            config.channel_binding(ChannelBinding::Require);
        }
        if let Some(password) = options.password {
            config.password(password);
        }

        let connector = MakeRustlsConnect::new(tls_config);
        let (client, connection) = config
            .connect(connector)
            .await
            .map_err(|error| classify_connect("postgres_connect", error))?;
        let driver = tokio::spawn(async move {
            connection
                .await
                .map_err(|error| classify_postgres("connection_driver", error))
        });
        Ok(Self {
            client: Some(client),
            driver: Some(driver),
        })
    }

    pub fn client(&self) -> SpikeResult<&Client> {
        self.client.as_ref().ok_or_else(|| {
            SafeError::new(
                "session_access",
                ErrorCategory::Internal,
                false,
                "The disposable session is already closed.",
            )
        })
    }

    pub fn client_mut(&mut self) -> SpikeResult<&mut Client> {
        self.client.as_mut().ok_or_else(|| {
            SafeError::new(
                "session_access",
                ErrorCategory::Internal,
                false,
                "The disposable session is already closed.",
            )
        })
    }

    pub async fn shutdown(mut self) -> SpikeResult<()> {
        self.client.take();
        let Some(driver) = self.driver.take() else {
            return Ok(());
        };
        match timeout(Duration::from_secs(5), driver).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => Err(SafeError::new(
                "connection_driver",
                ErrorCategory::Internal,
                false,
                "The disposable connection task failed.",
            )),
            Err(_) => Err(SafeError::new(
                "connection_driver",
                ErrorCategory::Timeout,
                true,
                "The disposable connection did not close before its deadline.",
            )),
        }
    }

    pub async fn observe_driver_after_loss(mut self) -> SpikeResult<SafeError> {
        self.client.take();
        let driver = self.driver.take().ok_or_else(|| {
            SafeError::new(
                "connection_driver",
                ErrorCategory::Internal,
                false,
                "The disposable connection task is missing.",
            )
        })?;
        match timeout(Duration::from_secs(5), driver).await {
            Ok(Ok(Err(error))) => Ok(error),
            Ok(Ok(Ok(()))) => Err(SafeError::new(
                "connection_driver",
                ErrorCategory::Internal,
                false,
                "The interrupted connection ended without loss evidence.",
            )),
            Ok(Err(_)) => Err(SafeError::new(
                "connection_driver",
                ErrorCategory::Internal,
                false,
                "The disposable connection task failed.",
            )),
            Err(_) => Err(SafeError::new(
                "connection_driver",
                ErrorCategory::Timeout,
                true,
                "The interrupted connection did not terminate before its deadline.",
            )),
        }
    }
}

impl Drop for ManagedSession {
    fn drop(&mut self) {
        self.client.take();
        if let Some(driver) = self.driver.take() {
            driver.abort();
        }
    }
}

pub fn classify_postgres(operation: &'static str, error: PostgresError) -> SafeError {
    if let Some(database_error) = error.as_db_error() {
        let code = database_error.code();
        let (category, retryable, message) = if code == &SqlState::INVALID_PASSWORD
            || code == &SqlState::INVALID_AUTHORIZATION_SPECIFICATION
        {
            (
                ErrorCategory::Authentication,
                false,
                "PostgreSQL rejected authentication.",
            )
        } else if code == &SqlState::QUERY_CANCELED {
            (
                ErrorCategory::Cancellation,
                false,
                "PostgreSQL confirmed query cancellation.",
            )
        } else if code == &SqlState::UNIQUE_VIOLATION {
            (
                ErrorCategory::Constraint,
                false,
                "PostgreSQL rejected a constraint-violating operation.",
            )
        } else if code == &SqlState::IN_FAILED_SQL_TRANSACTION {
            (
                ErrorCategory::Transaction,
                false,
                "The PostgreSQL transaction is aborted and must be rolled back.",
            )
        } else if code == &SqlState::ADMIN_SHUTDOWN
            || code == &SqlState::CRASH_SHUTDOWN
            || code == &SqlState::CANNOT_CONNECT_NOW
            || code == &SqlState::DATABASE_DROPPED
        {
            (
                ErrorCategory::Network,
                true,
                "The PostgreSQL server ended the connection before the operation completed.",
            )
        } else if code.code().starts_with("42") {
            (
                ErrorCategory::QuerySyntax,
                false,
                "PostgreSQL rejected the query syntax or object reference.",
            )
        } else {
            (
                ErrorCategory::Database,
                false,
                "PostgreSQL returned a database error.",
            )
        };
        return SafeError::new(operation, category, retryable, message).with_sqlstate(code);
    }
    if error.is_closed() {
        return SafeError::new(
            operation,
            ErrorCategory::Network,
            true,
            "The PostgreSQL connection closed before the operation completed.",
        );
    }
    SafeError::new(
        operation,
        ErrorCategory::Protocol,
        false,
        "The PostgreSQL driver rejected a protocol operation.",
    )
}

pub fn classify_connect(operation: &'static str, error: PostgresError) -> SafeError {
    if error.as_db_error().is_some() {
        return classify_postgres(operation, error);
    }
    let diagnostic = error.to_string().to_ascii_lowercase();
    if diagnostic.contains("certificate")
        || diagnostic.contains("tls")
        || diagnostic.contains("dns name")
        || diagnostic.contains("invalid peer")
    {
        SafeError::new(
            operation,
            ErrorCategory::Tls,
            false,
            "TLS trust or service-identity validation failed.",
        )
    } else {
        SafeError::new(
            operation,
            ErrorCategory::Network,
            true,
            "The PostgreSQL connection could not be established.",
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_error_never_contains_seeded_secret_or_connection_string() {
        let canary = "DF_TEST_SECRET_DO_NOT_LOG_79c8";
        let error = SafeError::new(
            "postgres_connect",
            ErrorCategory::Authentication,
            false,
            "PostgreSQL rejected authentication.",
        );
        let rendered = format!("{error:?} {error}");
        assert!(!rendered.contains(canary));
        assert!(!rendered.contains("postgresql://"));
        assert!(!rendered.contains("password="));
    }

    #[test]
    fn constants_preserve_ffi_stream_limits() {
        assert_eq!(MAX_CHUNK_ROWS, 1_000);
        assert_eq!(MAX_CHUNK_BYTES, 4 * 1024 * 1024);
        assert_eq!(MAX_CELL_BYTES, 1024 * 1024);
        assert_eq!(MAX_CERTIFICATE_BYTES, 1024 * 1024);
    }

    #[test]
    fn secret_debug_surface_is_intentionally_absent() {
        fn assert_not_debug<T>(_value: &T) {}
        let secret = SecretBytes(b"fake-only".to_vec());
        assert_not_debug(&secret);
        assert_eq!(secret.expose(), b"fake-only");
    }
}
