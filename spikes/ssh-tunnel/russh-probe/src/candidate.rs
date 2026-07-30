use std::borrow::Cow;
use std::io::Read;
use std::net::SocketAddr;
use std::path::Path;
use std::process::Command;
use std::sync::Arc;
use std::time::{Duration, Instant};

use russh::client::{self, AuthResult};
use russh::keys::agent::AgentIdentity;
use russh::keys::agent::client::AgentClient;
use russh::keys::key::PrivateKeyWithHashAlg;
use russh::keys::ssh_key::{Algorithm, PrivateKey};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UnixStream};
use tokio::sync::oneshot;
use tokio::time::timeout;
use zeroize::Zeroizing;

use crate::config::ProbeConfig;
use crate::trust::{TrustHandler, TrustObservation, TrustOutcome, snapshot};

pub const HANDSHAKE_DEADLINE: Duration = Duration::from_secs(5);
pub const CLEANUP_DEADLINE: Duration = Duration::from_secs(2);
pub const CHANNEL_WINDOW_BYTES: u32 = 256 * 1024;
pub const MAXIMUM_PACKET_BYTES: u32 = 32 * 1024;
pub const CHANNEL_MESSAGE_CAPACITY: usize = 8;
pub const MAX_AGENT_FRAME_BYTES: usize = 256 * 1024;
pub const MAX_AGENT_IDENTITIES: usize = 64;
pub const MAX_PRIVATE_KEY_BYTES: usize = 64 * 1024;
pub const MAX_TRUST_STORE_BYTES: usize = 64 * 1024;
pub const MAX_TRUST_STORE_LINES: usize = 256;
pub const MAX_TRUST_STORE_LINE_BYTES: usize = 4 * 1024;
pub const REPETITION_CYCLES: usize = 25;

pub type SessionHandle = client::Handle<TrustHandler>;

pub struct ConnectedSession {
    pub handle: SessionHandle,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CandidateError {
    Agent,
    AgentBounds,
    AuthenticationRejected,
    Cleanup,
    InsecureKeyPermissions,
    InvalidKey,
    Io,
    Protocol,
    Ssh,
    Timeout,
    TrustChanged,
    TrustRevoked,
    TrustStore,
    TrustUnknown,
}

#[derive(Clone, Copy, Debug)]
pub struct RepetitionMetrics {
    pub cycles: usize,
    pub fd_delta: i64,
    pub rss_delta_kib: i64,
}

#[derive(Clone, Copy, Debug)]
pub struct CancellationMetrics {
    pub cleanup_ms: u128,
    pub listener_closed: bool,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct AttemptCounters {
    pub jump: usize,
    pub direct: usize,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransportPolicy {
    DirectAllowed,
    TunnelRequired,
}

pub struct TrustProbe {
    pub result: Result<(), CandidateError>,
    pub observation: TrustObservation,
}

impl CandidateError {
    pub fn category(self) -> &'static str {
        match self {
            Self::Agent => "agent",
            Self::AgentBounds => "agent_bounds",
            Self::AuthenticationRejected => "authentication",
            Self::Cleanup => "cleanup",
            Self::InsecureKeyPermissions => "key_permissions",
            Self::InvalidKey => "key_format",
            Self::Io => "io",
            Self::Protocol => "protocol",
            Self::Ssh => "ssh",
            Self::Timeout => "timeout",
            Self::TrustChanged => "trust_changed",
            Self::TrustRevoked => "trust_revoked",
            Self::TrustStore => "trust_store",
            Self::TrustUnknown => "trust_unknown",
        }
    }
}

pub async fn load_private_key(path: &Path) -> Result<Arc<PrivateKey>, CandidateError> {
    let path = path.to_path_buf();
    tokio::task::spawn_blocking(move || {
        use std::fs::OpenOptions;
        use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};

        let mut file = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NOFOLLOW)
            .open(path)
            .map_err(|_| CandidateError::InsecureKeyPermissions)?;
        let metadata = file
            .metadata()
            .map_err(|_| CandidateError::InsecureKeyPermissions)?;
        // SAFETY: `geteuid` has no pointer arguments and only reads process credentials.
        let effective_uid = unsafe { libc::geteuid() };
        if !metadata.file_type().is_file()
            || metadata.permissions().mode() & 0o077 != 0
            || metadata.uid() != effective_uid
        {
            return Err(CandidateError::InsecureKeyPermissions);
        }
        if metadata.len() > MAX_PRIVATE_KEY_BYTES as u64 {
            return Err(CandidateError::InvalidKey);
        }

        let mut encoded = Zeroizing::new(Vec::with_capacity(metadata.len() as usize));
        file.by_ref()
            .take(MAX_PRIVATE_KEY_BYTES as u64 + 1)
            .read_to_end(&mut encoded)
            .map_err(|_| CandidateError::Io)?;
        if encoded.len() > MAX_PRIVATE_KEY_BYTES {
            return Err(CandidateError::InvalidKey);
        }
        let encoded =
            std::str::from_utf8(encoded.as_slice()).map_err(|_| CandidateError::InvalidKey)?;
        let key = russh::keys::decode_secret_key(encoded, None)
            .map_err(|_| CandidateError::InvalidKey)?;
        Ok(Arc::new(key))
    })
    .await
    .map_err(|_| CandidateError::Io)?
}

