use std::net::SocketAddr;
use std::path::Path;
use std::time::{Duration, Instant};

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinHandle;
use tokio::time::timeout;

use crate::candidate::{CandidateError, HANDSHAKE_DEADLINE, attempt_untrusted_handshake};

pub const HOSTILE_BANNER_BYTES: usize = 4 * 1024;

#[derive(Clone, Copy, Debug)]
pub enum HostileMode {
    OversizedBanner,
    OversizedPacket,
    PartialBanner,
}

#[derive(Clone, Copy, Debug)]
pub struct HostileResult {
    pub rejected: bool,
    pub elapsed_ms: u128,
    pub category: &'static str,
}

pub async fn run_hostile_case(
    mode: HostileMode,
    known_hosts: &Path,
) -> Result<HostileResult, CandidateError> {
    let (address, server) = spawn_server(mode).await?;
    let started = Instant::now();
    let client_result = match mode {
        HostileMode::PartialBanner => timeout(
            Duration::from_millis(500),
            attempt_untrusted_handshake(address, known_hosts),
        )
        .await
        .map_err(|_| CandidateError::Timeout),
        HostileMode::OversizedBanner | HostileMode::OversizedPacket => {
            Ok(attempt_untrusted_handshake(address, known_hosts).await)
        }
    };
    let elapsed_ms = started.elapsed().as_millis();

    let result = match client_result {
        Ok(Ok(())) => HostileResult {
            rejected: false,
            elapsed_ms,
            category: "unexpected_success",
        },
        Ok(Err(error)) => HostileResult {
            rejected: true,
            elapsed_ms,
            category: error.category(),
        },
        Err(CandidateError::Timeout) => HostileResult {
            rejected: true,
            elapsed_ms,
            category: "timeout",
        },
        Err(error) => HostileResult {
            rejected: true,
            elapsed_ms,
            category: error.category(),
        },
    };

    if !server.is_finished() {
        server.abort();
    }
    let _ = timeout(HANDSHAKE_DEADLINE, server).await;
    Ok(result)
}

async fn spawn_server(
    mode: HostileMode,
) -> Result<(SocketAddr, JoinHandle<Result<(), CandidateError>>), CandidateError> {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .map_err(|_| CandidateError::Io)?;
    let address = listener.local_addr().map_err(|_| CandidateError::Io)?;
    let task = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.map_err(|_| CandidateError::Io)?;
        match mode {
            HostileMode::OversizedBanner => oversized_banner(&mut stream).await,
            HostileMode::OversizedPacket => oversized_packet(&mut stream).await,
            HostileMode::PartialBanner => partial_banner(&mut stream).await,
        }
    });
    Ok((address, task))
}

async fn oversized_banner(stream: &mut TcpStream) -> Result<(), CandidateError> {
    let mut banner = vec![b'A'; HOSTILE_BANNER_BYTES];
    banner.extend_from_slice(b"\r\n");
    stream
        .write_all(&banner)
        .await
        .map_err(|_| CandidateError::Io)?;
    stream.shutdown().await.map_err(|_| CandidateError::Io)
}

async fn oversized_packet(stream: &mut TcpStream) -> Result<(), CandidateError> {
    read_identification(stream).await?;
    stream
        .write_all(b"SSH-2.0-DataForgeHostileFixture\r\n")
        .await
        .map_err(|_| CandidateError::Io)?;
    stream
        .write_all(&u32::MAX.to_be_bytes())
        .await
        .map_err(|_| CandidateError::Io)?;
    stream.flush().await.map_err(|_| CandidateError::Io)?;
    tokio::time::sleep(Duration::from_millis(100)).await;
    Ok(())
}

async fn partial_banner(stream: &mut TcpStream) -> Result<(), CandidateError> {
    stream
        .write_all(b"SSH-2.0-partial")
        .await
        .map_err(|_| CandidateError::Io)?;
    stream.flush().await.map_err(|_| CandidateError::Io)?;
    tokio::time::sleep(HANDSHAKE_DEADLINE + Duration::from_secs(1)).await;
    Ok(())
}

async fn read_identification(stream: &mut TcpStream) -> Result<(), CandidateError> {
    let mut total = 0_usize;
    let mut byte = [0_u8; 1];
    while total < 256 {
        let read = timeout(Duration::from_secs(1), stream.read(&mut byte))
            .await
            .map_err(|_| CandidateError::Timeout)?
            .map_err(|_| CandidateError::Io)?;
        if read == 0 {
            return Err(CandidateError::Protocol);
        }
        total += read;
        if byte[0] == b'\n' {
            return Ok(());
        }
    }
    Err(CandidateError::Protocol)
}
