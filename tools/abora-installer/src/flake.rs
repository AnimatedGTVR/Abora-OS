//! "Install from your own flake": the user's NixOS configuration is installed
//! through a small wrapper flake that adds only what this machine needs.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlakeRef {
    /// The flake URL without the `#host` part, e.g. `github:me/nixos`.
    pub url: String,
    /// The `nixosConfigurations` attribute, if the user named one.
    pub host: Option<String>,
}

const URL_SCHEMES: &[&str] = &[
    "github:",
    "gitlab:",
    "sourcehut:",
    "git+https://",
    "git+ssh://",
    "git+http://",
    "https://",
    "http://",
    "flake:",
];

fn url_char_ok(c: char) -> bool {
    c.is_ascii_alphanumeric() || "-._~:/?=&@%+,".contains(c)
}

pub fn host_ok(host: &str) -> bool {
    !host.is_empty()
        && host.len() <= 128
        && host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "-_.".contains(c))
}

/// The URL and host end up inside Nix strings, so only a conservative
/// character set is accepted: no quotes, `$`, braces, backslashes or spaces.
pub fn parse_ref(input: &str) -> Result<FlakeRef, String> {
    let input = input.trim();
    if input.is_empty() {
        return Err("enter a flake, e.g. github:you/nixos-config#laptop".into());
    }
    let (url, host) = match input.rsplit_once('#') {
        Some((url, host)) => (url, Some(host)),
        None => (input, None),
    };

    if url.starts_with("path:") || url.starts_with('/') || url.starts_with('.') {
        return Err(
            "local paths are not supported: the installed system could not find them again. \
             Push the flake to a Git host (github:, gitlab:, git+https://) and use that."
                .into(),
        );
    }
    if !URL_SCHEMES.iter().any(|scheme| url.starts_with(scheme)) {
        return Err(format!(
            "unsupported flake reference '{url}'; use github:, gitlab:, sourcehut:, git+https://, git+ssh:// or https://"
        ));
    }
    if let Some(bad) = url.chars().find(|&c| !url_char_ok(c)) {
        return Err(format!(
            "flake reference contains an unsupported character: {bad:?}"
        ));
    }
    if url.len() > 512 {
        return Err("flake reference is too long".into());
    }

    let host = match host {
        None | Some("") => None,
        Some(raw) => {
            let host = raw.strip_prefix("nixosConfigurations.").unwrap_or(raw);
            if !host_ok(host) {
                return Err(format!(
                    "configuration name '{host}' may only use letters, digits, '-', '_' and '.'"
                ));
            }
            Some(host.to_string())
        }
    };

    Ok(FlakeRef {
        url: url.to_string(),
        host,
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Machine {
    pub flake: FlakeRef,
    pub host: String,
    pub root_label: String,
    pub esp_uuid: String,
    /// Whole disk for a BIOS GRUB install; `None` when the disk has no BIOS-boot partition.
    pub bios_disk: Option<String>,
}

fn uuid_ok(uuid: &str) -> bool {
    !uuid.is_empty() && uuid.len() <= 64 && uuid.chars().all(|c| c.is_ascii_hexdigit() || c == '-')
}

fn disk_ok(disk: &str) -> bool {
    disk.starts_with("/dev/")
        && disk
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "/-_.:".contains(c))
}

impl Machine {
    pub fn validate(&self) -> Result<(), String> {
        parse_ref(&self.flake.url)?;
        if !host_ok(&self.host) {
            return Err(format!("invalid configuration name '{}'", self.host));
        }
        if !host_ok(&self.root_label) {
            return Err(format!("invalid root label '{}'", self.root_label));
        }
        if !uuid_ok(&self.esp_uuid) {
            return Err(format!("invalid EFI partition UUID '{}'", self.esp_uuid));
        }
        if let Some(disk) = &self.bios_disk {
            if !disk_ok(disk) {
                return Err(format!("invalid disk '{disk}'"));
            }
        }
        Ok(())
    }

    pub fn flake_nix(&self) -> String {
        format!(
            r#"# Written by the Abora installer: your configuration, plus this machine.
# Update your config with `nix flake update config` here, then
# `nixos-rebuild switch --flake /etc/nixos#abora`. See README-abora.md.
{{
  description = "{host} from {url}, installed by Abora";
  inputs.config.url = "{url}";
  outputs = {{ config, ... }}: {{
    nixosConfigurations.abora = config.nixosConfigurations."{host}".extendModules {{
      modules = [ ./abora-machine.nix ];
    }};
  }};
}}
"#,
            host = self.host,
            url = self.flake.url,
        )
    }

    pub fn machine_nix(&self) -> String {
        let grub_device = match &self.bios_disk {
            Some(disk) => format!(
                r#"
  # BIOS GRUB has to be written to the disk this installer partitioned.
  boot.loader.grub.devices = lib.mkIf
    (config.boot.loader.grub.enable && !config.boot.loader.grub.efiSupport)
    (lib.mkForce [ "{disk}" ]);
"#
            ),
            None => String::new(),
        };
        format!(
            r#"# Written by the Abora installer for this machine: hardware, and the
# partitions the installer created. Keep this file (and
# hardware-configuration.nix) if you move this host into your own repo.
{{ config, lib, ... }}:
{{
  imports = [ ./hardware-configuration.nix ];

  fileSystems."/" = lib.mkForce {{
    device = "/dev/disk/by-label/{label}";
    fsType = "ext4";
  }};
  fileSystems."/boot" = lib.mkForce {{
    device = "/dev/disk/by-uuid/{uuid}";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  }};
  boot.loader.efi.efiSysMountPoint = lib.mkForce "/boot";
{grub_device}}}
"#,
            label = self.root_label,
            uuid = self.esp_uuid,
        )
    }

    pub fn readme(&self) -> String {
        format!(
            "# This system was installed from your own flake\n\
             \n\
             Source: `{url}#{host}`\n\
             \n\
             `/etc/nixos/flake.nix` wraps that configuration and adds `abora-machine.nix`\n\
             (this machine's hardware and partitions).\n\
             \n\
             - Rebuild: `sudo nixos-rebuild switch --flake /etc/nixos#abora`\n\
             - Pick up new commits of your config: `sudo nix flake update config --flake /etc/nixos`, then rebuild\n\
             - To rebuild from your own repo instead, copy `abora-machine.nix` and\n\
               `hardware-configuration.nix` into it and import `abora-machine.nix` from the\n\
               `{host}` configuration. Without them this machine will not find its disks.\n\
             \n\
             Abora's own tools (`abora`, `anix`, updates) are not part of this install unless\n\
             your configuration imports them.\n",
            url = self.flake.url,
            host = self.host,
        )
    }
}

/// The nixpkgs branch an installed system follows: `nixos-unstable` or a
/// release like `nixos-26.05`. Anything else could escape the Nix string it
/// is written into, so it is refused.
pub fn branch_ok(branch: &str) -> bool {
    if branch == "nixos-unstable" {
        return true;
    }
    let Some(version) = branch.strip_prefix("nixos-") else {
        return false;
    };
    let Some((year, month)) = version.split_once('.') else {
        return false;
    };
    year.len() == 2
        && month.len() == 2
        && year
            .bytes()
            .chain(month.bytes())
            .all(|b| b.is_ascii_digit())
}

/// The `flake.nix` of a plain Abora install on a nixpkgs branch.
pub fn installed_flake_nix(branch: &str) -> Result<String, String> {
    if !branch_ok(branch) {
        return Err(format!(
            "{branch:?} is not a NixOS release branch (expected nixos-unstable or nixos-YY.MM)"
        ));
    }
    Ok(format!(
        r#"{{
  description = "Abora installed system";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/{branch}";
  outputs = {{ nixpkgs, ... }}: {{
    nixosConfigurations = {{
      abora = nixpkgs.lib.nixosSystem {{
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
        ];
      }};
    }};
  }};
}}
"#
    ))
}

