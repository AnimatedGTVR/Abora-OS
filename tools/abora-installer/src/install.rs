use crate::cli::Args;
use crate::{config, logging, runner, tui};

pub fn run(args: Args) -> Result<u8, String> {
    if args.smoke_test {
        tui::print_smoke_status(&args.legacy_script);
        return Ok(0);
    }

    if args.dry_run {
        tui::print_dry_run(&args.legacy_script, &args.passthrough);
        return Ok(0);
    }

    logging::append(
        &config::log_path(),
        &format!(
            "[rust-installer] delegating to {}\n",
            args.legacy_script.display()
        ),
    );
    runner::run_legacy(&args.legacy_script, &args.passthrough)
}
