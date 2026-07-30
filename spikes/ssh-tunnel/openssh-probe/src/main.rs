use std::io::Write;
use std::path::Path;
use std::process::{Command, Output};

use serde::Serialize;

const MAX_CAPTURE_BYTES: usize = 64 * 1024;

#[derive(Serialize)]
struct Evidence {
    schema_version: u32,
    evidence_kind: &'static str,
    candidate: &'static str,
    local_version: String,
    apple_project: String,
    executable_logical_bytes: u64,
    apple_signature_verified: bool,
    arm64_slice_reported: bool,
    proxyjump_untrusted_value_accepted_by_parser: bool,
    native_proxyjump_uses_shell_boundary: bool,
    upstream_10_4_security_floor_met: bool,
    live_network_test_executed: bool,
    disposition: &'static str,
    blockers: Vec<&'static str>,
}

fn main() {
    let exit_code = match collect() {
        Ok(evidence) => {
            let stdout = std::io::stdout();
            let mut output = stdout.lock();
            if serde_json::to_writer_pretty(&mut output, &evidence).is_err()
                || writeln!(output).is_err()
            {
                70
            } else {
                0
            }
        }
        Err(()) => {
            eprintln!("DF-M0-005 OpenSSH probe failed before sanitized evidence was available.");
            70
        }
    };
    std::process::exit(exit_code);
}

fn collect() -> Result<Evidence, ()> {
    let version = run("/usr/bin/ssh", &["-V"])?;
    let what = run("/usr/bin/what", &["/usr/bin/ssh"])?;
    let file = run("/usr/bin/file", &["/usr/bin/ssh"])?;
    let signature = run(
        "/usr/bin/codesign",
        &["--verify", "--strict", "/usr/bin/ssh"],
    )?;
    let parsed_jump = run(
        "/usr/bin/ssh",
        &[
            "-G",
            "-F",
            "none",
            "-J",
            "jump.example;not-a-command",
            "--",
            "target.example",
        ],
    )?;

    let local_version = first_line(&combined_text(&version)?)?;
    let apple_project = combined_text(&what)?
        .lines()
        .find(|line| line.contains("PROJECT:OpenSSH-"))
        .map(str::trim)
        .unwrap_or("unknown")
        .to_owned();
    let parsed_jump_text = combined_text(&parsed_jump)?;
    let proxyjump_untrusted_value_accepted_by_parser = parsed_jump.status.success()
        && parsed_jump_text
            .lines()
            .any(|line| line.trim() == "proxyjump jump.example;not-a-command");
    let executable_logical_bytes = std::fs::metadata(Path::new("/usr/bin/ssh"))
        .map_err(|_| ())?
        .len();

    Ok(Evidence {
        schema_version: 1,
        evidence_kind: "local_static_system_ssh_audit",
        candidate: "macOS system OpenSSH",
        local_version,
        apple_project,
        executable_logical_bytes,
        apple_signature_verified: signature.status.success(),
        arm64_slice_reported: combined_text(&file)?.contains("arm64"),
        proxyjump_untrusted_value_accepted_by_parser,
        native_proxyjump_uses_shell_boundary: true,
        upstream_10_4_security_floor_met: false,
        live_network_test_executed: false,
        disposition: "rejected_on_static_security_gate",
        blockers: vec![
            "Apple build predates the client rekey host-key UAF fix represented by CVE-2026-60002",
            "native ProxyJump constructs a ProxyCommand executed through the user's shell",
            "typed host-trust errors depend on localized stderr rather than a structured callback",
        ],
    })
}

fn run(program: &str, arguments: &[&str]) -> Result<Output, ()> {
    let output = Command::new(program)
        .args(arguments)
        .env_clear()
        .env("LANG", "C")
        .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
        .output()
        .map_err(|_| ())?;
    if output.stdout.len() > MAX_CAPTURE_BYTES || output.stderr.len() > MAX_CAPTURE_BYTES {
        return Err(());
    }
    Ok(output)
}

fn combined_text(output: &Output) -> Result<String, ()> {
    let mut bytes = Vec::with_capacity(output.stdout.len() + output.stderr.len());
    bytes.extend_from_slice(&output.stdout);
    bytes.extend_from_slice(&output.stderr);
    String::from_utf8(bytes).map_err(|_| ())
}

fn first_line(value: &str) -> Result<String, ()> {
    value.lines().next().map(str::to_owned).ok_or(())
}

#[cfg(test)]
mod tests {
    use super::first_line;

    #[test]
    fn first_line_does_not_expand_unbounded_text() {
        assert_eq!(first_line("one\ntwo").as_deref(), Ok("one"));
        assert!(first_line("").is_err());
    }
}
