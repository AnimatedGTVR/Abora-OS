use std::collections::HashSet;
use std::ffi::OsString;
use std::path::PathBuf;

use crate::config;
use crate::disk::{self, Host, Layout};
use crate::system::{DryRunHost, RealHost};

pub const USAGE: &str = "\
Usage:
  abora-installer disk erase <disk> [options]
  abora-installer disk existing <disk> --root <partition> --esp <partition> [options]
  abora-installer disk mount --root <partition> --efi <partition> [options]

erase     wipe <disk>: BIOS-boot + 512 MiB ESP + ext4 root (ABORA_ROOT)
existing  format only --root as ext4 and reuse --esp unformatted (dual boot)
mount     mount --root at the target and --efi at <target>/boot

erase and existing print the resulting layout as efi=<path> and root=<path>.

Options:
  --target <dir>  Install target (default /mnt)
  --log <path>    Command log (default $ABORA_INSTALL_LOG or /tmp/abora-install.log)
  --dry-run       Read the disks, print the commands, change nothing";

#[derive(Debug, Default, PartialEq, Eq)]
pub struct DiskArgs {
    pub action: String,
    pub disk: Option<String>,
    pub root: Option<String>,
    pub esp: Option<String>,
    pub target: String,
    pub log: Option<PathBuf>,
    pub dry_run: bool,
}

pub fn parse(args: &[OsString]) -> Result<DiskArgs, String> {
    let mut iter = args.iter().map(|a| a.to_string_lossy().into_owned());
    let action = iter
        .next()
        .ok_or("disk needs an action: erase, existing or mount")?;
    if !matches!(
        action.as_str(),
        "erase" | "existing" | "mount" | "-h" | "--help"
    ) {
        return Err(format!("unknown disk action: {action}"));
    }
    let mut parsed = DiskArgs {
        action,
        target: "/mnt".into(),
        ..DiskArgs::default()
    };
    while let Some(arg) = iter.next() {
        let mut value = |name: &str| iter.next().ok_or(format!("{name} needs a value"));
        match arg.as_str() {
            "--root" => parsed.root = Some(value("--root")?),
            "--esp" | "--efi" => parsed.esp = Some(value(&arg)?),
            "--target" => parsed.target = value("--target")?,
            "--log" => parsed.log = Some(PathBuf::from(value("--log")?)),
            "--dry-run" => parsed.dry_run = true,
            "-h" | "--help" => parsed.action = "--help".into(),
            flag if flag.starts_with('-') => return Err(format!("unknown option: {flag}")),
            _ if parsed.disk.is_none() => parsed.disk = Some(arg),
            _ => return Err(format!("unexpected argument: {arg}")),
        }
    }
    if !parsed.target.starts_with('/') || parsed.target == "/" {
        return Err(format!(
            "--target must be an absolute path other than /: {}",
            parsed.target
        ));
    }
    Ok(parsed)
}

fn required<'a>(value: &'a Option<String>, what: &str) -> Result<&'a str, String> {
    value.as_deref().ok_or(format!("missing {what}"))
}

pub fn run(raw: &[OsString]) -> Result<u8, String> {
    let args = parse(raw)?;
    if args.action == "--help" {
        println!("{USAGE}");
        return Ok(0);
    }

    let mut host: Box<dyn Host> = if args.dry_run {
        let mut planned = HashSet::new();
        if let (Some(disk), "erase") = (&args.disk, args.action.as_str()) {
            planned.insert(disk::partition_path(disk, 2));
            planned.insert(disk::partition_path(disk, 3));
        }
        Box::new(DryRunHost { planned })
    } else {
        Box::new(RealHost::new(
            args.log.clone().unwrap_or_else(config::log_path),
        ))
    };
    let host = host.as_mut();

    match args.action.as_str() {
        "erase" => {
            let layout = disk::erase(host, required(&args.disk, "<disk>")?, &args.target)?;
            print!("{}", layout.render());
        }
        "existing" => {
            let layout = disk::existing(
                host,
                required(&args.disk, "<disk>")?,
                required(&args.root, "--root")?,
                required(&args.esp, "--esp")?,
                &args.target,
            )?;
            print!("{}", layout.render());
        }
        _ => {
            let layout = Layout {
                root: required(&args.root, "--root")?.to_string(),
                efi: required(&args.esp, "--efi")?.to_string(),
            };
            disk::mount(host, &layout, &args.target)?;
        }
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(items: &[&str]) -> Vec<OsString> {
        items.iter().map(OsString::from).collect()
    }

    #[test]
    fn parses_existing_with_all_options() {
        let parsed = parse(&args(&[
            "existing",
            "/dev/sda",
            "--root",
            "/dev/sda4",
            "--esp",
            "/dev/sda1",
            "--target",
            "/target",
            "--dry-run",
        ]))
        .unwrap();
        assert_eq!(parsed.disk.as_deref(), Some("/dev/sda"));
        assert_eq!(parsed.root.as_deref(), Some("/dev/sda4"));
        assert_eq!(parsed.esp.as_deref(), Some("/dev/sda1"));
        assert_eq!(parsed.target, "/target");
        assert!(parsed.dry_run);
    }

    #[test]
    fn rejects_unknown_actions_and_unsafe_targets() {
        assert!(parse(&args(&["format", "/dev/sda"])).is_err());
        assert!(parse(&args(&["erase", "/dev/sda", "--target", "/"])).is_err());
        assert!(parse(&args(&["erase", "/dev/sda", "--target", "mnt"])).is_err());
        assert!(parse(&args(&["erase", "/dev/sda", "/dev/sdb"])).is_err());
        assert!(parse(&args(&["erase", "/dev/sda", "--force"])).is_err());
    }

    #[test]
    fn missing_disk_is_an_error_not_a_default() {
        assert_eq!(
            run(&args(&["erase", "--dry-run"])).unwrap_err(),
            "missing <disk>"
        );
    }
}
