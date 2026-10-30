use std::ffi::OsString;
use std::fs;
use std::path::Path;

use crate::disk::ROOT_LABEL;
use crate::flake::{self, Machine};

pub const USAGE: &str = "\
Usage:
  abora-installer flake check <flake>[#<config>]
  abora-installer flake judge --uefi <yes|no> --bios-boot <yes|no> < inspection
  abora-installer flake write --flake <flake> --host <config> --esp-uuid <uuid>
                              [--bios-disk <disk>] [--target <dir>]
  abora-installer flake write-installed --branch <nixos-branch> [--target <dir>]
  abora-installer flake audit <file>...

check  validate a flake reference; prints url=<url> and host=<config or empty>
judge  read the configuration's key=value inspection on stdin; print
       refuse=<reason> / warn=<note> lines, exit 1 if anything is refused
write  write <target>/etc/nixos/{flake.nix,abora-machine.nix,README-abora.md}
       so <config> is installed with this machine's hardware and partitions
       (expects <target>/etc/nixos/hardware-configuration.nix next to them)
write-installed
       write <target>/etc/nixos/flake.nix for a plain Abora install following
       <nixos-branch>, and <target>/etc/nixos/abora/nixos-release
audit  print every line of the given files that points at a path on the
       installer (nixpkgs, /etc/abora, /mnt/etc/nixos); exit 1 if any";

fn write_atomic(path: &Path, contents: &str) -> Result<(), String> {
    let tmp = path.with_extension("abora-tmp");
    fs::write(&tmp, contents).map_err(|e| format!("could not write {}: {e}", tmp.display()))?;
    fs::rename(&tmp, path).map_err(|e| format!("could not write {}: {e}", path.display()))
}

pub fn run(raw: &[OsString]) -> Result<u8, String> {
    let args: Vec<String> = raw
        .iter()
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    match args.first().map(String::as_str) {
        Some("check") => {
            let [_, reference] = args.as_slice() else {
                return Err("flake check needs exactly one flake reference".into());
            };
            let parsed = flake::parse_ref(reference)?;
            println!("url={}", parsed.url);
            println!("host={}", parsed.host.unwrap_or_default());
            Ok(0)
        }
        Some("judge") => {
            let flag = |name: &str| -> Result<bool, String> {
                match option(&args[1..], name)?.as_deref() {
                    Some("yes") => Ok(true),
                    Some("no") => Ok(false),
                    _ => Err(format!("{name} must be yes or no")),
                }
            };
            let (uefi, bios_boot) = (flag("--uefi")?, flag("--bios-boot")?);
            let mut text = String::new();
            std::io::Read::read_to_string(&mut std::io::stdin(), &mut text)
                .map_err(|e| format!("could not read the inspection: {e}"))?;
            let verdict = flake::judge(&flake::Inspection::parse(&text), uefi, bios_boot);
            for reason in &verdict.refusals {
                println!("refuse={reason}");
            }
            for note in &verdict.warnings {
                println!("warn={note}");
            }
            Ok(u8::from(!verdict.refusals.is_empty()))
        }
        Some("write") => {
            let machine = parse_write(&args[1..])?;
            let target = option(&args[1..], "--target")?.unwrap_or_else(|| "/mnt".into());
            write(&machine, Path::new(&target))?;
            Ok(0)
        }
        Some("write-installed") => {
            let branch = option(&args[1..], "--branch")?.ok_or("write-installed needs --branch")?;
            let target = option(&args[1..], "--target")?.unwrap_or_else(|| "/mnt".into());
            let text = flake::installed_flake_nix(&branch)?;
            let dir = Path::new(&target).join("etc/nixos");
            fs::create_dir_all(dir.join("abora")).map_err(|e| format!("could not create {}: {e}", dir.display()))?;
            write_atomic(&dir.join("flake.nix"), &text)?;
            write_atomic(&dir.join("abora/nixos-release"), &format!("{branch}\n"))?;
            Ok(0)
        }
        Some("audit") => {
            let mut found = false;
            for file in &args[1..] {
                let text = fs::read_to_string(file).map_err(|e| format!("could not read {file}: {e}"))?;
                for line in flake::local_path_lines(&text) {
                    println!("{file}: {line}");
                    found = true;
                }
            }
            Ok(u8::from(found))
        }
        Some("-h" | "--help") => {
            println!("{USAGE}");
            Ok(0)
        }
        Some(other) => Err(format!("unknown flake action: {other}")),
        None => Err("flake needs an action: check, judge, write, write-installed or audit".into()),
    }
}

fn option(args: &[String], name: &str) -> Result<Option<String>, String> {
    let mut found = None;
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if !arg.starts_with("--") {
            return Err(format!("unexpected argument: {arg}"));
        }
        let value = iter.next().ok_or(format!("{arg} needs a value"))?;
        if arg == name {
            found = Some(value.clone());
        } else if ![
            "--flake",
            "--host",
            "--esp-uuid",
            "--bios-disk",
            "--target",
            "--uefi",
            "--bios-boot",
            "--branch",
        ]
        .contains(&arg.as_str())
        {
            return Err(format!("unknown option: {arg}"));
        }
    }
    Ok(found)
}

