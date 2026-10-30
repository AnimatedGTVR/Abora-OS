use std::path::Path;
use std::process::{Command, Stdio};

/// Every command grab runs goes through this, so the providers can be tested
/// against canned output.
pub trait Runner {
    fn has(&self, program: &str) -> bool;
    /// Runs a query; its stdout, or an error with the last lines of stderr.
    fn capture(&mut self, argv: &[&str]) -> Result<String, String>;
    /// Runs a change with the terminal attached, so progress and prompts show.
    fn run(&mut self, argv: &[&str]) -> Result<(), String>;
}

pub struct RealRunner;

impl Runner for RealRunner {
    fn has(&self, program: &str) -> bool {
        std::env::var_os("PATH").is_some_and(|path| {
            std::env::split_paths(&path).any(|dir| is_executable(&dir.join(program)))
        })
    }

    fn capture(&mut self, argv: &[&str]) -> Result<String, String> {
        let out = Command::new(argv[0])
            .args(&argv[1..])
            .stdin(Stdio::null())
            .output()
            .map_err(|e| format!("could not start {}: {e}", argv[0]))?;
        if out.status.success() {
            return Ok(String::from_utf8_lossy(&out.stdout).into_owned());
        }
        let err = String::from_utf8_lossy(&out.stderr);
        let tail: Vec<&str> = err.lines().rev().take(4).collect();
        Err(tail.into_iter().rev().collect::<Vec<_>>().join("\n"))
    }

    fn run(&mut self, argv: &[&str]) -> Result<(), String> {
        let status = Command::new(argv[0])
            .args(&argv[1..])
            .status()
            .map_err(|e| format!("could not start {}: {e}", argv[0]))?;
        if status.success() {
            Ok(())
        } else {
            Err(format!("{} failed", argv.join(" ")))
        }
    }
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}