pub async fn connect_key(
    config: &ProbeConfig,
    known_hosts: &Path,
    key: Arc<PrivateKey>,
) -> Result<ConnectedSession, CandidateError> {
    let mut session = start_direct(
        config.bastion_address,
        &config.bastion_host,
        config.bastion_address.port(),
        known_hosts,
    )
    .await?;
    authenticate_key(&mut session.handle, &config.username, key).await?;
    Ok(session)
}

pub async fn probe_trust(
    config: &ProbeConfig,
    known_hosts: &Path,
    key: Arc<PrivateKey>,
) -> TrustProbe {
    let handler = match load_trust_handler(
        &config.bastion_host,
        config.bastion_address.port(),
        known_hosts,
    )
    .await
    {
        Ok(handler) => handler,
        Err(error) => {
            return TrustProbe {
                result: Err(error),
                observation: TrustObservation {
                    outcome: TrustOutcome::StoreFailure,
                    fingerprint_is_sha256: false,
                },
            };
        }
    };
    let observation_handle = handler.observation_handle();
    let connect_result = timeout(
        HANDSHAKE_DEADLINE,
        client::connect(client_config(), config.bastion_address, handler),
    )
    .await;

    let result = match connect_result {
        Err(_) => Err(CandidateError::Timeout),
        Ok(Err(_)) => match snapshot(&observation_handle) {
            Ok(value) => Err(map_trust_outcome(value.outcome)),
            Err(()) => Err(CandidateError::TrustStore),
        },
        Ok(Ok(mut handle)) => {
            let authentication = authenticate_key(&mut handle, &config.username, key).await;
            let trust = snapshot(&observation_handle)
                .map_err(|_| CandidateError::TrustStore)
                .and_then(|value| {
                    if value.outcome == TrustOutcome::Matched {
                        Ok(value)
                    } else {
                        Err(map_trust_outcome(value.outcome))
                    }
                });
            let session = trust.map(|_| ConnectedSession { handle });
            match (authentication, session) {
                (Err(error), Ok(session)) => {
                    let _ = close_session(session).await;
                    Err(error)
                }
                (Ok(()), Ok(session)) => close_session(session).await,
                (_, Err(error)) => Err(error),
            }
        }
    };

    let observation = snapshot(&observation_handle).unwrap_or(TrustObservation {
        outcome: TrustOutcome::StoreFailure,
        fingerprint_is_sha256: false,
    });
    TrustProbe {
        result,
        observation,
    }
}

