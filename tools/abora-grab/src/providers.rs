//! The package sources grab knows: Nix (or Lix, its fork), Flatpak and Snap.

use std::path::Path;

use crate::grab::normalize;
use crate::runner::Runner;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Nix,
    Flatpak,
    Snap,
}

impl Kind {
    pub const ALL: [Kind; 3] = [Kind::Nix, Kind::Flatpak, Kind::Snap];

    pub fn parse(name: &str) -> Option<Kind> {
        match name {
            "nix" | "lix" | "nixpkgs" => Some(Kind::Nix),
            "flatpak" | "flathub" => Some(Kind::Flatpak),
            "snap" => Some(Kind::Snap),
            _ => None,
        }
    }

    pub fn program(self) -> &'static str {
        match self {
            Kind::Nix => "nix",
            Kind::Flatpak => "flatpak",
            Kind::Snap => "snap",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Candidate {
    pub id: String,
    pub name: String,
    pub summary: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scope {
    User,
    System,
}

pub struct Settings {
    pub scope: Scope,
    /// The system flake whose pinned nixpkgs installs should use.
    pub config_dir: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            scope: Scope::User,
            config_dir: std::env::var("ANIX_SYSTEM_CONFIG").unwrap_or_else(|_| "/etc/nixos".into()),
        }
    }
}

const NIX_FLAGS: [&str; 2] = ["--extra-experimental-features", "nix-command flakes"];

/// Shows "lix" when the nix command is really Lix.
pub fn nix_flavor(runner: &mut dyn Runner) -> &'static str {
    match runner.capture(&["nix", "--version"]) {
        Ok(v) if v.to_lowercase().contains("lix") => "lix",
        _ => "nix",
    }
}

fn nixpkgs_args(settings: &Settings) -> Vec<String> {
    if Path::new(&settings.config_dir).join("flake.lock").is_file() {
        vec!["--inputs-from".into(), settings.config_dir.clone()]
    } else {
        Vec::new()
    }
}

fn argv(parts: &[String]) -> Vec<&str> {
    parts.iter().map(String::as_str).collect()
}

/// The exact command that installs `id` from `kind`.
pub fn install_command(
    kind: Kind,
    id: &str,
    runner: &mut dyn Runner,
    settings: &Settings,
) -> Vec<String> {
    let mut cmd: Vec<String> = Vec::new();
    match kind {
        Kind::Nix => {
            // Newer Nix renamed `profile install` to `profile add`.
            let mut probe = vec!["nix"];
            probe.extend(NIX_FLAGS);
            probe.extend(["profile", "add", "--help"]);
            let verb = if runner.capture(&probe).is_ok() {
                "add"
            } else {
                "install"
            };
            cmd.push("nix".into());
            cmd.extend(NIX_FLAGS.map(String::from));
            cmd.extend(["profile".into(), verb.into()]);
            cmd.extend(nixpkgs_args(settings));
            cmd.push(format!("nixpkgs#{id}"));
        }
        Kind::Flatpak => {
            cmd.extend(
                [
                    "flatpak",
                    "install",
                    "--noninteractive",
                    scope_flag(settings),
                    "flathub",
                    id,
                ]
                .map(String::from),
            );
        }
        Kind::Snap => cmd.extend(["snap", "install", id].map(String::from)),
    }
    cmd
}

pub fn remove_command(kind: Kind, id: &str, settings: &Settings) -> Vec<String> {
    match kind {
        Kind::Nix => {
            let mut cmd = vec!["nix".to_string()];
            cmd.extend(NIX_FLAGS.map(String::from));
            cmd.extend(["profile", "remove", id].map(String::from));
            cmd
        }
        Kind::Flatpak => [
            "flatpak",
            "uninstall",
            "--noninteractive",
            scope_flag(settings),
            id,
        ]
        .map(String::from)
        .to_vec(),
        Kind::Snap => ["snap", "remove", id].map(String::from).to_vec(),
    }
}

fn scope_flag(settings: &Settings) -> &'static str {
    match settings.scope {
        Scope::User => "--user",
        Scope::System => "--system",
    }
}

pub fn search(
    kind: Kind,
    query: &str,
    runner: &mut dyn Runner,
    settings: &Settings,
) -> Result<Vec<Candidate>, String> {
    match kind {
        Kind::Nix => {
            let mut cmd: Vec<String> = vec!["nix".into()];
            cmd.extend(NIX_FLAGS.map(String::from));
            cmd.push("search".into());
            cmd.extend(nixpkgs_args(settings));
            cmd.extend(["--json".into(), "nixpkgs".into(), query.into()]);
            match runner.capture(&argv(&cmd)) {
                Ok(out) => Ok(parse_nix_search(&out)),
                // `nix search` exits non-zero when nothing matches.
                Err(e) if e.contains("no results") => Ok(Vec::new()),
                Err(e) => Err(e),
            }
        }
        Kind::Flatpak => {
            let out = runner.capture(&[
                "flatpak",
                "search",
                "--columns=application,name,description",
                query,
            ])?;
            Ok(parse_flatpak_search(&out))
        }
        Kind::Snap => match runner.capture(&["snap", "find", query]) {
            Ok(out) => Ok(parse_snap_find(&out)),
            Err(e) if e.contains("No matching snaps") => Ok(Vec::new()),
            Err(e) => Err(e),
        },
    }
}

