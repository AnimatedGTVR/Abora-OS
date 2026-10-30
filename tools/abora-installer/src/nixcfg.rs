//! The Nix files an install writes to /etc/nixos: configuration.nix,
//! abora-local.nix and (when ANIX is on) anix.nix.
//!
//! Every value that ends up inside a Nix string goes through `nix_string`, so
//! a hostname or disk name can never close the string or start `${...}`.

use std::collections::BTreeMap;

/// Escapes text for the inside of a double-quoted Nix string. Matches the
/// installer's old Bash helper exactly: `\`, `$` and `"` are escaped and
/// newlines dropped.
pub fn nix_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '$' => out.push_str("\\$"),
            '"' => out.push_str("\\\""),
            '\n' => {}
            c => out.push(c),
        }
    }
    out
}

/// `yes`, `true` and `1` are true; anything else is false.
pub fn nix_bool(value: &str) -> &'static str {
    match value {
        "yes" | "true" | "1" => "true",
        _ => "false",
    }
}

const KEYS: &[&str] = &[
    "hostname", "locale", "timezone", "keyboard", "xkb", "desktop", "wallpaper", "gpu", "disk", "disk_mode", "user", "anix", "root_hash",
    "secrets_dir", "labs", "minimal", "gaming_enabled", "gaming_steam", "gaming_big_picture", "gaming_autostart", "gaming_gamescope",
    "gaming_vulkan", "gaming_controller", "gaming_mangohud", "gaming_gamemode", "gaming_launchers",
];

/// What the installer decided, as `key=value` lines.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Settings(BTreeMap<String, String>);

impl Settings {
    pub fn parse(text: &str) -> Result<Self, String> {
        let mut map = BTreeMap::new();
        for (n, line) in text.lines().enumerate() {
            if line.trim().is_empty() {
                continue;
            }
            let (key, value) = line.split_once('=').ok_or_else(|| format!("line {}: expected key=value", n + 1))?;
            if !KEYS.contains(&key) {
                return Err(format!("line {}: unknown setting {key:?}", n + 1));
            }
            if map.insert(key.to_string(), value.to_string()).is_some() {
                return Err(format!("line {}: {key} given twice", n + 1));
            }
        }
        for key in KEYS {
            if !map.contains_key(*key) {
                return Err(format!("missing setting {key}"));
            }
        }
        Ok(Self(map))
    }

    fn get(&self, key: &str) -> &str {
        self.0.get(key).map(String::as_str).unwrap_or("")
    }

    fn s(&self, key: &str) -> String {
        nix_string(self.get(key))
    }