pub async fn connect_agent(
    config: &ProbeConfig,
    known_hosts: &Path,
) -> Result<ConnectedSession, CandidateError> {
    let mut session = start_direct(
        config.bastion_address,
        &config.bastion_host,
        config.bastion_address.port(),
        known_hosts,
    )
    .await?;
    let stream = timeout(
        HANDSHAKE_DEADLINE,
        UnixStream::connect(&config.agent_socket),
    )
    .await
    .map_err(|_| CandidateError::Timeout)?
    .map_err(|_| CandidateError::Agent)?;
    let mut agent = AgentClient::connect(stream);
    let identities = timeout(HANDSHAKE_DEADLINE, agent.request_identities())
        .await
        .map_err(|_| CandidateError::Timeout)?
        .map_err(|_| CandidateError::Agent)?;
    if identities.is_empty() || identities.len() > MAX_AGENT_IDENTITIES {
        return Err(CandidateError::AgentBounds);
    }

    let identity = identities
        .first()
        .ok_or(CandidateError::AgentBounds)?
        .clone();
    authenticate_agent_identity(&mut session.handle, &config.username, identity, &mut agent)
        .await?;
    Ok(session)
}

pub async fn close_session(session: ConnectedSession) -> Result<(), CandidateError> {
    session
        .handle
        .disconnect(russh::Disconnect::ByApplication, "", "")
        .await
        .map_err(|_| CandidateError::Cleanup)?;
    match timeout(CLEANUP_DEADLINE, session.handle).await {
        Ok(Ok(())) => Ok(()),
        Ok(Err(russh::Error::Disconnect)) => Ok(()),
        Ok(Err(_)) | Err(_) => Err(CandidateError::Cleanup),
    }
}

pub async fn verify_jump(
    config: &ProbeConfig,
    known_hosts: &Path,
    key: Arc<PrivateKey>,
) -> Result<(), CandidateError> {
    let bastion = connect_key(config, known_hosts, Arc::clone(&key)).await?;
    let channel = match timeout(
        HANDSHAKE_DEADLINE,
        bastion.handle.channel_open_direct_tcpip(
            config.target_host.clone(),
            u32::from(config.target_port),
            "127.0.0.1",
            0,
        ),
    )
    .await
    {
        Ok(Ok(channel)) => channel,
        Ok(Err(_)) => {
            let _ = close_session(bastion).await;
            return Err(CandidateError::Ssh);
        }
        Err(_) => {
            let _ = close_session(bastion).await;
            return Err(CandidateError::Timeout);
        }
    };

    let mut target = match start_stream(
        channel.into_stream(),
        &config.target_host,
        config.target_port,
        known_hosts,
    )
    .await
    {
        Ok(target) => target,
        Err(error) => {
            let _ = close_session(bastion).await;
            return Err(error);
        }
    };

    if let Err(error) = authenticate_key(&mut target.handle, &config.username, key).await {
        let _ = close_session(target).await;
        let _ = close_session(bastion).await;
        return Err(error);
    }

    let target_close = close_session(target).await;
    let bastion_close = close_session(bastion).await;
    target_close.and(bastion_close)
}

pub async fn verify_forward_banner(
    config: &ProbeConfig,
    known_hosts: &Path,
    key: Arc<PrivateKey>,
) -> Result<(), CandidateError> {
    let session = connect_key(config, known_hosts, key).await?;
    let channel = timeout(
        HANDSHAKE_DEADLINE,
        session.handle.channel_open_direct_tcpip(
            config.target_host.clone(),
            u32::from(config.target_port),
            "127.0.0.1",
            0,
        ),
    )
    .await
    .map_err(|_| CandidateError::Timeout)?
    .map_err(|_| CandidateError::Ssh)?;
    let mut stream = channel.into_stream();
    let mut banner = [0_u8; 64];
    let bytes_read = timeout(HANDSHAKE_DEADLINE, stream.read(&mut banner))
        .await
        .map_err(|_| CandidateError::Timeout)?
        .map_err(|_| CandidateError::Io)?;
    let banner_matches = banner
        .get(..bytes_read)
        .is_some_and(|bytes| bytes.starts_with(b"SSH-2.0-"));
    let _ = stream.shutdown().await;
    let close = close_session(session).await;
    if banner_matches {
        close
    } else {
        Err(CandidateError::Protocol)
    }
}

