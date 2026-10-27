//! grab: install an app from whichever source has it (Nix or Lix, Flatpak, Snap).

mod grab;
mod providers;
mod runner;

use std::process::ExitCode;

use grab::Resolution;
use providers::{Kind, Scope, Settings};
use runner::{RealRunner, Runner};

const HELP: &str = "\
grab: install an app from whichever source has it

Usage:
  grab <app>...              install (also: grab install <app>...)
  grab remove <app>...       uninstall, from wherever it was installed
  grab search <words>        list matches from every source
  grab info <app>            show where grab would get it, and the exact command
  grab providers             show which sources this system has

Sources, in the order grab asks them: Nix (or Lix), Flatpak (Flathub), Snap.
A few names are pinned to a source (zen-browser comes from Flathub). Only an
exact name match is installed; close matches are listed for you to pick.

Options:
  --provider <nix|lix|flatpak|snap>   use only this source
  --system                            Flatpak: install for every user (needs root)
  --dry-run                           print the commands, change nothing
  -h, --help                          this help";

struct Args {
    command: String,
    names: Vec<String>,
    only: Option<Kind>,
    dry_run: bool,
    settings: Settings,
}

fn parse(raw: Vec<String>) -> Result<Args, String> {
    let mut args = Args {
        command: String::new(),
        names: Vec::new(),
        only: None,
        dry_run: false,
        settings: Settings::default(),
    };
    let mut iter = raw.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "-h" | "--help" | "help" if args.command.is_empty() => args.command = "help".into(),
            "--provider" | "-p" => {
                let v = iter
                    .next()
                    .ok_or("--provider needs nix, lix, flatpak or snap")?;
                args.only = Some(Kind::parse(&v).ok_or(format!(
                    "unknown provider {v}: use nix, lix, flatpak or snap"
                ))?);
            }
            "--system" => args.settings.scope = Scope::System,
            "--user" => args.settings.scope = Scope::User,
            "--dry-run" | "-n" => args.dry_run = true,
            flag if flag.starts_with('-') => {
                return Err(format!("unknown option {flag} (see grab --help)"))
            }
            word if args.command.is_empty() => {
                args.command = match word {
                    "install" | "get" | "add" => "install".into(),
                    "remove" | "uninstall" | "rm" => "remove".into(),
                    "search" | "find" => "search".into(),
                    "info" | "explain" | "check" => "info".into(),
                    "providers" | "sources" => "providers".into(),
                    _ => {
                        args.names.push(word.into());
                        "install".into()
                    }
                }
            }
            _ => args.names.push(arg),
        }
    }
    if args.command.is_empty() {
        args.command = "help".into();
    }
    let needs_names = ["install", "remove", "search", "info"].contains(&args.command.as_str());
    if needs_names && args.names.is_empty() {
        return Err(format!("grab {} needs a package name", args.command));
    }
    Ok(args)
}

fn label(kind: Kind, runner: &mut dyn Runner) -> &'static str {
    if kind == Kind::Nix {
        providers::nix_flavor(runner)
    } else {
        kind.program()
    }
}

fn execute(cmd: &[String], dry_run: bool, runner: &mut dyn Runner) -> Result<(), String> {
    if dry_run {
        println!("  would run: {}", cmd.join(" "));
        return Ok(());
    }
    runner.run(&cmd.iter().map(String::as_str).collect::<Vec<_>>())
}

fn sudo_hint(kind: Kind, settings: &Settings) -> Option<&'static str> {
    let root = std::env::var("USER").is_ok_and(|u| u == "root");
    (!root && (kind == Kind::Snap || (kind == Kind::Flatpak && settings.scope == Scope::System)))
        .then_some("  this source needs root; try again with sudo")
}