    fn b(&self, key: &str) -> &'static str {
        nix_bool(self.get(key))
    }

    pub fn anix_enabled(&self) -> bool {
        self.get("anix") == "yes"
    }

    pub fn anix_nix(&self) -> String {
        format!(
            "{{ ... }}:\n{{\n  anix.enable = true;\n  anix.hostname = \"{}\";\n  anix.timezone = \"{}\";\n  anix.keyboard.console = \"{}\";\n  anix.keyboard.xkb = \"{}\";\n  anix.desktop = \"{}\";\n  anix.wallpaper = \"{}\";\n}}\n",
            self.s("hostname"),
            self.s("timezone"),
            self.s("keyboard"),
            self.s("xkb"),
            self.s("desktop"),
            self.s("wallpaper"),
        )
    }

    pub fn configuration_nix(&self) -> String {
        let anix_import = if self.anix_enabled() { "    ./anix.nix\n" } else { "\n" };
        format!(
            "{{ ... }}:\n{{\n  imports = [\n    ./hardware-configuration.nix\n    ./abora/installed-base.nix\n    ./abora/abora-options.nix\n    ./abora/anix-module.nix\n    ./abora/apps.nix\n    ./abora-local.nix\n{anix_import}  ];\n}}\n"
        )
    }

    pub fn abora_local_nix(&self) -> String {
        let secrets = nix_string(self.get("secrets_dir"));
        // "Use an existing partition" never makes a bios_grub partition, so
        // BIOS boot support must be off there: limine fails silently without one.
        let bios = if self.get("disk_mode") == "existing" { "false" } else { "true" };
        let root_pw = if self.get("root_hash") == "yes" {
            format!("  users.users.root.hashedPasswordFile = \"{secrets}/root.hash\";")
        } else {
            "  users.users.root.hashedPassword = \"!\";".to_string()
        };
        format!(
            r#"{{ pkgs, lib, config, ... }}:
{{
  abora.hostname = "{host}";
  abora.locale = "{locale}";
  abora.timezone = "{tz}";
  abora.keyboard.console = "{kbd}";
  abora.keyboard.xkb = "{xkb}";
  abora.desktop = "{desktop}";
  abora.wallpaper = "{wall}";
  abora.gpu = "{gpu}";
  abora.disk = "{disk}";
  abora.diskBiosSupport = {bios};
  abora.stateVersion = "26.05";
  abora.gaming.enable = {g_enable};
  abora.gaming.steam = {g_steam};
  abora.gaming.bigPictureShortcut = {g_bp};
  abora.gaming.bigPictureAutostart = {g_auto};
  abora.gaming.gamescopeSession = {g_scope};
  abora.gaming.controllerSupport = {g_ctl};
  abora.gaming.mangohud = {g_hud};
  abora.gaming.gamemode = {g_mode};
  abora.gaming.vulkanTools = {g_vk};
  abora.gaming.launchers = {g_launch};
  abora.labs.enable = {labs};
  abora.minimal = {minimal};
  abora.extras.diagnostics = false;
  abora.extras.virtualizationGuests = false;
  abora.extras.mobileBroadband = false;
  abora.user.name = "{user}";
  abora.user.hashedPasswordFile = "{secrets}/user.hash";

  networking.networkmanager.enable = lib.mkForce true;
  i18n.supportedLocales = [
    "${{config.abora.locale}}/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];

{root_pw}
}}
"#,
            host = self.s("hostname"),
            locale = self.s("locale"),
            tz = self.s("timezone"),
            kbd = self.s("keyboard"),
            xkb = self.s("xkb"),
            desktop = self.s("desktop"),
            wall = self.s("wallpaper"),
            gpu = self.s("gpu"),
            disk = self.s("disk"),
            g_enable = self.b("gaming_enabled"),
            g_steam = self.b("gaming_steam"),
            g_bp = self.b("gaming_big_picture"),
            g_auto = self.b("gaming_autostart"),
            g_scope = self.b("gaming_gamescope"),
            g_ctl = self.b("gaming_controller"),
            g_hud = self.b("gaming_mangohud"),
            g_mode = self.b("gaming_gamemode"),
            g_vk = self.b("gaming_vulkan"),
            g_launch = self.b("gaming_launchers"),
            labs = self.b("labs"),
            minimal = self.b("minimal"),
            user = self.s("user"),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(super) fn sample() -> String {
        "hostname=abora\nlocale=en_US.UTF-8\ntimezone=America/New_York\nkeyboard=us\nxkb=us\ndesktop=gnome\nwallpaper=titlis-alps.jpg\ngpu=auto\ndisk=/dev/vda\ndisk_mode=erase\nuser=ada\nanix=yes\nroot_hash=no\nsecrets_dir=/var/lib/abora/secrets\nlabs=no\nminimal=no\ngaming_enabled=yes\ngaming_steam=yes\ngaming_big_picture=no\ngaming_autostart=no\ngaming_gamescope=no\ngaming_vulkan=yes\ngaming_controller=yes\ngaming_mangohud=no\ngaming_gamemode=yes\ngaming_launchers=no\n".to_string()
    }

    #[test]
    fn nix_strings_cannot_escape() {
        assert_eq!(nix_string(r#"a"b\c$d"#), r#"a\"b\\c\$d"#);
        assert_eq!(nix_string("x\ny"), "xy");
        assert_eq!(nix_string("${evil}"), "\\${evil}");
        assert_eq!(nix_bool("yes"), "true");
        assert_eq!(nix_bool("1"), "true");
        assert_eq!(nix_bool("no"), "false");
        assert_eq!(nix_bool(""), "false");
    }

    #[test]
    fn hostile_values_stay_inside_their_string() {
        let text = sample().replace("hostname=abora", "hostname=x\";services.openssh.enable=true;a=\"");
        let out = Settings::parse(&text).unwrap().abora_local_nix();
        assert!(out.contains("abora.hostname = \"x\\\";services.openssh.enable=true;a=\\\"\";"), "{out}");
        let dollar = sample().replace("user=ada", "user=${builtins.readFile /etc/shadow}");
        assert!(Settings::parse(&dollar).unwrap().abora_local_nix().contains("abora.user.name = \"\\${builtins"));
    }

    #[test]
    fn settings_must_be_complete_and_known() {
        assert!(Settings::parse(&sample()).is_ok());
        assert!(Settings::parse(&sample().replace("gpu=auto\n", "")).unwrap_err().contains("missing setting gpu"));
        assert!(Settings::parse(&format!("{}gpuu=auto\n", sample())).unwrap_err().contains("unknown setting"));
        assert!(Settings::parse(&format!("{}gpu=nvidia\n", sample())).unwrap_err().contains("twice"));
        assert!(Settings::parse("nonsense").unwrap_err().contains("key=value"));
    }

    #[test]
    fn existing_partition_mode_turns_bios_support_off() {
        let on = Settings::parse(&sample()).unwrap().abora_local_nix();
        assert!(on.contains("abora.diskBiosSupport = true;"));
        let off = Settings::parse(&sample().replace("disk_mode=erase", "disk_mode=existing")).unwrap().abora_local_nix();
        assert!(off.contains("abora.diskBiosSupport = false;"));
    }

    #[test]
    fn root_password_line_follows_whether_a_root_hash_exists() {
        let locked = Settings::parse(&sample()).unwrap().abora_local_nix();
        assert!(locked.contains("users.users.root.hashedPassword = \"!\";"));
        let set = Settings::parse(&sample().replace("root_hash=no", "root_hash=yes")).unwrap().abora_local_nix();
        assert!(set.contains("users.users.root.hashedPasswordFile = \"/var/lib/abora/secrets/root.hash\";"));
        assert!(set.contains("${config.abora.locale}/UTF-8"), "the Nix interpolation is written literally");
    }

    #[test]
    fn configuration_imports_anix_only_when_enabled() {
        let with = Settings::parse(&sample()).unwrap();
        assert!(with.configuration_nix().contains("    ./abora-local.nix\n    ./anix.nix\n  ];"));
        assert!(with.anix_nix().contains("anix.desktop = \"gnome\";"));
        let without = Settings::parse(&sample().replace("anix=yes", "anix=no")).unwrap();
        assert!(!without.anix_enabled() && !without.configuration_nix().contains("anix.nix"));
    }
}

#[cfg(test)]
mod layout_tests {
    use super::*;

    #[test]
    fn settings_keep_their_two_space_indent() {
        let out = Settings::parse(&super::tests::sample()).unwrap().abora_local_nix();
        assert!(out.starts_with("{ pkgs, lib, config, ... }:\n{\n  abora.hostname = \"abora\";\n"), "{out}");
        assert!(out.contains("\n\n  networking.networkmanager.enable = lib.mkForce true;\n  i18n.supportedLocales = [\n    \"${config.abora.locale}/UTF-8\"\n"));
        assert!(out.ends_with("\n  users.users.root.hashedPassword = \"!\";\n}\n"), "{out}");
    }
}
