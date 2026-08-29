use std::collections::BTreeSet;
use std::ffi::OsString;

use anyhow::{Result, bail};
use clap::{CommandFactory, FromArgMatches, Parser, Subcommand, ValueEnum};
use clap_complete::{Shell, generate};
use serde::Serialize;

use crate::provider::{Action, Provider, resolve_alias, resolve_package};
use crate::state::{State, Transaction};
use crate::ui::Activity;

#[derive(Debug, Parser)]
#[command(
    name = "tinypm",
    version,
    about = "One friendly package command for Linux"
)]
pub struct Cli {
    #[arg(skip)]
    entrypoint: Entrypoint,

    /// Package provider to use (auto detects the native provider)
    #[arg(
        long,
        global = true,
        value_enum,
        default_value_t = Provider::Auto,
        env = "TINYPM_PROVIDER"
    )]
    pub provider: Provider,

    /// Print the operation without changing the system
    #[arg(short = 'd', long, global = true)]
    pub dry_run: bool,

    /// Disable animated progress output
    #[arg(long, global = true)]
    pub no_progress: bool,

    #[command(subcommand)]
    pub command: Command,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum Entrypoint {
    Grab,
    #[default]
    TinyPm,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Add one or more packages
    #[command(name = "add", alias = "install", alias = "get", alias = "i")]
    Install { packages: Vec<String> },
    /// Search for a package
    #[command(alias = "find", alias = "s")]
    Search { query: String },
    /// Show package metadata from a provider
    Info { package: String },
    /// Check whether a package is available from a provider
    Check {
        package: String,
        /// Emit a structured availability report
        #[arg(long)]
        json: bool,
    },
    /// Remove one or more packages
    #[command(alias = "uninstall", alias = "rm", alias = "r")]
    Remove { packages: Vec<String> },
    /// Update installed packages
    #[command(alias = "upgrade", alias = "up", alias = "u")]
    Update,
    /// List installed packages
    #[command(alias = "ls")]
    List,
    /// Explain how a package name resolves
    Explain {
        package: String,
        /// Emit machine-readable JSON
        #[arg(long)]
        json: bool,
    },
    /// Show provider diagnostics
    Doctor {
        /// Emit machine-readable JSON
        #[arg(long)]
        json: bool,
    },
    /// List supported package providers and their availability
    Providers {
        /// Emit machine-readable JSON
        #[arg(long)]
        json: bool,
    },
    /// Show transactions performed by TinyPM
    History {
        /// Maximum number of recent records to show
        #[arg(default_value_t = 50)]
        limit: usize,
        /// Emit machine-readable JSON
        #[arg(long)]
        json: bool,
    },
    /// Show packages currently managed by TinyPM
    Managed {
        /// Emit machine-readable JSON
        #[arg(long)]
        json: bool,
    },
    /// Preview or reverse the latest package transaction
    Undo {
        /// Execute the reversal instead of only previewing it
        #[arg(short = 'y', long)]
        yes: bool,
        /// Emit a machine-readable preview
        #[arg(long, conflicts_with = "yes")]
        json: bool,
    },
    /// Generate shell completion source
    Completions {
        #[arg(value_enum)]
        shell: CompletionShell,
    },
}

#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum CompletionShell {
    Bash,
    Zsh,
    Fish,
    Elvish,
    Powershell,
}

impl From<CompletionShell> for Shell {
    fn from(shell: CompletionShell) -> Self {
        match shell {
            CompletionShell::Bash => Self::Bash,
            CompletionShell::Zsh => Self::Zsh,
            CompletionShell::Fish => Self::Fish,
            CompletionShell::Elvish => Self::Elvish,
            CompletionShell::Powershell => Self::PowerShell,
        }
    }
}

impl Cli {
    pub fn parse_env() -> Result<Self> {
        match Self::try_parse_from_normalized(std::env::args_os()) {
            Ok(cli) => Ok(cli),
            Err(error) => error.exit(),
        }
    }

    #[cfg(test)]
    fn parse_from_args<I, T>(args: I) -> Result<Self>
    where
        I: IntoIterator<Item = T>,
        T: Into<OsString> + Clone,
    {
        Self::try_parse_from_normalized(args).map_err(Into::into)
    }