fn install(name: &str, a: &Args, runner: &mut dyn Runner) -> bool {
    for kind in grab::available(runner) {
        if a.only.is_some_and(|o| o != kind) {
            continue;
        }
        if let Some(id) = providers::installed(kind, name, runner) {
            println!(
                "grab: {name} is already installed ({}: {id})",
                label(kind, runner)
            );
            return true;
        }
    }
    match grab::resolve(name, a.only, runner, &a.settings) {
        Ok(Resolution::Found { kind, id, why }) => {
            let source = label(kind, runner);
            println!("grab: {name} -> {source} {id} ({why})");
            let cmd = providers::install_command(kind, &id, runner, &a.settings);
            match execute(&cmd, a.dry_run, runner) {
                Ok(()) if a.dry_run => true,
                Ok(()) => {
                    println!("grab: installed {name} from {source}");
                    true
                }
                Err(e) => {
                    eprintln!("grab: {e}");
                    if let Some(hint) = sudo_hint(kind, &a.settings) {
                        eprintln!("{hint}");
                    }
                    false
                }
            }
        }
        Ok(Resolution::Ambiguous(list)) => {
            eprintln!("grab: nothing is called exactly \"{name}\". Close matches:");
            for (kind, c) in list {
                eprintln!("  {:<8} {:<34} {}", label(kind, runner), c.id, c.summary);
            }
            eprintln!("Install one with: grab <id>   (or pick a source with --provider)");
            false
        }
        Ok(Resolution::NotFound) => {
            let sources: Vec<&str> = grab::available(runner)
                .into_iter()
                .map(|k| label(k, runner))
                .collect();
            eprintln!(
                "grab: no source has \"{name}\" (asked: {})",
                sources.join(", ")
            );
            false
        }
        Err(e) => {
            eprintln!("grab: {e}");
            false
        }
    }
}

fn remove(name: &str, a: &Args, runner: &mut dyn Runner) -> bool {
    for kind in grab::available(runner) {
        if a.only.is_some_and(|o| o != kind) {
            continue;
        }
        if let Some(id) = providers::installed(kind, name, runner) {
            let source = label(kind, runner);
            let cmd = providers::remove_command(kind, &id, &a.settings);
            return match execute(&cmd, a.dry_run, runner) {
                Ok(()) => {
                    if !a.dry_run {
                        println!("grab: removed {id} ({source})");
                    }
                    true
                }
                Err(e) => {
                    eprintln!("grab: {e}");
                    false
                }
            };
        }
    }
    eprintln!("grab: {name} isn't installed by grab, Nix, Flatpak or Snap for this user");
    eprintln!("  Packages in your system config are removed with: anix package remove {name}");
    false
}

fn search(a: &Args, runner: &mut dyn Runner) -> bool {
    let query = a.names.join(" ");
    let mut any = false;
    for kind in grab::available(runner) {
        if a.only.is_some_and(|o| o != kind) {
            continue;
        }
        let source = label(kind, runner);
        match providers::search(kind, &query, runner, &a.settings) {
            Ok(found) if found.is_empty() => println!("{source}: no matches"),
            Ok(found) => {
                any = true;
                println!("{source}:");
                for c in found.iter().take(15) {
                    println!("  {:<34} {}", c.id, c.summary);
                }
                if found.len() > 15 {
                    println!("  ... and {} more", found.len() - 15);
                }
            }
            Err(e) => println!("{source}: search failed: {e}"),
        }
    }
    any
}

fn info(name: &str, a: &Args, runner: &mut dyn Runner) -> bool {
    match grab::resolve(name, a.only, runner, &a.settings) {
        Ok(Resolution::Found { kind, id, why }) => {
            let cmd = providers::install_command(kind, &id, runner, &a.settings);
            println!("{name}");
            println!("  source:  {}", label(kind, runner));
            println!("  id:      {id}");
            println!("  chosen:  {why}");
            println!("  command: {}", cmd.join(" "));
            true
        }
        Ok(Resolution::Ambiguous(_)) | Ok(Resolution::NotFound) => {
            eprintln!("grab: no exact match for {name}; try: grab search {name}");
            false
        }
        Err(e) => {
            eprintln!("grab: {e}");
            false
        }
    }
}

fn providers_report(runner: &mut dyn Runner) {
    for kind in Kind::ALL {
        if !runner.has(kind.program()) {
            println!("  {:<8} not installed", kind.program());
            continue;
        }
        let version = runner
            .capture(&[kind.program(), "--version"])
            .ok()
            .and_then(|v| v.lines().next().map(str::to_string))
            .unwrap_or_default();
        println!("  {:<8} {version}", label(kind, runner));
    }
}

/// Runs `f` for every name, even after one fails, and reports whether all worked.
fn every(names: &[String], mut f: impl FnMut(&str) -> bool) -> bool {
    let mut ok = true;
    for name in names {
        ok &= f(name);
    }
    ok
}

