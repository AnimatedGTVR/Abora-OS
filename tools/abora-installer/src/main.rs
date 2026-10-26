mod cli;
mod config;
mod disk;
mod disk_cli;
mod flake;
mod flake_cli;
mod install;
mod logging;
mod runner;
mod system;
mod tui;

use std::process::ExitCode;

fn main() -> ExitCode {
    let raw: Vec<_> = std::env::args_os().skip(1).collect();
    let subcommand = match raw.first().and_then(|a| a.to_str()) {
        Some("disk") => Some(disk_cli::run as fn(&[std::ffi::OsString]) -> Result<u8, String>),
        Some("flake") => Some(flake_cli::run as fn(&[std::ffi::OsString]) -> Result<u8, String>),
        _ => None,
    };
    if let Some(run) = subcommand {
        return match run(&raw[1..]) {
            Ok(code) => ExitCode::from(code),
            Err(err) => {
                eprintln!("abora-installer: {err}");
                ExitCode::from(1)
            }
        };
    }

    let args = match cli::Args::parse(raw) {
        Ok(args) => args,
        Err(err) => {
            eprintln!("abora-installer: {err}");
            eprintln!("Try: abora-installer --help");
            return ExitCode::from(2);
        }
    };

    if args.help {
        tui::print_help();
        return ExitCode::SUCCESS;
    }

    if args.version {
        println!("abora-installer {}", config::VERSION);
        return ExitCode::SUCCESS;
    }

    match install::run(args) {
        Ok(code) => ExitCode::from(code),
        Err(err) => {
            eprintln!("abora-installer: {err}");
            ExitCode::from(1)
        }
    }
}