    fn try_parse_from_normalized<I, T>(args: I) -> std::result::Result<Self, clap::Error>
    where
        I: IntoIterator<Item = T>,
        T: Into<OsString> + Clone,
    {
        let mut args: Vec<OsString> = args.into_iter().map(Into::into).collect();
        let program = args
            .first()
            .and_then(|arg| std::path::Path::new(arg).file_name())
            .and_then(|arg| arg.to_str())
            .unwrap_or("tinypm")
            .to_owned();

        // `grab` keeps TinyPM's install-first interface: `grab firefox`.
        if program == "grab" && should_insert_install(&args[1..]) {
            args.insert(1, OsString::from("add"));
        }

        let entrypoint = if program == "grab" {
            Entrypoint::Grab
        } else {
            Entrypoint::TinyPm
        };
        let command = command_for(entrypoint);
        let matches = command.try_get_matches_from(args)?;
        let mut cli = Self::from_arg_matches(&matches)?;
        cli.entrypoint = entrypoint;
        Ok(cli)
    }
}

fn should_insert_install(args: &[OsString]) -> bool {
    let mut positional = None;
    let mut skip_next = false;
    for arg in args {
        let Some(text) = arg.to_str() else {
            continue;
        };
        if skip_next {
            skip_next = false;
            continue;
        }
        if text == "--provider" {
            skip_next = true;
            continue;
        }
        if text == "--" {
            return true;
        }
        if text.starts_with('-') {
            continue;
        }
        positional = Some(text);
        break;
    }
    let Some(first) = positional else {
        return false;
    };

    !matches!(
        first,
        "install"
            | "add"
            | "get"
            | "i"
            | "search"
            | "find"
            | "s"
            | "info"
            | "check"
            | "remove"
            | "uninstall"
            | "rm"
            | "r"
            | "update"
            | "upgrade"
            | "up"
            | "u"
            | "list"
            | "ls"
            | "explain"
            | "doctor"
            | "providers"
            | "history"
            | "managed"
            | "undo"
            | "completions"
            | "help"
    )
}

pub fn run(cli: Cli) -> Result<()> {
    enforce_entrypoint(&cli)?;
    match cli.command {
        Command::Doctor { json } => return doctor(cli.provider, json),
        Command::Providers { json } => return show_providers(json),
        Command::History { limit, json } => return show_history(limit, json),
        Command::Managed { json } => return show_managed(json),
        Command::Undo { yes, json } => {
            return undo(yes && !cli.dry_run, json, progress_enabled(cli.no_progress));
        }
        Command::Completions { shell } => return completions(shell, cli.entrypoint),
        Command::Check { package, json } => {
            validate_package_name(&package)?;
            return check_package(cli.provider, &package, json);
        }
        Command::Explain { package, json } => {
            validate_package_name(&package)?;
            let provider = cli.provider.resolve()?;
            let resolution = resolve_package(provider, &package);
            let command =
                provider.command(Action::Install, std::slice::from_ref(&resolution.resolved))?;
            let report = ExplanationReport {
                requested: &package,
                resolved: &resolution.resolved,
                alias: resolution.is_alias(),
                reason: resolution
                    .reason
                    .unwrap_or("The package name is passed through unchanged"),
                provider: provider.label(),
                provider_key: provider.key(),
                command: command.display(),
            };
            if json {
                serde_json::to_writer_pretty(std::io::stdout(), &report)?;
                println!();
            } else {
                println!("Package      {}", report.requested);
                println!("Resolved     {}", report.resolved);
                println!("Alias        {}", if report.alias { "yes" } else { "no" });
                println!("Reason       {}", report.reason);
                println!("Provider     {}", report.provider);
                println!("Command      {}", report.command);
            }
            return Ok(());
        }
        _ => {}
    }

    let provider = cli.provider.resolve()?;
    let dry_run = cli.dry_run;
    let progress = progress_enabled(cli.no_progress);
    let (action, requested, values) = match cli.command {
        Command::Install { packages } => {
            require_values("install", &packages)?;
            let (mut requested, mut resolved) = resolve_unique(provider, packages);
            if !dry_run {
                (requested, resolved) =
                    filter_by_installed_state(provider, requested, resolved, false)?;
            }
            (Action::Install, requested, resolved)
        }
        Command::Search { query } => (Action::Search, vec![query.clone()], vec![query]),
        Command::Info { package } => {
            validate_package_name(&package)?;
            let resolved = resolve_alias(provider, &package);
            (Action::Info, vec![package], vec![resolved])
        }
        Command::Remove { packages } => {
            require_values("remove", &packages)?;
            let (mut requested, mut resolved) = resolve_unique(provider, packages);
            if !dry_run {
                (requested, resolved) =
                    filter_by_installed_state(provider, requested, resolved, true)?;
            }
            (Action::Remove, requested, resolved)
        }
        Command::Update => (Action::Update, vec![], vec![]),
        Command::List => (Action::List, vec![], vec![]),
        Command::Explain { .. }
        | Command::Doctor { .. }
        | Command::Providers { .. }
        | Command::History { .. }
        | Command::Managed { .. }
        | Command::Undo { .. }
        | Command::Completions { .. }
        | Command::Check { .. } => unreachable!(),
    };

    if values.is_empty() && matches!(action, Action::Install | Action::Remove) {
        println!("Nothing to do.");
        return Ok(());
    }

    if matches!(action, Action::Install | Action::Remove) {
        return execute_package_operations(
            provider, action, &requested, &values, dry_run, progress,
        );
    }

    let plan = provider.plan(action, &values)?;
    if dry_run {
        println!(
            "Dry run ({} step{}):",
            plan.len(),
            if plan.len() == 1 { "" } else { "s" }
        );
        for (index, command) in plan.iter().enumerate() {
            println!("  {}. {}", index + 1, command.display());
        }
        return Ok(());
    }
    if matches!(action, Action::Update) {
        let activity = Activity::start(format!("Updating with {}", provider.label()), progress);
        if let Err(error) = plan.iter().try_for_each(|command| command.execute()) {
            activity.failure(format!("{} update failed", provider.label()));
            return Err(error);
        }
        activity.success(format!("{} packages updated", provider.label()));
    } else {
        for command in &plan {
            command.execute()?;
        }
    }

    Ok(())
}