fn main() -> ExitCode {
    let a = match parse(std::env::args().skip(1).collect()) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("grab: {e}");
            return ExitCode::from(2);
        }
    };
    let mut runner = RealRunner;
    let ok = match a.command.as_str() {
        "help" => {
            println!("{HELP}");
            true
        }
        "providers" => {
            providers_report(&mut runner);
            true
        }
        "search" => search(&a, &mut runner),
        "info" => a.names.iter().all(|n| info(n, &a, &mut runner)),
        "remove" => every(&a.names, |n| remove(n, &a, &mut runner)),
        _ => every(&a.names, |n| install(n, &a, &mut runner)),
    };
    if ok {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grab::tests::{Fake, HTOP};

    fn args(items: &[&str]) -> Args {
        let mut a = parse(items.iter().map(|s| s.to_string()).collect()).unwrap();
        a.settings.config_dir = "/nonexistent".into();
        a
    }

    #[test]
    fn a_bare_name_means_install() {
        let a = args(&["zen-browser", "htop"]);
        assert_eq!(a.command, "install");
        assert_eq!(a.names, ["zen-browser", "htop"]);
        assert_eq!(args(&["rm", "htop"]).command, "remove");
        assert_eq!(
            args(&["--provider", "lix", "search", "x"]).only,
            Some(Kind::Nix)
        );
    }

    #[test]
    fn bad_usage_is_rejected() {
        assert!(parse(vec!["remove".into()]).is_err());
        assert!(parse(vec!["--provider".into(), "apt".into(), "x".into()]).is_err());
        assert!(parse(vec!["--force".into()]).is_err());
        assert_eq!(parse(Vec::new()).unwrap().command, "help");
    }

    fn runner(extra: &[(&'static str, Result<&str, &str>)]) -> Fake {
        let mut f = Fake {
            programs: vec!["nix", "flatpak"],
            ..Fake::default()
        };
        f.answers
            .insert("nix --version", Ok("nix (Lix, like Nix) 2.93.0".into()));
        f.answers.insert(
            "nix --extra-experimental-features nix-command flakes profile list",
            Ok(r#"{"elements":{}}"#.into()),
        );
        f.answers.insert(
            "nix --extra-experimental-features nix-command flakes profile add",
            Ok(String::new()),
        );
        f.answers.insert("flatpak list", Ok(String::new()));
        for (k, v) in extra {
            f.answers
                .insert(k, v.map(str::to_string).map_err(str::to_string));
        }
        f
    }

    #[test]
    fn installs_zen_from_flathub_for_this_user() {
        let mut f = runner(&[]);
        assert!(install("zen-browser", &args(&["zen-browser"]), &mut f));
        assert_eq!(
            f.ran,
            ["flatpak install --noninteractive --user flathub app.zen_browser.zen"]
        );
    }

    #[test]
    fn installs_from_the_system_nixpkgs_with_the_new_profile_verb() {
        let mut f = runner(&[(
            "nix --extra-experimental-features nix-command flakes search",
            Ok(HTOP),
        )]);
        assert!(install("htop", &args(&["htop"]), &mut f));
        assert_eq!(
            f.ran,
            ["nix --extra-experimental-features nix-command flakes profile add nixpkgs#htop"]
        );
    }

    #[test]
    fn dry_run_changes_nothing() {
        let mut f = runner(&[]);
        assert!(install("zen", &args(&["--dry-run", "zen"]), &mut f));
        assert!(f.ran.is_empty());
    }

    #[test]
    fn already_installed_apps_are_left_alone() {
        let mut f = runner(&[("flatpak list", Ok("app.zen_browser.zen\tZen Browser\n"))]);
        assert!(install("zen-browser", &args(&["zen-browser"]), &mut f));
        assert!(f.ran.is_empty());
    }

    #[test]
    fn remove_finds_the_source_it_came_from() {
        let mut f = runner(&[("flatpak list", Ok("app.zen_browser.zen\tZen Browser\n"))]);
        assert!(remove(
            "zen browser",
            &args(&["remove", "zen browser"]),
            &mut f
        ));
        assert_eq!(
            f.ran,
            ["flatpak uninstall --noninteractive --user app.zen_browser.zen"]
        );

        let mut f = runner(&[]);
        assert!(!remove("htop", &args(&["remove", "htop"]), &mut f));
    }
}