pub async fn verify_forward_cancellation(
    config: &ProbeConfig,
    known_hosts: &Path,
    key: Arc<PrivateKey>,
) -> Result<CancellationMetrics, CandidateError> {
    let session = connect_key(config, known_hosts, key).await?;
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .map_err(|_| CandidateError::Io)?;
    let listener_address = listener.local_addr().map_err(|_| CandidateError::Io)?;
    let target_host = config.target_host.clone();
    let target_port = config.target_port;
    let (cancel_tx, cancel_rx) = oneshot::channel::<()>();

    let forward_task = tokio::spawn(async move {
        run_one_connection_forward(session, listener, target_host, target_port, cancel_rx).await
    });

    let mut local = timeout(HANDSHAKE_DEADLINE, TcpStream::connect(listener_address))
        .await
        .map_err(|_| CandidateError::Timeout)?
        .map_err(|_| CandidateError::Io)?;
    let mut banner = [0_u8; 64];
    let bytes_read = timeout(HANDSHAKE_DEADLINE, local.read(&mut banner))
        .await
        .map_err(|_| CandidateError::Timeout)?
        .map_err(|_| CandidateError::Io)?;
    if !banner
        .get(..bytes_read)
        .is_some_and(|bytes| bytes.starts_with(b"SSH-2.0-"))
    {
        return Err(CandidateError::Protocol);
    }

    let cleanup_started = Instant::now();
    cancel_tx.send(()).map_err(|_| CandidateError::Cleanup)?;
    drop(local);
    let forward_result = timeout(CLEANUP_DEADLINE, forward_task)
        .await
        .map_err(|_| CandidateError::Cleanup)?
        .map_err(|_| CandidateError::Cleanup)?;
    forward_result?;
    let cleanup_ms = cleanup_started.elapsed().as_millis();
    let listener_closed = TcpStream::connect(listener_address).await.is_err();
    if !listener_closed || cleanup_started.elapsed() > CLEANUP_DEADLINE {
        return Err(CandidateError::Cleanup);
    }

    Ok(CancellationMetrics {
        cleanup_ms,
        listener_closed,
    })
}

pub async fn verify_destination_failure_cleanup(
    config: &ProbeConfig,
    known_hosts: &Path,
    key: Arc<PrivateKey>,
) -> Result<(), CandidateError> {
    let session = connect_key(config, known_hosts, key).await?;
    let open_result = timeout(
        HANDSHAKE_DEADLINE,
        session
            .handle
            .channel_open_direct_tcpip(config.target_host.clone(), 1, "127.0.0.1", 0),
    )
    .await;
    let failed_as_expected = matches!(open_result, Ok(Err(_)));
    let close_result = close_session(session).await;
    if failed_as_expected {
        close_result
    } else {
        Err(CandidateError::Protocol)
    }
}

pub async fn verify_oversized_agent_frame() -> Result<(), CandidateError> {
    let root =
        std::env::temp_dir().join(format!("dataforge-ssh-agent-probe-{}", std::process::id()));
    tokio::fs::create_dir(&root)
        .await
        .map_err(|_| CandidateError::Io)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        tokio::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700))
            .await
            .map_err(|_| CandidateError::Io)?;
    }
    let socket_path = root.join("agent.sock");
    let listener = tokio::net::UnixListener::bind(&socket_path).map_err(|_| CandidateError::Io)?;
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.map_err(|_| CandidateError::Io)?;
        let mut request = [0_u8; 5];
        stream
            .read_exact(&mut request)
            .await
            .map_err(|_| CandidateError::Io)?;
        let oversized = (MAX_AGENT_FRAME_BYTES as u32 + 1).to_be_bytes();
        stream
            .write_all(&oversized)
            .await
            .map_err(|_| CandidateError::Io)?;
        Ok::<(), CandidateError>(())
    });

    let stream = UnixStream::connect(&socket_path)
        .await
        .map_err(|_| CandidateError::Agent)?;
    let mut client = AgentClient::connect(stream);
    let result = timeout(HANDSHAKE_DEADLINE, client.request_identities()).await;
    let rejected = matches!(result, Ok(Err(_)));
    let server_result = timeout(CLEANUP_DEADLINE, server)
        .await
        .map_err(|_| CandidateError::Cleanup)?
        .map_err(|_| CandidateError::Cleanup)?;
    let _ = tokio::fs::remove_file(&socket_path).await;
    let _ = tokio::fs::remove_dir(&root).await;
    server_result?;
    if rejected {
        Ok(())
    } else {
        Err(CandidateError::AgentBounds)
    }
}