#[derive(Serialize)]
struct ExplanationReport<'a> {
    requested: &'a str,
    resolved: &'a str,
    alias: bool,
    reason: &'a str,
    provider: &'static str,
    provider_key: &'static str,
    command: String,
}

#[derive(Serialize)]
struct AvailabilityReport<'a> {
    requested: &'a str,
    resolved: &'a str,
    provider: &'static str,
    provider_key: &'static str,
    available: bool,
}

#[derive(Serialize)]
struct UndoReport<'a> {
    transaction_id: &'a str,
    original_action: &'a str,
    reversal_action: &'a str,
    requested: &'a str,
    resolved: &'a str,
    provider: &'static str,
    provider_key: &'static str,
    command: String,
}

fn enforce_entrypoint(cli: &Cli) -> Result<()> {
    if cli.entrypoint == Entrypoint::Grab {
        return Ok(());
    }
    match &cli.command {
        Command::Install { .. } => bail!("installation belongs to grab; use `grab <PACKAGE>...`"),
        Command::Remove { .. } => {
            bail!("package removal belongs to grab; use `grab remove <PACKAGE>...`")
        }
        Command::Update => bail!("package updating belongs to grab; use `grab update`"),
        Command::Undo { yes: true, .. } => {
            bail!("transaction reversal belongs to grab; use `grab undo --yes`")
        }
        _ => Ok(()),
    }
}