fn parse_write(args: &[String]) -> Result<Machine, String> {
    let need = |name: &str| option(args, name)?.ok_or(format!("missing {name}"));
    let flake = flake::parse_ref(&need("--flake")?)?;
    let host = match option(args, "--host")? {
        Some(host) => host,
        None => flake.host.clone().ok_or("missing --host")?,
    };
    let machine = Machine {
        flake,
        host,
        root_label: ROOT_LABEL.to_string(),
        esp_uuid: need("--esp-uuid")?,
        bios_disk: option(args, "--bios-disk")?.filter(|d| !d.is_empty()),
    };
    machine.validate()?;
    Ok(machine)
}

pub fn write(machine: &Machine, target: &Path) -> Result<(), String> {
    let dir = target.join("etc/nixos");
    if !dir.join("hardware-configuration.nix").is_file() {
        return Err(format!(
            "{} is missing; run nixos-generate-config first",
            dir.join("hardware-configuration.nix").display()
        ));
    }
    write_atomic(&dir.join("abora-machine.nix"), &machine.machine_nix())?;
    write_atomic(&dir.join("README-abora.md"), &machine.readme())?;
    // Last, so a half-written set never looks like a finished one.
    write_atomic(&dir.join("flake.nix"), &machine.flake_nix())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strings(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn host_comes_from_the_reference_when_not_given() {
        let m = parse_write(&strings(&[
            "--flake",
            "github:me/cfg#desk",
            "--esp-uuid",
            "AB-12",
        ]))
        .unwrap();
        assert_eq!(m.host, "desk");
        assert_eq!(m.flake.url, "github:me/cfg");
        assert_eq!(m.bios_disk, None);
    }

    #[test]
    fn write_needs_a_host_and_rejects_unknown_options() {
        assert!(parse_write(&strings(&["--flake", "github:me/cfg", "--esp-uuid", "AB"])).is_err());
        assert!(parse_write(&strings(&[
            "--flake",
            "github:me/cfg#d",
            "--esp-uuid",
            "AB",
            "--force",
            "x"
        ]))
        .is_err());
    }

    #[test]
    fn writes_all_three_files_next_to_the_hardware_config() {
        let target = std::env::temp_dir().join(format!("abora-flake-test-{}", std::process::id()));
        let dir = target.join("etc/nixos");
        fs::create_dir_all(&dir).unwrap();
        let m = parse_write(&strings(&[
            "--flake",
            "github:me/cfg#desk",
            "--esp-uuid",
            "AB-12",
        ]))
        .unwrap();

        assert!(write(&m, &target)
            .unwrap_err()
            .contains("nixos-generate-config"));
        fs::write(dir.join("hardware-configuration.nix"), "{ }\n").unwrap();
        write(&m, &target).unwrap();
        for file in ["flake.nix", "abora-machine.nix", "README-abora.md"] {
            assert!(dir.join(file).is_file(), "{file} missing");
        }
        assert!(fs::read_to_string(dir.join("flake.nix"))
            .unwrap()
            .contains("\"desk\""));
        fs::remove_dir_all(&target).unwrap();
    }
}

#[cfg(test)]
mod engine_tests {
    use super::*;

    fn run_args(args: &[&str]) -> Result<u8, String> {
        let raw: Vec<OsString> = args.iter().map(OsString::from).collect();
        run(&raw)
    }

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("abora-flake-cli-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn write_installed_writes_the_flake_and_the_release_marker() {
        let root = scratch("write");
        let target = root.to_str().unwrap();
        assert_eq!(run_args(&["write-installed", "--branch", "nixos-26.05", "--target", target]).unwrap(), 0);
        let flake = fs::read_to_string(root.join("etc/nixos/flake.nix")).unwrap();
        assert!(flake.contains("github:NixOS/nixpkgs/nixos-26.05"));
        assert_eq!(fs::read_to_string(root.join("etc/nixos/abora/nixos-release")).unwrap(), "nixos-26.05\n");
        // Hostile branch names are refused before anything is written.
        let other = scratch("refuse");
        let err = run_args(&["write-installed", "--branch", "x\"; evil", "--target", other.to_str().unwrap()]).unwrap_err();
        assert!(err.contains("not a NixOS release branch"), "{err}");
        assert!(!other.join("etc/nixos/flake.nix").exists());
        assert!(run_args(&["write-installed", "--target", target]).is_err(), "--branch is required");
        let _ = fs::remove_dir_all(root);
        let _ = fs::remove_dir_all(other);
    }

    #[test]
    fn audit_exits_one_only_when_a_local_path_is_present() {
        let dir = scratch("audit");
        let clean = dir.join("clean");
        let dirty = dir.join("dirty");
        fs::write(&clean, "url = \"github:NixOS/nixpkgs/nixos-26.05\";\n").unwrap();
        fs::write(&dirty, "url = \"path:/etc/abora/nixpkgs\";\n").unwrap();
        assert_eq!(run_args(&["audit", clean.to_str().unwrap()]).unwrap(), 0);
        assert_eq!(run_args(&["audit", clean.to_str().unwrap(), dirty.to_str().unwrap()]).unwrap(), 1);
        assert!(run_args(&["audit", dir.join("missing").to_str().unwrap()]).is_err());
        let _ = fs::remove_dir_all(dir);
    }
}
