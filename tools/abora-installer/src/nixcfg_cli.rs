use std::ffi::OsString;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use crate::nixcfg::Settings;

pub const USAGE: &str = "\
Usage:
  abora-installer config write [--target <dir>] < settings

Reads the installer's choices as key=value lines on stdin and writes
<target>/etc/nixos/{configuration.nix,abora-local.nix} (and anix.nix when
anix=yes; removes it otherwise). Every setting is required and unknown ones
are refused, so a typo can't silently fall back to a default.";

fn write_atomic(path: &Path, contents: &str, mode: u32) -> Result<(), String> {
    let tmp = path.with_extension("abora-tmp");
    fs::write(&tmp, contents).map_err(|e| format!("could not write {}: {e}", tmp.display()))?;
    fs::set_permissions(&tmp, fs::Permissions::from_mode(mode)).map_err(|e| format!("could not set the mode of {}: {e}", tmp.display()))?;
    fs::rename(&tmp, path).map_err(|e| format!("could not write {}: {e}", path.display()))
}

pub fn run(raw: &[OsString]) -> Result<u8, String> {
    let args: Vec<String> = raw.iter().map(|a| a.to_string_lossy().into_owned()).collect();
    match args.first().map(String::as_str) {
        Some("write") => {
            let target = match args.get(1..).unwrap_or_default() {
                [] => "/mnt".to_string(),
                [flag, dir] if flag == "--target" => dir.clone(),
                _ => return Err("config write takes only --target <dir>".into()),
            };
            let mut text = String::new();
            std::io::Read::read_to_string(&mut std::io::stdin(), &mut text).map_err(|e| format!("could not read the settings: {e}"))?;
            write(&Settings::parse(&text)?, Path::new(&target))?;
            Ok(0)
        }
        Some("-h" | "--help") => {
            println!("{USAGE}");
            Ok(0)
        }
        Some(other) => Err(format!("unknown config action: {other}")),
        None => Err("config needs an action: write".into()),
    }
}

pub fn write(settings: &Settings, target: &Path) -> Result<(), String> {
    let dir = target.join("etc/nixos");
    fs::create_dir_all(&dir).map_err(|e| format!("could not create {}: {e}", dir.display()))?;
    if settings.anix_enabled() {
        write_atomic(&dir.join("anix.nix"), &settings.anix_nix(), 0o644)?;
    } else {
        let _ = fs::remove_file(dir.join("anix.nix"));
    }
    write_atomic(&dir.join("configuration.nix"), &settings.configuration_nix(), 0o644)?;
    // No secret in it (the hashes live under /var/lib/abora/secrets), so the
    // user's tools can read it.
    write_atomic(&dir.join("abora-local.nix"), &settings.abora_local_nix(), 0o644)
}