fn execute_package_operations(
    provider: Provider,
    action: Action,
    requested: &[String],
    resolved: &[String],
    dry_run: bool,
    progress: bool,
) -> Result<()> {
    let action_name = if matches!(action, Action::Install) {
        "install"
    } else {
        "remove"
    };

    if dry_run {
        println!(
            "Dry run ({} package{}):",
            resolved.len(),
            if resolved.len() == 1 { "" } else { "s" }
        );
        for (index, package) in resolved.iter().enumerate() {
            let plan = provider.plan(action, std::slice::from_ref(package))?;
            for command in plan {
                println!("  {}. {}", index + 1, command.display());
            }
        }
        return Ok(());
    }

    let state = State::discover()?;
    let mut succeeded = 0usize;
    let mut failures = Vec::new();
    for (original, package) in requested.iter().zip(resolved) {
        let plan = provider.plan(action, std::slice::from_ref(package))?;
        let position = succeeded + failures.len() + 1;
        let activity = Activity::start(
            format!(
                "{} {original} with {} [{position}/{}]",
                if action_name == "install" {
                    "Grabbing"
                } else {
                    "Removing"
                },
                provider.label(),
                resolved.len()
            ),
            progress,
        );
        let result = plan.iter().try_for_each(|command| command.execute());
        match result {
            Ok(()) => {
                state.append(&Transaction::new(
                    action_name,
                    original,
                    package,
                    provider.key(),
                ))?;
                succeeded += 1;
                let result = if action_name == "install" {
                    "installed"
                } else {
                    "removed"
                };
                activity.success(format!("{original} {result}"));
            }
            Err(error) => {
                activity.failure(format!("{original} failed"));
                eprintln!("Failed to {action_name} {original}: {error:#}");
                failures.push(original.as_str());
            }
        }
    }

    println!("Summary: {succeeded} succeeded, {} failed", failures.len());
    if !failures.is_empty() {
        bail!("{action_name} failed for: {}", failures.join(", "));
    }
    Ok(())
}

fn progress_enabled(no_progress: bool) -> bool {
    !no_progress && std::env::var_os("TINYPM_NO_PROGRESS").is_none()
}

fn resolve_unique(provider: Provider, packages: Vec<String>) -> (Vec<String>, Vec<String>) {
    let mut seen = BTreeSet::new();
    let mut requested = Vec::new();
    let mut resolved = Vec::new();
    for package in packages {
        let native = resolve_alias(provider, &package);
        if seen.insert(native.clone()) {
            requested.push(package);
            resolved.push(native);
        } else {
            println!("Duplicate package skipped: {package} ({native})");
        }
    }
    (requested, resolved)
}

fn filter_by_installed_state(
    provider: Provider,
    requested: Vec<String>,
    resolved: Vec<String>,
    keep_installed: bool,
) -> Result<(Vec<String>, Vec<String>)> {
    let mut kept_requested = Vec::new();
    let mut kept_resolved = Vec::new();
    for (original, package) in requested.into_iter().zip(resolved) {
        let installed = provider.is_installed(&package)?;
        let skip = if keep_installed {
            installed == Some(false)
        } else {
            installed == Some(true)
        };
        if skip {
            if keep_installed {
                println!("Not installed: {original} ({package})");
            } else {
                println!("Already installed: {original} ({package})");
            }
        } else {
            kept_requested.push(original);
            kept_resolved.push(package);
        }
    }
    Ok((kept_requested, kept_resolved))
}

fn require_values(action: &str, values: &[String]) -> Result<()> {
    if values.is_empty() {
        bail!("{action} requires at least one package name");
    }
    for value in values {
        validate_package_name(value)?;
    }
    Ok(())
}

fn validate_package_name(package: &str) -> Result<()> {
    if package.is_empty() {
        bail!("package name cannot be empty");
    }
    if package.starts_with('-') {
        bail!("unsafe package name `{package}`: names cannot begin with '-'");
    }
    if !package
        .chars()
        .all(|character| character.is_ascii_alphanumeric() || ".+_@/:#-".contains(character))
    {
        bail!(
            "unsafe package name `{package}`: use only letters, numbers, '.', '+', '_', '@', '/', ':', '#', and '-'"
        );
    }
    Ok(())
}

#[derive(Serialize)]
struct DoctorReport {
    version: &'static str,
    requested_provider: &'static str,
    provider: Option<&'static str>,
    provider_key: Option<&'static str>,
    provider_validation: Option<&'static str>,
    executable: Option<String>,
    missing_executables: Vec<&'static str>,
    provider_healthy: bool,
    provider_error: Option<String>,
    state_path: Option<String>,
    history_records: Option<usize>,
    state_healthy: bool,
    state_error: Option<String>,
}

#[derive(Serialize)]
struct ProviderReport {
    key: &'static str,
    name: &'static str,
    executable: &'static str,
    path: Option<String>,
    available: bool,
    ready: bool,
    validation: &'static str,
    missing_executables: Vec<&'static str>,
}