pub async fn verify_repetition(
    config: &ProbeConfig,
    known_hosts: &Path,
    key: Arc<PrivateKey>,
) -> Result<RepetitionMetrics, CandidateError> {
    let fd_before = file_descriptor_count().await?;
    let rss_before = resident_kib().await?;
    for _ in 0..REPETITION_CYCLES {
        let session = connect_key(config, known_hosts, Arc::clone(&key)).await?;
        close_session(session).await?;
    }
    tokio::time::sleep(Duration::from_millis(100)).await;
    let fd_after = file_descriptor_count().await?;
    let rss_after = resident_kib().await?;
    Ok(RepetitionMetrics {
        cycles: REPETITION_CYCLES,
        fd_delta: fd_after as i64 - fd_before as i64,
        rss_delta_kib: rss_after as i64 - rss_before as i64,
    })
}

pub fn execute_connection_plan(
    policy: TransportPolicy,
    jump_succeeds: bool,
    direct_succeeds: bool,
) -> (Result<(), CandidateError>, AttemptCounters) {
    let mut counters = AttemptCounters::default();
    let result = match policy {
        TransportPolicy::TunnelRequired => {
            counters.jump += 1;
            if jump_succeeds {
                Ok(())
            } else {
                Err(CandidateError::Ssh)
            }
        }
        TransportPolicy::DirectAllowed => {
            counters.direct += 1;
            if direct_succeeds {
                Ok(())
            } else {
                Err(CandidateError::Io)
            }
        }
    };
    (result, counters)
}

pub async fn attempt_untrusted_handshake(
    address: SocketAddr,
    known_hosts: &Path,
) -> Result<(), CandidateError> {
    let session = start_direct(address, "127.0.0.1", address.port(), known_hosts).await?;
    close_session(session).await
}

pub async fn trust_store_snapshot(path: &Path) -> Result<Vec<u8>, CandidateError> {
    let metadata = tokio::fs::metadata(path)
        .await
        .map_err(|_| CandidateError::TrustStore)?;
    if metadata.len() > MAX_TRUST_STORE_BYTES as u64 {
        return Err(CandidateError::TrustStore);
    }
    let bytes = tokio::fs::read(path)
        .await
        .map_err(|_| CandidateError::TrustStore)?;
    if !valid_trust_store_bytes(&bytes) {
        return Err(CandidateError::TrustStore);
    }
    Ok(bytes)
}

async fn start_direct(
    address: SocketAddr,
    trust_host: &str,
    trust_port: u16,
    known_hosts: &Path,
) -> Result<ConnectedSession, CandidateError> {
    let handler = load_trust_handler(trust_host, trust_port, known_hosts).await?;
    let observation = handler.observation_handle();
    let result = timeout(
        HANDSHAKE_DEADLINE,
        client::connect(client_config(), address, handler),
    )
    .await
    .map_err(|_| CandidateError::Timeout)?;
    finish_connect(result, &observation)
}

async fn start_stream<R>(
    stream: R,
    trust_host: &str,
    trust_port: u16,
    known_hosts: &Path,
) -> Result<ConnectedSession, CandidateError>
where
    R: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let handler = load_trust_handler(trust_host, trust_port, known_hosts).await?;
    let observation = handler.observation_handle();
    let result = timeout(
        HANDSHAKE_DEADLINE,
        client::connect_stream(client_config(), stream, handler),
    )
    .await
    .map_err(|_| CandidateError::Timeout)?;
    finish_connect(result, &observation)
}

