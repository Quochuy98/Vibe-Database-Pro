use std::collections::BTreeMap;

use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Serialize)]
pub struct Evidence {
    pub schema_version: u32,
    pub evidence_kind: &'static str,
    pub candidate: Candidate,
    pub bounds: Bounds,
    pub scenarios: Vec<Scenario>,
    pub summary: Summary,
}

#[derive(Debug, Serialize)]
pub struct Candidate {
    pub name: &'static str,
    pub version: &'static str,
    pub crypto_provider: &'static str,
    pub enabled_optional_features: Vec<&'static str>,
    pub compression_enabled: bool,
    pub rsa_enabled: bool,
    pub credential_memory_contract: &'static str,
}

#[derive(Debug, Serialize)]
pub struct Bounds {
    pub handshake_deadline_ms: u64,
    pub cleanup_deadline_ms: u64,
    pub channel_window_bytes: u32,
    pub maximum_packet_bytes: u32,
    pub channel_message_capacity: usize,
    pub agent_frame_bytes: usize,
    pub agent_identity_count: usize,
    pub trust_store_bytes: usize,
    pub trust_store_lines: usize,
    pub trust_store_line_bytes: usize,
    pub password_input_bytes: usize,
    pub hostile_banner_bytes_sent: usize,
    pub repetition_cycles: usize,
}

#[derive(Debug, Serialize)]
pub struct Scenario {
    pub id: &'static str,
    pub status: Status,
    pub category: &'static str,
    pub elapsed_ms: u128,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub observations: BTreeMap<String, Value>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Pass,
    Fail,
    Unsupported,
}

#[derive(Debug, Serialize)]
pub struct Summary {
    pub pass: usize,
    pub fail: usize,
    pub unsupported: usize,
    pub runtime_matrix_passed: bool,
}

impl Scenario {
    pub fn new(id: &'static str, status: Status, category: &'static str, elapsed_ms: u128) -> Self {
        Self {
            id,
            status,
            category,
            elapsed_ms,
            observations: BTreeMap::new(),
        }
    }

    pub fn observe(mut self, key: &str, value: impl Into<Value>) -> Self {
        self.observations.insert(key.to_owned(), value.into());
        self
    }

    pub fn fail_if(mut self, condition: bool, category: &'static str) -> Self {
        if condition {
            self.status = Status::Fail;
            self.category = category;
        }
        self
    }
}

impl Summary {
    pub fn from_scenarios(scenarios: &[Scenario]) -> Self {
        let pass = scenarios
            .iter()
            .filter(|scenario| scenario.status == Status::Pass)
            .count();
        let fail = scenarios
            .iter()
            .filter(|scenario| scenario.status == Status::Fail)
            .count();
        let unsupported = scenarios
            .iter()
            .filter(|scenario| scenario.status == Status::Unsupported)
            .count();
        Self {
            pass,
            fail,
            unsupported,
            runtime_matrix_passed: fail == 0,
        }
    }
}