fn show_providers(json: bool) -> Result<()> {
    let reports = Provider::supported()
        .iter()
        .map(|provider| {
            let path = provider
                .executable_path()
                .map(|path| path.display().to_string());
            let missing_executables = provider.missing_executables();
            ProviderReport {
                key: provider.key(),
                name: provider.label(),
                executable: provider.executable(),
                available: path.is_some(),
                ready: missing_executables.is_empty(),
                validation: provider.validation_level(),
                missing_executables,
                path,
            }
        })
        .collect::<Vec<_>>();
    if json {
        serde_json::to_writer_pretty(std::io::stdout(), &reports)?;
        println!();
        return Ok(());
    }

    println!("PROVIDER\tSTATUS\tVALIDATION\tEXECUTABLE");
    for report in reports {
        println!(
            "{}\t{}\t{}\t{}",
            report.name,
            if report.ready {
                "ready"
            } else if report.available {
                "incomplete"
            } else {
                "missing"
            },
            report.validation,
            if report.missing_executables.is_empty() {
                report
                    .path
                    .as_deref()
                    .unwrap_or(report.executable)
                    .to_owned()
            } else {
                format!("missing: {}", report.missing_executables.join(", "))
            }
        );
    }
    Ok(())
}

fn doctor(requested: Provider, json: bool) -> Result<()> {
    let (
        provider,
        provider_key,
        provider_validation,
        executable,
        missing_executables,
        provider_error,
    ) = match requested.resolve() {
        Ok(provider) => {
            let missing = provider.missing_executables();
            let error = (!missing.is_empty())
                .then(|| format!("required executables are missing: {}", missing.join(", ")));
            (
                Some(provider.label()),
                Some(provider.key()),
                Some(provider.validation_level()),
                provider
                    .executable_path()
                    .map(|path| path.display().to_string()),
                missing,
                error,
            )
        }
        Err(error) if requested != Provider::Auto => (
            Some(requested.label()),
            Some(requested.key()),
            Some(requested.validation_level()),
            None,
            requested.missing_executables(),
            Some(format!("{error:#}")),
        ),
        Err(error) => (
            None,
            None,
            None,
            None,
            Vec::new(),
            Some(format!("{error:#}")),
        ),
    };
    let (state_path, history_records, state_error) = match State::discover() {
        Ok(state) => {
            let path = Some(state.history_path().display().to_string());
            match state.history() {
                Ok(history) => (path, Some(history.len()), None),
                Err(error) => (path, None, Some(format!("{error:#}"))),
            }
        }
        Err(error) => (None, None, Some(format!("{error:#}"))),
    };
    let report = DoctorReport {
        version: env!("CARGO_PKG_VERSION"),
        requested_provider: requested.key(),
        provider,
        provider_key,
        provider_validation,
        executable,
        missing_executables,
        provider_healthy: provider_error.is_none(),
        provider_error,
        state_path,
        history_records,
        state_healthy: state_error.is_none(),
        state_error,
    };

    if json {
        serde_json::to_writer_pretty(std::io::stdout(), &report)?;
        println!();
    } else {
        println!("TinyPM        {}", report.version);
        println!("Requested     {}", report.requested_provider);
        println!("Provider      {}", report.provider.unwrap_or("unavailable"));
        println!(
            "Validation    {}",
            report.provider_validation.unwrap_or("unavailable")
        );
        println!(
            "Executable    {}",
            report.executable.as_deref().unwrap_or("not found")
        );
        if !report.missing_executables.is_empty() {
            println!("Missing       {}", report.missing_executables.join(", "));
        }
        println!(
            "State         {}",
            report.state_path.as_deref().unwrap_or("unavailable")
        );
        println!(
            "Transactions  {}",
            report
                .history_records
                .map_or_else(|| "unknown".to_owned(), |count| count.to_string())
        );
        println!(
            "Status        {}",
            if report.provider_healthy && report.state_healthy {
                "healthy"
            } else {
                "needs attention"
            }
        );
        if let Some(error) = &report.provider_error {
            eprintln!("Provider issue: {error}");
        }
        if let Some(error) = &report.state_error {
            eprintln!("State issue: {error}");
        }
    }

    if !report.provider_healthy || !report.state_healthy {
        bail!("doctor found problems");
    }
    Ok(())
}