async fn load_trust_handler(
    host: &str,
    port: u16,
    known_hosts: &Path,
) -> Result<TrustHandler, CandidateError> {
    let bytes = trust_store_snapshot(known_hosts).await?;
    TrustHandler::from_snapshot(host, port, &bytes).map_err(|_| CandidateError::TrustStore)
}

fn finish_connect(
    result: Result<SessionHandle, russh::Error>,
    observation: &Arc<std::sync::Mutex<TrustObservation>>,
) -> Result<ConnectedSession, CandidateError> {
    let trust = snapshot(observation).map_err(|_| CandidateError::TrustStore)?;
    match result {
        Ok(handle) if trust.outcome == TrustOutcome::Matched => Ok(ConnectedSession { handle }),
        Ok(_) => Err(map_trust_outcome(trust.outcome)),
        Err(_) if trust.outcome != TrustOutcome::NotObserved => {
            Err(map_trust_outcome(trust.outcome))
        }
        Err(_) => Err(CandidateError::Ssh),
    }
}

fn client_config() -> Arc<client::Config> {
    let preferred = russh::Preferred {
        key: Cow::Owned(vec![Algorithm::Ed25519]),
        ..russh::Preferred::default()
    };
    Arc::new(client::Config {
        window_size: CHANNEL_WINDOW_BYTES,
        maximum_packet_size: MAXIMUM_PACKET_BYTES,
        channel_buffer_size: CHANNEL_MESSAGE_CAPACITY,
        inactivity_timeout: Some(HANDSHAKE_DEADLINE),
        keepalive_interval: Some(Duration::from_secs(2)),
        keepalive_max: 1,
        nodelay: true,
        preferred,
        ..client::Config::default()
    })
}

async fn authenticate_key(
    handle: &mut SessionHandle,
    username: &str,
    key: Arc<PrivateKey>,
) -> Result<(), CandidateError> {
    let result = timeout(
        HANDSHAKE_DEADLINE,
        handle.authenticate_publickey(username, PrivateKeyWithHashAlg::new(key, None)),
    )
    .await
    .map_err(|_| CandidateError::Timeout)?
    .map_err(|_| CandidateError::Ssh)?;
    require_auth_success(result)
}

async fn authenticate_agent_identity(
    handle: &mut SessionHandle,
    username: &str,
    identity: AgentIdentity,
    agent: &mut AgentClient<UnixStream>,
) -> Result<(), CandidateError> {
    let public_key = identity.public_key().into_owned();
    let result = timeout(
        HANDSHAKE_DEADLINE,
        handle.authenticate_publickey_with(username, public_key, None, agent),
    )
    .await
    .map_err(|_| CandidateError::Timeout)?
    .map_err(|_| CandidateError::Agent)?;
    require_auth_success(result)
}

fn require_auth_success(result: AuthResult) -> Result<(), CandidateError> {
    if result.success() {
        Ok(())
    } else {
        Err(CandidateError::AuthenticationRejected)
    }
}

fn map_trust_outcome(outcome: TrustOutcome) -> CandidateError {
    match outcome {
        TrustOutcome::Unknown => CandidateError::TrustUnknown,
        TrustOutcome::Changed => CandidateError::TrustChanged,
        TrustOutcome::Revoked => CandidateError::TrustRevoked,
        TrustOutcome::StoreFailure | TrustOutcome::NotObserved => CandidateError::TrustStore,
        TrustOutcome::Matched => CandidateError::Ssh,
    }
}