/// Lines that point a flake at a path on the installer instead of the network:
/// those would break the installed system the moment the ISO is gone.
pub fn local_path_lines(text: &str) -> Vec<String> {
    text.lines()
        .filter(|line| {
            let Some(at) = line.find("path:") else {
                return false;
            };
            let rest = &line[at..];
            ["nixpkgs", "/etc/abora", "/mnt/etc/nixos"]
                .iter()
                .any(|needle| rest.contains(needle))
        })
        .map(|line| line.trim().to_string())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_real_release_branches_are_accepted() {
        for ok in ["nixos-unstable", "nixos-26.05", "nixos-25.11"] {
            assert!(branch_ok(ok), "{ok}");
        }
        for bad in [
            "",
            "nixos-",
            "nixos-26.5",
            "nixos-2605",
            "nixos-26.05\"; evil",
            "master",
            "nixos-26.05/../x",
            "nixos-ab.cd",
            "../nixos-26.05",
            "nixos-unstable ",
        ] {
            assert!(!branch_ok(bad), "{bad:?}");
        }
        assert!(installed_flake_nix("nixos-26.05\"; rm -rf /").is_err());
    }

    #[test]
    fn installed_flake_follows_the_branch_and_keeps_its_shape() {
        let text = installed_flake_nix("nixos-26.05").unwrap();
        assert!(text.contains("inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixos-26.05\";"));
        assert!(
            text.contains("abora = nixpkgs.lib.nixosSystem {")
                && text.contains("./configuration.nix")
        );
        assert_eq!(
            text.matches('{').count(),
            text.matches('}').count(),
            "braces balance"
        );
        assert!(text.starts_with("{\n") && text.ends_with("}\n"));
    }

    #[test]
    fn local_paths_are_found_but_network_inputs_are_fine() {
        let bad =
            "inputs.nixpkgs.url = \"path:/nix/store/abc-nixpkgs\";\n  x = \"path:/etc/abora/y\";";
        assert_eq!(local_path_lines(bad).len(), 2);
        assert!(
            local_path_lines("inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixos-26.05\";\n")
                .is_empty()
        );
        assert!(local_path_lines("# path: of the problem, but nothing local").is_empty());
    }

    #[test]
    fn splits_url_and_host() {
        let r = parse_ref("github:me/nixos-config#laptop").unwrap();
        assert_eq!(r.url, "github:me/nixos-config");
        assert_eq!(r.host.as_deref(), Some("laptop"));

        let r = parse_ref("  git+https://git.example.org/me/cfg?ref=main  ").unwrap();
        assert_eq!(r.url, "git+https://git.example.org/me/cfg?ref=main");
        assert_eq!(r.host, None);

        let r = parse_ref("github:me/cfg#nixosConfigurations.desk").unwrap();
        assert_eq!(r.host.as_deref(), Some("desk"));
    }

    #[test]
    fn rejects_anything_that_could_escape_a_nix_string() {
        for bad in [
            "github:me/cfg\"; evil = true; #",
            "github:me/${builtins.abort \"x\"}",
            "github:me/cfg#lap\"top",
            "github:me/cfg#lap top",
            "github:me/c\\fg",
            "github:me/{cfg}",
            "github:me/cfg\n#x",
        ] {
            assert!(parse_ref(bad).is_err(), "accepted {bad:?}");
        }
    }

    #[test]
    fn rejects_local_paths_and_unknown_schemes() {
        assert!(parse_ref("path:/run/media/usb/cfg")
            .unwrap_err()
            .contains("Git host"));
        assert!(parse_ref("/etc/nixos").is_err());
        assert!(parse_ref(".#laptop").is_err());
        assert!(parse_ref("ftp://example.org/cfg").is_err());
        assert!(parse_ref("").is_err());
    }

    fn machine(bios_disk: Option<&str>) -> Machine {
        Machine {
            flake: parse_ref("github:me/cfg").unwrap(),
            host: "laptop".into(),
            root_label: "ABORA_ROOT".into(),
            esp_uuid: "ABCD-1234".into(),
            bios_disk: bios_disk.map(str::to_string),
        }
    }

    #[test]
    fn wrapper_extends_the_named_configuration() {
        let m = machine(None);
        m.validate().unwrap();
        let flake = m.flake_nix();
        assert!(flake.contains(r#"inputs.config.url = "github:me/cfg";"#));
        assert!(flake.contains(r#"config.nixosConfigurations."laptop".extendModules"#));
        assert!(flake.contains("nixosConfigurations.abora ="));
        assert!(flake.contains("./abora-machine.nix"));
    }

    #[test]
    fn machine_module_pins_this_disk() {
        let uefi = machine(None).machine_nix();
        assert!(uefi.contains("/dev/disk/by-label/ABORA_ROOT"));
        assert!(uefi.contains("/dev/disk/by-uuid/ABCD-1234"));
        assert!(uefi.contains(r#"efiSysMountPoint = lib.mkForce "/boot""#));
        assert!(!uefi.contains("grub.devices"));

        let bios = machine(Some("/dev/disk/by-id/ata-Disk_123")).machine_nix();
        assert!(bios.contains(r#"(lib.mkForce [ "/dev/disk/by-id/ata-Disk_123" ])"#));
    }

    #[test]
    fn validate_rejects_bad_machine_values() {
        let mut m = machine(None);
        m.esp_uuid = "x\"y".into();
        assert!(m.validate().is_err());
        let mut m = machine(Some("/dev/sda\"; x"));
        assert!(m.validate().is_err());
        m.bios_disk = None;
        m.host = "a b".into();
        assert!(m.validate().is_err());
    }
}

/// What the installer learned from evaluating the user's configuration
/// (`key=value` lines; see `INSPECT_EXPR` in the installer script).
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Inspection {
    pub system: String,
    pub systemd_boot: bool,
    pub grub: bool,
    pub grub_efi: bool,
    pub limine: bool,
    /// Mount points other than / and /boot that boot will wait for.
    pub extra_mounts: Vec<String>,
}

impl Inspection {
    pub fn parse(text: &str) -> Self {
        let mut found = Self::default();
        for line in text.lines() {
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            let yes = value.trim() == "1" || value.trim() == "true";
            match key.trim() {
                "system" => found.system = value.trim().to_string(),
                "systemd_boot" => found.systemd_boot = yes,
                "grub" => found.grub = yes,
                "grub_efi" => found.grub_efi = yes,
                "limine" => found.limine = yes,
                "extra_mounts" => {
                    found.extra_mounts = value.split_whitespace().map(str::to_string).collect()
                }
                _ => {}
            }
        }
        found
    }
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Verdict {
    pub refusals: Vec<String>,
    pub warnings: Vec<String>,
}

/// Decides whether the configuration can boot on this machine and disk.
pub fn judge(found: &Inspection, uefi: bool, has_bios_boot_partition: bool) -> Verdict {
    let mut v = Verdict::default();
    if found.system != "x86_64-linux" {
        let shown = if found.system.is_empty() {
            "unknown"
        } else {
            &found.system
        };
        v.refusals.push(format!(
            "this configuration is for {shown}, but this machine is x86_64-linux"
        ));
    }

    let bios_grub = found.grub && !found.grub_efi;
    let uefi_loader = found.systemd_boot || found.limine || (found.grub && found.grub_efi);
    let bios_loader = bios_grub || found.limine;
    if !found.systemd_boot && !found.grub && !found.limine {
        v.refusals.push(
            "the configuration enables no bootloader; set boot.loader.systemd-boot.enable (UEFI) \
             or boot.loader.grub.enable"
                .into(),
        );
    } else if uefi && !uefi_loader {
        v.refusals.push(
            "this machine boots in UEFI mode, but the configuration only installs BIOS GRUB; \
             set boot.loader.grub.efiSupport = true or use systemd-boot"
                .into(),
        );
    } else if !uefi && !bios_loader {
        v.refusals.push(
            "this machine boots in legacy BIOS mode, but the configuration's bootloader needs UEFI; \
             use boot.loader.grub without efiSupport"
                .into(),
        );
    }
    if !uefi && bios_grub && !has_bios_boot_partition {
        v.refusals.push(
            "BIOS GRUB needs a BIOS-boot partition, and the chosen partition mode keeps the disk's \
             table as it is; use \"Erase entire disk\""
                .into(),
        );
    }

    if !found.extra_mounts.is_empty() {
        v.warnings.push(format!(
            "the configuration also mounts {}; those devices must exist on this machine or boot \
             stops in emergency mode (add \"nofail\" to their options if they are optional)",
            found.extra_mounts.join(", ")
        ));
    }
    v
}

#[cfg(test)]
mod judge_tests {
    use super::*;

    fn found(text: &str) -> Inspection {
        Inspection::parse(text)
    }

    #[test]
    fn parses_the_inspection_lines() {
        let f =
            found("system=x86_64-linux\nsystemd_boot=1\ngrub=0\nextra_mounts=/home /srv\nnoise\n");
        assert_eq!(f.system, "x86_64-linux");
        assert!(f.systemd_boot && !f.grub);
        assert_eq!(f.extra_mounts, vec!["/home", "/srv"]);
    }

    #[test]
    fn systemd_boot_on_uefi_is_fine() {
        let v = judge(&found("system=x86_64-linux\nsystemd_boot=1"), true, false);
        assert_eq!(v, Verdict::default());
    }

    #[test]
    fn refuses_wrong_arch_and_missing_bootloader() {
        let v = judge(&found("system=aarch64-linux\n"), true, true);
        assert_eq!(v.refusals.len(), 2);
        assert!(v.refusals[0].contains("aarch64-linux"));
        assert!(v.refusals[1].contains("no bootloader"));
    }

    #[test]
    fn firmware_and_bootloader_must_match() {
        let bios_grub = found("system=x86_64-linux\ngrub=1\ngrub_efi=0");
        assert!(judge(&bios_grub, true, true).refusals[0].contains("UEFI mode"));
        assert!(judge(&bios_grub, false, true).refusals.is_empty());
        assert!(judge(&bios_grub, false, false).refusals[0].contains("BIOS-boot partition"));

        let sd = found("system=x86_64-linux\nsystemd_boot=1");
        assert!(judge(&sd, false, true).refusals[0].contains("legacy BIOS"));

        let efi_grub = found("system=x86_64-linux\ngrub=1\ngrub_efi=1");
        assert!(judge(&efi_grub, true, false).refusals.is_empty());
        let limine = found("system=x86_64-linux\nlimine=1");
        assert!(judge(&limine, false, true).refusals.is_empty());
    }

    #[test]
    fn extra_mounts_are_a_warning_not_a_refusal() {
        let v = judge(
            &found("system=x86_64-linux\nsystemd_boot=1\nextra_mounts=/home"),
            true,
            false,
        );
        assert!(v.refusals.is_empty());
        assert!(v.warnings[0].contains("/home"));
    }
}