fn show_history(limit: usize, json: bool) -> Result<()> {
    let state = State::discover()?;
    let history = state.history()?;
    let recent = history.iter().rev().take(limit).collect::<Vec<_>>();
    if json {
        serde_json::to_writer_pretty(std::io::stdout(), &recent)?;
        println!();
        return Ok(());
    }
    if history.is_empty() {
        println!("No TinyPM transactions recorded.");
        return Ok(());
    }
    println!("TIMESTAMP\tACTION\tPACKAGE\tRESOLVED\tPROVIDER");
    for transaction in recent {
        println!(
            "{}\t{}\t{}\t{}\t{}",
            transaction.timestamp,
            transaction.action,
            transaction.requested,
            transaction.resolved,
            transaction.provider
        );
    }
    Ok(())
}

fn show_managed(json: bool) -> Result<()> {
    let state = State::discover()?;
    let packages = state.managed()?;
    if json {
        serde_json::to_writer_pretty(std::io::stdout(), &packages)?;
        println!();
        return Ok(());
    }
    if packages.is_empty() {
        println!("No packages are currently managed by TinyPM.");
        return Ok(());
    }
    println!("PACKAGE\tRESOLVED\tPROVIDER\tINSTALLED");
    for package in packages {
        println!(
            "{}\t{}\t{}\t{}",
            package.requested, package.resolved, package.provider, package.timestamp
        );
    }
    Ok(())
}

fn undo(execute: bool, json: bool, progress: bool) -> Result<()> {
    let state = State::discover()?;
    let Some(original) = state.latest_reversible()? else {
        if json {
            println!("null");
        } else {
            println!("No reversible TinyPM transaction found.");
        }
        return Ok(());
    };
    let reversal = Transaction::reversing(&original);
    let recorded_provider = Provider::from_key(&original.provider)?;
    let provider = if execute {
        recorded_provider.resolve()?
    } else {
        recorded_provider
    };
    let action = if reversal.action == "install" {
        Action::Install
    } else {
        Action::Remove
    };
    let command = provider.command(action, std::slice::from_ref(&original.resolved))?;

    if json {
        let report = UndoReport {
            transaction_id: &original.id,
            original_action: &original.action,
            reversal_action: &reversal.action,
            requested: &original.requested,
            resolved: &original.resolved,
            provider: provider.label(),
            provider_key: provider.key(),
            command: command.display(),
        };
        serde_json::to_writer_pretty(std::io::stdout(), &report)?;
        println!();
        return Ok(());
    }

    println!(
        "Undo {} of {} with {}",
        original.action,
        original.requested,
        provider.label()
    );
    println!("Command      {}", command.display());
    if !execute {
        println!("Preview only. Run `grab undo --yes` to continue.");
        return Ok(());
    }

    let activity = Activity::start(format!("Reversing {}", original.requested), progress);
    if let Err(error) = command.execute() {
        activity.failure(format!("Could not reverse {}", original.requested));
        return Err(error);
    }
    state.append(&reversal)?;
    activity.success(format!("Reversed {}", original.requested));
    Ok(())
}

fn completions(shell: CompletionShell, entrypoint: Entrypoint) -> Result<()> {
    let mut command = completion_command_for(entrypoint);
    let name = if entrypoint == Entrypoint::Grab {
        "grab"
    } else {
        "tinypm"
    };
    generate(
        Shell::from(shell),
        &mut command,
        name,
        &mut std::io::stdout(),
    );
    Ok(())
}

fn completion_command_for(entrypoint: Entrypoint) -> clap::Command {
    if entrypoint == Entrypoint::Grab {
        return command_for(entrypoint);
    }

    const INSPECTION_COMMANDS: &[&str] = &[
        "search",
        "info",
        "check",
        "list",
        "explain",
        "doctor",
        "providers",
        "history",
        "managed",
        "undo",
        "completions",
    ];
    let source = command_for(Entrypoint::TinyPm);
    let mut command = clap::Command::new("tinypm")
        .version(env!("CARGO_PKG_VERSION"))
        .about("Inspect packages and diagnose TinyPM");
    if let Some(provider) = source
        .get_arguments()
        .find(|argument| argument.get_id() == "provider")
    {
        command = command.arg(provider.clone());
    }
    for subcommand in source
        .get_subcommands()
        .filter(|subcommand| INSPECTION_COMMANDS.contains(&subcommand.get_name()))
    {
        command = command.subcommand(subcommand.clone());
    }
    command
}

