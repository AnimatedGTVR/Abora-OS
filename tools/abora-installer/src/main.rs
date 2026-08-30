mod cli;
mod config;
mod install;
mod logging;
mod runner;
mod tui;

use std::process::ExitCode;

fn main() -> ExitCode {
    let args = match cli::Args::parse(std::env::args_os().skip(1)) {
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
