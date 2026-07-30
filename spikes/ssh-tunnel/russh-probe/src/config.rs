use std::collections::BTreeMap;
use std::env;
use std::net::SocketAddr;
use std::path::PathBuf;

const MAX_HOST_BYTES: usize = 255;
const MAX_USERNAME_BYTES: usize = 64;

#[derive(Clone, Debug)]
pub struct ProbeConfig {
    pub bastion_address: SocketAddr,
    pub bastion_host: String,
    pub target_host: String,
    pub target_port: u16,
    pub username: String,
    pub key_path: PathBuf,
    pub insecure_key_path: PathBuf,
    pub known_correct: PathBuf,
    pub known_empty: PathBuf,
    pub known_hashed: PathBuf,
    pub known_revoked: PathBuf,
    pub known_bastion_mismatch: PathBuf,
    pub known_target_mismatch: PathBuf,
    pub agent_socket: PathBuf,
}

#[derive(Debug)]
pub enum ConfigError {
    InvalidArguments,
    InvalidEndpoint,
    InvalidHost,
    InvalidPort,
    InvalidUsername,
    MissingArgument,
}

impl ProbeConfig {
    pub fn from_process_args() -> Result<Self, ConfigError> {
        let mut values = BTreeMap::new();
        let mut args = env::args().skip(1);

        while let Some(flag) = args.next() {
            if !flag.starts_with("--") || values.contains_key(&flag) {
                return Err(ConfigError::InvalidArguments);
            }
            let value = args.next().ok_or(ConfigError::MissingArgument)?;
            values.insert(flag, value);
        }

        let bastion_address = required(&values, "--bastion-address")?
            .parse::<SocketAddr>()
            .map_err(|_| ConfigError::InvalidEndpoint)?;
        if !bastion_address.ip().is_loopback() {
            return Err(ConfigError::InvalidEndpoint);
        }

        let bastion_host = validated_host(required(&values, "--bastion-host")?)?;
        let target_host = validated_host(required(&values, "--target-host")?)?;
        let target_port = required(&values, "--target-port")?
            .parse::<u16>()
            .map_err(|_| ConfigError::InvalidPort)?;
        if target_port == 0 {
            return Err(ConfigError::InvalidPort);
        }

        let username = required(&values, "--username")?.to_owned();
        if username.is_empty()
            || username.len() > MAX_USERNAME_BYTES
            || username.bytes().any(|byte| byte.is_ascii_control())
        {
            return Err(ConfigError::InvalidUsername);
        }

        let expected_flags = [
            "--agent-socket",
            "--bastion-address",
            "--bastion-host",
            "--insecure-key",
            "--key",
            "--known-bastion-mismatch",
            "--known-correct",
            "--known-empty",
            "--known-hashed",
            "--known-revoked",
            "--known-target-mismatch",
            "--target-host",
            "--target-port",
            "--username",
        ];
        if values
            .keys()
            .any(|flag| !expected_flags.contains(&flag.as_str()))
        {
            return Err(ConfigError::InvalidArguments);
        }

        Ok(Self {
            bastion_address,
            bastion_host,
            target_host,
            target_port,
            username,
            key_path: required_path(&values, "--key")?,
            insecure_key_path: required_path(&values, "--insecure-key")?,
            known_correct: required_path(&values, "--known-correct")?,
            known_empty: required_path(&values, "--known-empty")?,
            known_hashed: required_path(&values, "--known-hashed")?,
            known_revoked: required_path(&values, "--known-revoked")?,
            known_bastion_mismatch: required_path(&values, "--known-bastion-mismatch")?,
            known_target_mismatch: required_path(&values, "--known-target-mismatch")?,
            agent_socket: required_path(&values, "--agent-socket")?,
        })
    }
}

fn required<'a>(values: &'a BTreeMap<String, String>, key: &str) -> Result<&'a str, ConfigError> {
    values
        .get(key)
        .map(String::as_str)
        .ok_or(ConfigError::MissingArgument)
}

fn required_path(values: &BTreeMap<String, String>, key: &str) -> Result<PathBuf, ConfigError> {
    let value = required(values, key)?;
    if value.is_empty() || value.as_bytes().contains(&0) {
        return Err(ConfigError::InvalidArguments);
    }
    Ok(PathBuf::from(value))
}

fn validated_host(value: &str) -> Result<String, ConfigError> {
    if value.is_empty()
        || value.len() > MAX_HOST_BYTES
        || value.bytes().any(|byte| byte.is_ascii_control())
    {
        return Err(ConfigError::InvalidHost);
    }
    Ok(value.to_owned())
}

#[cfg(test)]
mod tests {
    use super::validated_host;

    #[test]
    fn host_validation_rejects_control_characters() {
        assert!(validated_host("safe.test").is_ok());
        assert!(validated_host("bad\n.test").is_err());
        assert!(validated_host("").is_err());
    }
}
