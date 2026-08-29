mod cli;
mod provider;
mod state;
mod ui;

use anyhow::Result;

/// Parse the current process arguments and run TinyPM.
pub fn run() -> Result<()> {
    let cli = cli::Cli::parse_env()?;
    cli::run(cli)
}
