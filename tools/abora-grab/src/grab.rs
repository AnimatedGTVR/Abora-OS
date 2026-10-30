//! Picks where a package comes from.

use crate::providers::{self, Candidate, Kind, Settings};
use crate::runner::Runner;

/// Names that need a particular source: the obvious search would miss them or
/// pick the wrong thing. Add entries here as they come up.
const CATALOG: &[(&str, Kind, &str)] = &[
    ("zen-browser", Kind::Flatpak, "app.zen_browser.zen"),
    ("zen", Kind::Flatpak, "app.zen_browser.zen"),
];

#[derive(Debug, PartialEq, Eq)]
pub enum Resolution {
    Found {
        kind: Kind,
        id: String,
        why: &'static str,
    },
    /// Nothing matched exactly; these came close.
    Ambiguous(Vec<(Kind, Candidate)>),
    NotFound,
}

/// "Zen Browser", "zen-browser" and "zen_browser" are the same name.
pub fn normalize(s: &str) -> String {
    s.chars()
        .filter(|c| c.is_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

fn exact(query: &str, c: &Candidate) -> bool {
    let q = normalize(query);
    let last = c.id.rsplit('.').next().unwrap_or(&c.id);
    [c.id.as_str(), c.name.as_str(), last]
        .iter()
        .any(|s| normalize(s) == q)
}

pub fn available(runner: &dyn Runner) -> Vec<Kind> {
    Kind::ALL
        .into_iter()
        .filter(|k| runner.has(k.program()))
        .collect()
}

pub fn resolve(
    query: &str,
    only: Option<Kind>,
    runner: &mut dyn Runner,
    settings: &Settings,
) -> Result<Resolution, String> {
    let have = available(runner);
    if let Some(kind) = only {
        if !have.contains(&kind) {
            return Err(format!("{} isn't installed on this system", kind.program()));
        }
    }

    if only.is_none() {
        if let Some(&(_, kind, id)) = CATALOG
            .iter()
            .find(|(name, ..)| normalize(name) == normalize(query))
        {
            if have.contains(&kind) {
                return Ok(Resolution::Found {
                    kind,
                    id: id.into(),
                    why: "Abora's catalog",
                });
            }
        }
    }

    let mut close = Vec::new();
    let mut errors = Vec::new();
    for kind in have.into_iter().filter(|k| only.is_none_or(|o| o == *k)) {
        match providers::search(kind, query, runner, settings) {
            Ok(found) => {
                if let Some(hit) = found.iter().find(|c| exact(query, c)) {
                    return Ok(Resolution::Found {
                        kind,
                        id: hit.id.clone(),
                        why: "exact match",
                    });
                }
                close.extend(found.into_iter().take(5).map(|c| (kind, c)));
            }
            Err(e) => errors.push(format!("{}: {e}", kind.program())),
        }
    }
    if !close.is_empty() {
        return Ok(Resolution::Ambiguous(close));
    }
    if !errors.is_empty() {
        return Err(errors.join("\n"));
    }
    Ok(Resolution::NotFound)
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use std::collections::HashMap;

    /// Answers queries by the start of the command line.
    #[derive(Default)]
    pub struct Fake {
        pub programs: Vec<&'static str>,
        pub answers: HashMap<&'static str, Result<String, String>>,
        pub ran: Vec<String>,
    }

    impl Runner for Fake {
        fn has(&self, program: &str) -> bool {
            self.programs.contains(&program)
        }
        fn capture(&mut self, argv: &[&str]) -> Result<String, String> {
            let line = argv.join(" ");
            self.answers
                .iter()
                .find(|(prefix, _)| line.starts_with(*prefix))
                .map(|(_, answer)| answer.clone())
                .unwrap_or_else(|| Err(format!("unexpected: {line}")))
        }
        fn run(&mut self, argv: &[&str]) -> Result<(), String> {
            self.ran.push(argv.join(" "));
            Ok(())
        }
    }

    const NIX_SEARCH: &str = "nix --extra-experimental-features nix-command flakes search";
    pub const HTOP: &str =
        r#"{"legacyPackages.x86_64-linux.htop":{"pname":"htop","description":"Process viewer"}}"#;

    fn settings() -> Settings {
        Settings {
            config_dir: "/nonexistent".into(),
            ..Settings::default()
        }
    }

    fn fake(programs: &[&'static str], answers: &[(&'static str, Result<&str, &str>)]) -> Fake {
        Fake {
            programs: programs.to_vec(),
            answers: answers
                .iter()
                .map(|(k, v)| (*k, v.map(str::to_string).map_err(str::to_string)))
                .collect(),
            ran: Vec::new(),
        }
    }

    #[test]
    fn names_compare_without_case_or_punctuation() {
        assert_eq!(normalize("Zen Browser"), normalize("zen-browser"));
        assert_ne!(normalize("zen"), normalize("zen-browser"));
    }

    #[test]
    fn the_catalog_sends_zen_to_flathub() {
        let mut f = fake(&["nix", "flatpak"], &[]);
        let r = resolve("zen-browser", None, &mut f, &settings()).unwrap();
        assert_eq!(
            r,
            Resolution::Found {
                kind: Kind::Flatpak,
                id: "app.zen_browser.zen".into(),
                why: "Abora's catalog"
            }
        );
    }

    #[test]
    fn nix_is_asked_first_and_an_exact_match_wins() {
        let mut f = fake(&["nix", "flatpak"], &[(NIX_SEARCH, Ok(HTOP))]);
        let r = resolve("htop", None, &mut f, &settings()).unwrap();
        assert_eq!(
            r,
            Resolution::Found {
                kind: Kind::Nix,
                id: "htop".into(),
                why: "exact match"
            }
        );
    }

    #[test]
    fn falls_through_to_flatpak_by_app_name() {
        let mut f = fake(
            &["nix", "flatpak"],
            &[
                (
                    NIX_SEARCH,
                    Err("error: no results for the given search term(s)!"),
                ),
                (
                    "flatpak search",
                    Ok("org.mozilla.firefox\tFirefox\tWeb Browser\n"),
                ),
            ],
        );
        let r = resolve("firefox", None, &mut f, &settings()).unwrap();
        assert_eq!(
            r,
            Resolution::Found {
                kind: Kind::Flatpak,
                id: "org.mozilla.firefox".into(),
                why: "exact match"
            }
        );
    }

    #[test]
    fn close_matches_are_offered_not_installed() {
        let mut f = fake(
            &["flatpak"],
            &[(
                "flatpak search",
                Ok("com.spotify.Client\tSpotify\tMusic\nio.github.spot\tSpot\tSpotify client\n"),
            )],
        );
        match resolve("spotify-player", None, &mut f, &settings()).unwrap() {
            Resolution::Ambiguous(list) => assert_eq!(list.len(), 2),
            other => panic!("expected close matches, got {other:?}"),
        }
    }

    #[test]
    fn a_forced_provider_skips_the_catalog_and_must_exist() {
        let mut f = fake(&["nix"], &[(NIX_SEARCH, Ok(HTOP))]);
        assert!(resolve("htop", Some(Kind::Snap), &mut f, &settings())
            .unwrap_err()
            .contains("snap"));
        let mut f = fake(
            &["nix", "flatpak"],
            &[(NIX_SEARCH, Err("error: no results"))],
        );
        assert_eq!(
            resolve("zen", Some(Kind::Nix), &mut f, &settings()).unwrap(),
            Resolution::NotFound
        );
    }

    #[test]
    fn errors_surface_only_when_nothing_was_found() {
        let mut f = fake(&["nix"], &[(NIX_SEARCH, Err("unable to download"))]);
        assert!(resolve("htop", None, &mut f, &settings())
            .unwrap_err()
            .contains("unable to download"));
    }
}