fn command_for(entrypoint: Entrypoint) -> clap::Command {
    let name = if entrypoint == Entrypoint::Grab {
        "grab"
    } else {
        "tinypm"
    };
    let mut command = Cli::command().name(name);
    if entrypoint == Entrypoint::TinyPm {
        command = command
            .about("Inspect packages and diagnose TinyPM")
            .mut_arg("dry_run", |argument| argument.hide(true))
            .mut_arg("no_progress", |argument| argument.hide(true))
            .mut_subcommand("add", |command| command.hide(true))
            .mut_subcommand("remove", |command| command.hide(true))
            .mut_subcommand("update", |command| command.hide(true))
            .mut_subcommand("undo", |command| {
                command
                    .about("Preview the latest reversible transaction")
                    .mut_arg("yes", |argument| argument.hide(true))
            });
    }
    command
}

fn check_package(requested_provider: Provider, package: &str, json: bool) -> Result<()> {
    let provider = requested_provider.resolve()?;
    let resolved = resolve_alias(provider, package);
    let available = provider.is_available(&resolved)?;
    if json {
        let report = AvailabilityReport {
            requested: package,
            resolved: &resolved,
            provider: provider.label(),
            provider_key: provider.key(),
            available,
        };
        println!("{}", serde_json::to_string_pretty(&report)?);
    } else if available {
        println!("Available: {package} ({resolved}) via {}", provider.label());
    }

    if available {
        Ok(())
    } else {
        bail!(
            "package not available: {package} ({resolved}) via {}",
            provider.label()
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn grab_defaults_to_install() {
        let cli = Cli::parse_from_args(["grab", "firefox"]).unwrap();
        assert!(matches!(cli.command, Command::Install { packages } if packages == ["firefox"]));
    }

    #[test]
    fn grab_preserves_subcommands() {
        let cli = Cli::parse_from_args(["grab", "search", "editor"]).unwrap();
        assert!(matches!(cli.command, Command::Search { query } if query == "editor"));
    }

    #[test]
    fn grab_understands_provider_before_subcommand() {
        let cli = Cli::parse_from_args(["grab", "--provider", "apk", "search", "editor"]).unwrap();
        assert_eq!(cli.provider, Provider::Apk);
        assert!(matches!(cli.command, Command::Search { query } if query == "editor"));
    }

    #[test]
    fn grab_double_dash_installs_reserved_package_name() {
        let cli = Cli::parse_from_args(["grab", "--", "search"]).unwrap();
        assert!(matches!(cli.command, Command::Install { packages } if packages == ["search"]));
    }

    #[test]
    fn compatibility_aliases_map_to_core_commands() {
        let add = Cli::parse_from_args(["grab", "add", "curl"]).unwrap();
        assert!(matches!(add.command, Command::Install { packages } if packages == ["curl"]));
        let install = Cli::parse_from_args(["grab", "install", "curl"]).unwrap();
        assert!(matches!(install.command, Command::Install { packages } if packages == ["curl"]));
        let remove = Cli::parse_from_args(["grab", "uninstall", "curl"]).unwrap();
        assert!(matches!(remove.command, Command::Remove { packages } if packages == ["curl"]));
        let update = Cli::parse_from_args(["tinypm", "upgrade"]).unwrap();
        assert!(matches!(update.command, Command::Update));
    }

    #[test]
    fn aliases_that_resolve_to_same_package_are_deduplicated() {
        let (requested, resolved) = resolve_unique(
            Provider::Pacman,
            vec!["gcc++".into(), "gcc".into(), "curl".into()],
        );
        assert_eq!(requested, ["gcc++", "curl"]);
        assert_eq!(resolved, ["gcc", "curl"]);
    }

    #[test]
    fn package_validation_accepts_real_provider_forms() {
        for package in [
            "libgtk-3-dev",
            "curl:amd64",
            "org.mozilla.firefox",
            "owner/tap/formula@2",
            "nixpkgs#ripgrep",
            "gcc++",
        ] {
            validate_package_name(package).unwrap();
        }
    }

    #[test]
    fn package_validation_rejects_options_and_shell_like_input() {
        for package in [
            "--noconfirm",
            "name with space",
            "$(touch-pwned)",
            "name;command",
        ] {
            assert!(validate_package_name(package).is_err());
        }
    }
}