/// The installed id matching `query`, if this provider has it.
pub fn installed(kind: Kind, query: &str, runner: &mut dyn Runner) -> Option<String> {
    let q = normalize(query);
    match kind {
        Kind::Nix => {
            let mut cmd = vec!["nix"];
            cmd.extend(NIX_FLAGS);
            cmd.extend(["profile", "list", "--json"]);
            let out = runner.capture(&cmd).ok()?;
            let json: serde_json::Value = serde_json::from_str(&out).ok()?;
            json.get("elements")?
                .as_object()?
                .keys()
                .find(|name| normalize(name) == q)
                .cloned()
        }
        Kind::Flatpak => {
            let out = runner
                .capture(&["flatpak", "list", "--app", "--columns=application,name"])
                .ok()?;
            out.lines().find_map(|line| {
                let mut cols = line.split('\t');
                let (id, name) = (cols.next()?.trim(), cols.next().unwrap_or("").trim());
                (normalize(id) == q || normalize(name) == q).then(|| id.to_string())
            })
        }
        Kind::Snap => {
            let out = runner.capture(&["snap", "list"]).ok()?;
            out.lines()
                .skip(1)
                .filter_map(|l| l.split_whitespace().next())
                .find(|name| normalize(name) == q)
                .map(str::to_string)
        }
    }
}

pub fn parse_nix_search(json: &str) -> Vec<Candidate> {
    let Ok(serde_json::Value::Object(map)) = serde_json::from_str(json) else {
        return Vec::new();
    };
    let mut found: Vec<Candidate> = map
        .iter()
        .map(|(attr, info)| {
            // "legacyPackages.x86_64-linux.firefox" -> "firefox"
            let id = attr.splitn(3, '.').nth(2).unwrap_or(attr).to_string();
            let field = |k: &str| {
                info.get(k)
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string()
            };
            Candidate {
                name: field("pname"),
                summary: field("description"),
                id,
            }
        })
        .collect();
    found.sort_by(|a, b| a.id.cmp(&b.id));
    found
}

pub fn parse_flatpak_search(out: &str) -> Vec<Candidate> {
    out.lines()
        .filter(|l| l.contains('\t'))
        .filter_map(|line| {
            let cols: Vec<&str> = line.split('\t').map(str::trim).collect();
            let id = cols.first()?.to_string();
            // The header row, when flatpak prints one.
            if id.eq_ignore_ascii_case("application id") || !id.contains('.') {
                return None;
            }
            Some(Candidate {
                id,
                name: cols.get(1).unwrap_or(&"").to_string(),
                summary: cols.get(2).unwrap_or(&"").to_string(),
            })
        })
        .collect()
}

/// `snap find` prints aligned columns: Name Version Publisher Notes Summary.
pub fn parse_snap_find(out: &str) -> Vec<Candidate> {
    out.lines()
        .skip_while(|l| !l.starts_with("Name"))
        .skip(1)
        .filter_map(|line| {
            let cols: Vec<&str> = line
                .split("  ")
                .map(str::trim)
                .filter(|c| !c.is_empty())
                .collect();
            let id = cols.first()?.to_string();
            Some(Candidate {
                name: id.clone(),
                summary: cols.last().unwrap_or(&"").to_string(),
                id,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nix_search_json_gives_attribute_names() {
        let out = r#"{"legacyPackages.x86_64-linux.htop":{"pname":"htop","version":"3.4.1","description":"An interactive process viewer"},
                     "legacyPackages.x86_64-linux.btop":{"pname":"btop","version":"1.4","description":"A monitor of resources"}}"#;
        let found = parse_nix_search(out);
        assert_eq!(
            found.iter().map(|c| c.id.as_str()).collect::<Vec<_>>(),
            ["btop", "htop"]
        );
        assert_eq!(found[1].summary, "An interactive process viewer");
        assert!(parse_nix_search("not json").is_empty());
    }

    #[test]
    fn flatpak_search_skips_the_header() {
        let out = "Application ID\tName\tDescription\n\
                   app.zen_browser.zen\tZen Browser\tExperience tranquillity while browsing the web\n\
                   org.mozilla.firefox\tFirefox\tFast, Private & Safe Web Browser\n";
        let found = parse_flatpak_search(out);
        assert_eq!(found.len(), 2);
        assert_eq!(found[0].id, "app.zen_browser.zen");
        assert_eq!(found[0].name, "Zen Browser");
        assert!(parse_flatpak_search("No matches found\n").is_empty());
    }

    #[test]
    fn snap_find_reads_aligned_columns() {
        let out = "Name      Version  Publisher   Notes  Summary\n\
                   firefox   131.0    mozilla**   -      Mozilla Firefox web browser\n\
                   firefox-x 1.0      someone     -      Unofficial build\n";
        let found = parse_snap_find(out);
        assert_eq!(found[0].id, "firefox");
        assert_eq!(found[0].summary, "Mozilla Firefox web browser");
        assert_eq!(found.len(), 2);
    }

    #[test]
    fn provider_names_include_lix_and_flathub() {
        assert_eq!(Kind::parse("lix"), Some(Kind::Nix));
        assert_eq!(Kind::parse("flathub"), Some(Kind::Flatpak));
        assert_eq!(Kind::parse("apt"), None);
    }
}
