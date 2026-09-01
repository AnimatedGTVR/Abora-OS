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

    let status = Command::new("/usr/bin/env")
        .arg("bash")
        .arg(script)
        .args(passthrough)
        .status()
        .map_err(|err| format!("failed to launch {}: {err}", script.display()))?;

    Ok(status.code().unwrap_or(1).min(u8::MAX as i32) as u8)
}
