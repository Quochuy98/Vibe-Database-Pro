use std::sync::{Arc, Mutex};

use data_encoding::BASE64_MIME;
use hmac::{Hmac, KeyInit, Mac};
use russh::client;
use russh::keys::parse_public_key_base64;
use russh::keys::ssh_key::{HashAlg, PublicKey};
use sha1::Sha1;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TrustOutcome {
    NotObserved,
    Matched,
    Unknown,
    Changed,
    Revoked,
    StoreFailure,
}

#[derive(Clone, Debug)]
pub struct TrustObservation {
    pub outcome: TrustOutcome,
    pub fingerprint_is_sha256: bool,
}

#[derive(Clone)]
pub struct TrustHandler {
    keys: Vec<TrustKey>,
    observation: Arc<Mutex<TrustObservation>>,
}

#[derive(Clone)]
struct TrustKey {
    key: PublicKey,
    revoked: bool,
}

impl TrustHandler {
    pub fn from_snapshot(host: &str, port: u16, bytes: &[u8]) -> Result<Self, ()> {
        let identity = if port == 22 {
            host.to_owned()
        } else {
            format!("[{host}]:{port}")
        };
        let content = std::str::from_utf8(bytes).map_err(|_| ())?;
        let mut keys = Vec::new();

        for raw_line in content.lines() {
            let line = raw_line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let mut fields = line.split_ascii_whitespace();
            let first = fields.next().ok_or(())?;
            let (marker, host_patterns) = if first.starts_with('@') {
                (Some(first), fields.next().ok_or(())?)
            } else {
                (None, first)
            };
            let algorithm = fields.next().ok_or(())?;
            let encoded_key = fields.next().ok_or(())?;

            if !host_patterns_match(&identity, host_patterns)? {
                continue;
            }
            let key = parse_public_key_base64(encoded_key).map_err(|_| ())?;
            if key.algorithm().as_str() != algorithm {
                return Err(());
            }
            let revoked = match marker {
                None => false,
                Some("@revoked") => true,
                Some("@cert-authority") | Some(_) => return Err(()),
            };
            keys.push(TrustKey { key, revoked });
        }

        Ok(Self {
            keys,
            observation: Arc::new(Mutex::new(TrustObservation {
                outcome: TrustOutcome::NotObserved,
                fingerprint_is_sha256: false,
            })),
        })
    }

    pub fn observation_handle(&self) -> Arc<Mutex<TrustObservation>> {
        Arc::clone(&self.observation)
    }

    fn record(&self, key: &PublicKey, outcome: TrustOutcome) {
        if let Ok(mut observation) = self.observation.lock() {
            let fingerprint = key.fingerprint(HashAlg::Sha256).to_string();
            observation.outcome = outcome;
            observation.fingerprint_is_sha256 = fingerprint.starts_with("SHA256:");
        }
    }
}

impl client::Handler for TrustHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &PublicKey,
    ) -> Result<bool, Self::Error> {
        if self
            .keys
            .iter()
            .any(|entry| entry.revoked && entry.key == *server_public_key)
        {
            self.record(server_public_key, TrustOutcome::Revoked);
            return Ok(false);
        }
        if self
            .keys
            .iter()
            .any(|entry| !entry.revoked && entry.key == *server_public_key)
        {
            self.record(server_public_key, TrustOutcome::Matched);
            return Ok(true);
        }
        if self.keys.iter().any(|entry| !entry.revoked) {
            self.record(server_public_key, TrustOutcome::Changed);
        } else {
            self.record(server_public_key, TrustOutcome::Unknown);
        }
        Ok(false)
    }
}

pub fn snapshot(observation: &Arc<Mutex<TrustObservation>>) -> Result<TrustObservation, ()> {
    observation
        .lock()
        .map(|value| value.clone())
        .map_err(|_| ())
}

fn host_patterns_match(identity: &str, patterns: &str) -> Result<bool, ()> {
    if patterns.contains(['*', '?', '!']) {
        return Err(());
    }
    for pattern in patterns.split(',') {
        if pattern.starts_with("|1|") {
            if hashed_host_matches(identity, pattern)? {
                return Ok(true);
            }
        } else if pattern == identity {
            return Ok(true);
        }
    }
    Ok(false)
}

fn hashed_host_matches(identity: &str, pattern: &str) -> Result<bool, ()> {
    let mut fields = pattern.split('|');
    if fields.next() != Some("") || fields.next() != Some("1") {
        return Err(());
    }
    let salt = BASE64_MIME
        .decode(fields.next().ok_or(())?.as_bytes())
        .map_err(|_| ())?;
    let expected = BASE64_MIME
        .decode(fields.next().ok_or(())?.as_bytes())
        .map_err(|_| ())?;
    if fields.next().is_some() {
        return Err(());
    }
    let mut mac = Hmac::<Sha1>::new_from_slice(&salt).map_err(|_| ())?;
    mac.update(identity.as_bytes());
    Ok(mac.verify_slice(&expected).is_ok())
}

#[cfg(test)]
mod tests {
    use super::{hashed_host_matches, host_patterns_match};

    #[test]
    fn exact_and_hashed_hosts_are_scoped() {
        assert_eq!(host_patterns_match("[host]:2200", "[host]:2200"), Ok(true));
        assert_eq!(host_patterns_match("[host]:2201", "[host]:2200"), Ok(false));
        assert_eq!(
            hashed_host_matches(
                "example.com",
                "|1|O33ESRMWPVkMYIwJ1Uw+n877jTo=|nuuC5vEqXlEZ/8BXQR7m619W6Ak=",
            ),
            Ok(true)
        );
    }

    #[test]
    fn wildcard_and_negation_syntax_is_rejected() {
        assert!(host_patterns_match("host", "*.example").is_err());
        assert!(host_patterns_match("host", "!host").is_err());
    }
}
