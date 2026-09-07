use std::ffi::OsString;
use std::path::Path;
use std::process::Command;

pub fn run_legacy(script: &Path, passthrough: &[OsString]) -> Result<u8, String> {
    if !script.exists() {
        return Err(format!(
            "legacy installer script not found: {}",
            script.display()
        ));
    }

    // Spawning through /usr/bin/env made every installer run depend on a path
    // that a minimal Nix-built live image is not obliged to provide; when it
    // was absent nothing ran at all. Resolve bash through PATH instead, and
    // only then fall back to the usual absolute locations.
    let mut last_err = None;
    for bash in bash_candidates() {
        match Command::new(&bash)
            .arg(script)
            .args(passthrough)
            .status()
        {
            Ok(status) => return Ok(status.code().unwrap_or(1).min(u8::MAX as i32) as u8),
            Err(err) => last_err = Some((bash, err)),
        }
    }

    Err(match last_err {
        Some((bash, err)) => format!(
            "failed to launch {} with {}: {err}",
            script.display(),
            bash
        ),
        None => format!("failed to launch {}: no bash found", script.display()),
    })
}

/// `bash` first, so PATH decides; then the locations it is actually installed
/// in when PATH is unhelpful (ABORA_BASH lets a packager pin the store path).
fn bash_candidates() -> Vec<String> {
    let mut candidates = Vec::new();
    if let Some(pinned) = std::env::var_os("ABORA_BASH") {
        candidates.push(pinned.to_string_lossy().into_owned());
    }
    candidates.push("bash".to_string());
    candidates.push("/run/current-system/sw/bin/bash".to_string());
    candidates.push("/bin/bash".to_string());
    candidates.push("/usr/bin/bash".to_string());
    candidates
}
