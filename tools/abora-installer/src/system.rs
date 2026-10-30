use std::collections::HashSet;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::FileTypeExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

use crate::disk::Host;

fn is_block_device(path: &str) -> bool {
    std::fs::metadata(path)
        .map(|m| m.file_type().is_block_device())
        .unwrap_or(false)
}

fn open_log(path: &Path) -> Option<File> {
    OpenOptions::new().create(true).append(true).open(path).ok()
}

pub struct RealHost {
    log_path: PathBuf,
}

impl RealHost {
    pub fn new(log_path: PathBuf) -> Self {
        Self { log_path }
    }
}

impl Host for RealHost {
    fn is_block(&self, path: &str) -> bool {
        is_block_device(path)
    }

    fn run(&mut self, timeout_secs: u32, argv: &[&str]) -> Result<(), String> {
        self.log(&format!("$ {}", argv.join(" ")));
        let mut cmd = Command::new("timeout");
        cmd.args([
            "--signal=TERM",
            "--kill-after=5s",
            &format!("{timeout_secs}s"),
        ])
        .args(argv)
        .stdin(Stdio::null());
        match open_log(&self.log_path) {
            Some(log) => {
                let err = log
                    .try_clone()
                    .map(Stdio::from)
                    .unwrap_or_else(|_| Stdio::null());
                cmd.stdout(Stdio::from(log)).stderr(err);
            }
            None => {
                cmd.stdout(Stdio::null()).stderr(Stdio::null());
            }
        }
        let status = cmd
            .status()
            .map_err(|err| format!("could not start {}: {err}", argv[0]))?;
        match status.code() {
            Some(0) => Ok(()),
            Some(124) => Err(format!(
                "{} timed out after {timeout_secs}s",
                argv.join(" ")
            )),
            Some(code) => Err(format!("{} failed (exit {code})", argv.join(" "))),
            None => Err(format!("{} was killed", argv.join(" "))),
        }
    }

    fn query(&mut self, argv: &[&str]) -> Option<String> {
        let out = Command::new(argv[0])
            .args(&argv[1..])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .ok()?;
        out.status
            .success()
            .then(|| String::from_utf8_lossy(&out.stdout).into_owned())
    }

    fn sleep(&mut self, secs: u64) {
        std::thread::sleep(Duration::from_secs(secs));
    }

    fn log(&mut self, message: &str) {
        if let Some(mut log) = open_log(&self.log_path) {
            let _ = writeln!(log, "[installer] {message}");
        }
    }
}

/// Reads the machine for real but only prints what it would change.
pub struct DryRunHost {
    /// Partitions the plan creates; they cannot exist yet in a dry run.
    pub planned: HashSet<String>,
}

impl Host for DryRunHost {
    fn is_block(&self, path: &str) -> bool {
        self.planned.contains(path) || is_block_device(path)
    }

    fn run(&mut self, _timeout_secs: u32, argv: &[&str]) -> Result<(), String> {
        eprintln!("would run: {}", argv.join(" "));
        Ok(())
    }

    fn query(&mut self, argv: &[&str]) -> Option<String> {
        RealHost::new(PathBuf::from("/dev/null")).query(argv)
    }

    fn sleep(&mut self, _secs: u64) {}

    fn log(&mut self, _message: &str) {}

    fn verifies_writes(&self) -> bool {
        false
    }
}