async fn run_one_connection_forward(
    session: ConnectedSession,
    listener: TcpListener,
    target_host: String,
    target_port: u16,
    mut cancel: oneshot::Receiver<()>,
) -> Result<(), CandidateError> {
    let (mut local, origin) = tokio::select! {
        accepted = listener.accept() => accepted.map_err(|_| CandidateError::Io)?,
        _ = &mut cancel => {
            return close_session(session).await;
        }
    };
    let channel = timeout(
        HANDSHAKE_DEADLINE,
        session.handle.channel_open_direct_tcpip(
            target_host,
            u32::from(target_port),
            origin.ip().to_string(),
            u32::from(origin.port()),
        ),
    )
    .await
    .map_err(|_| CandidateError::Timeout)?
    .map_err(|_| CandidateError::Ssh)?;
    let mut remote = channel.into_stream();
    tokio::select! {
        result = tokio::io::copy_bidirectional(&mut local, &mut remote) => {
            result.map_err(|_| CandidateError::Io)?;
        }
        _ = &mut cancel => {}
    }
    drop(local);
    drop(remote);
    drop(listener);
    close_session(session).await
}

async fn file_descriptor_count() -> Result<usize, CandidateError> {
    tokio::task::spawn_blocking(|| {
        std::fs::read_dir("/dev/fd")
            .map_err(|_| CandidateError::Io)?
            .try_fold(0_usize, |count, entry| {
                entry.map(|_| count + 1).map_err(|_| CandidateError::Io)
            })
    })
    .await
    .map_err(|_| CandidateError::Io)?
}

pub async fn resident_kib() -> Result<usize, CandidateError> {
    tokio::task::spawn_blocking(|| {
        let pid = std::process::id().to_string();
        let output = Command::new("/bin/ps")
            .args(["-o", "rss=", "-p", &pid])
            .output()
            .map_err(|_| CandidateError::Io)?;
        if !output.status.success() || output.stdout.len() > 64 {
            return Err(CandidateError::Io);
        }
        let value = std::str::from_utf8(&output.stdout)
            .map_err(|_| CandidateError::Io)?
            .trim()
            .parse::<usize>()
            .map_err(|_| CandidateError::Io)?;
        Ok(value)
    })
    .await
    .map_err(|_| CandidateError::Io)?
}

fn valid_trust_store_bytes(bytes: &[u8]) -> bool {
    if bytes.len() > MAX_TRUST_STORE_BYTES || bytes.contains(&0) {
        return false;
    }
    let mut line_count = 0_usize;
    for line in bytes.split(|byte| *byte == b'\n') {
        if line.len() > MAX_TRUST_STORE_LINE_BYTES {
            return false;
        }
        line_count += 1;
        if line_count > MAX_TRUST_STORE_LINES {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::{
        CandidateError, MAX_TRUST_STORE_LINE_BYTES, MAX_TRUST_STORE_LINES, TransportPolicy,
        execute_connection_plan, valid_trust_store_bytes,
    };

    #[test]
    fn failed_jump_plan_has_no_direct_attempt() {
        let (result, counters) =
            execute_connection_plan(TransportPolicy::TunnelRequired, false, true);
        assert_eq!(result, Err(CandidateError::Ssh));
        assert_eq!(counters.jump, 1);
        assert_eq!(counters.direct, 0);
    }

    #[test]
    fn explicit_direct_policy_never_attempts_jump() {
        let (result, counters) =
            execute_connection_plan(TransportPolicy::DirectAllowed, false, true);
        assert_eq!(result, Ok(()));
        assert_eq!(counters.jump, 0);
        assert_eq!(counters.direct, 1);
    }

    #[test]
    fn errors_expose_only_stable_categories() {
        assert_eq!(CandidateError::TrustChanged.category(), "trust_changed");
        assert_eq!(CandidateError::AgentBounds.category(), "agent_bounds");
    }

    #[test]
    fn trust_store_bounds_reject_oversized_lines_and_line_counts() {
        assert!(valid_trust_store_bytes(b"host ssh-ed25519 key\n"));
        assert!(!valid_trust_store_bytes(&vec![
            b'a';
            MAX_TRUST_STORE_LINE_BYTES
                + 1
        ]));
        assert!(!valid_trust_store_bytes(
            vec![b'\n'; MAX_TRUST_STORE_LINES + 1].as_slice()
        ));
    }
}
