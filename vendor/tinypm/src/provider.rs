use std::fmt::Write as _;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::{env, fs};

use anyhow::{Context, Result, bail};
use clap::ValueEnum;

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub enum Provider {
    Auto,
    Apt,
    Dnf,
    Pacman,
    Apk,
    Zypper,
    #[value(alias = "xbps-install")]
    Xbps,
    #[value(alias = "emerge")]
    Portage,
    Eopkg,
    Swupd,
    Slackpkg,
    Opkg,
    Urpmi,
    Guix,
    Moss,
    Tazpkg,
    #[value(alias = "prtget")]
    PrtGet,
    Flatpak,
    Snap,
    Nix,
    Brew,
}

#[derive(Clone, Copy, Debug)]
pub enum Action {
    Install,
    Search,
    Info,
    Remove,
    Update,
    List,
}

#[derive(Debug, Eq, PartialEq)]
pub struct CommandSpec {
    program: &'static str,
    args: Vec<String>,
    elevated: bool,
}

#[derive(Debug, Eq, PartialEq)]
pub struct PackageResolution {
    pub resolved: String,
    pub reason: Option<&'static str>,
}

impl PackageResolution {
    pub const fn is_alias(&self) -> bool {
        self.reason.is_some()
    }
}

impl Provider {
    pub const fn supported() -> &'static [Self] {
        &[
            Self::Apt,
            Self::Dnf,
            Self::Pacman,
            Self::Apk,
            Self::Zypper,
            Self::Xbps,
            Self::Portage,
            Self::Eopkg,
            Self::Swupd,
            Self::Slackpkg,
            Self::Opkg,
            Self::Urpmi,
            Self::Guix,
            Self::Moss,
            Self::Tazpkg,
            Self::PrtGet,
            Self::Flatpak,
            Self::Snap,
            Self::Nix,
            Self::Brew,
        ]
    }

    pub fn from_key(key: &str) -> Result<Self> {
        match key {
            "apt" => Ok(Self::Apt),
            "dnf" => Ok(Self::Dnf),
            "pacman" => Ok(Self::Pacman),
            "apk" => Ok(Self::Apk),
            "zypper" => Ok(Self::Zypper),
            "xbps" => Ok(Self::Xbps),
            "portage" | "emerge" => Ok(Self::Portage),
            "eopkg" => Ok(Self::Eopkg),
            "swupd" => Ok(Self::Swupd),
            "slackpkg" => Ok(Self::Slackpkg),
            "opkg" => Ok(Self::Opkg),
            "urpmi" => Ok(Self::Urpmi),
            "guix" => Ok(Self::Guix),
            "moss" => Ok(Self::Moss),
            "tazpkg" => Ok(Self::Tazpkg),
            "prt-get" | "prtget" => Ok(Self::PrtGet),
            "flatpak" => Ok(Self::Flatpak),
            "snap" => Ok(Self::Snap),
            "nix" => Ok(Self::Nix),
            "brew" => Ok(Self::Brew),
            _ => bail!("unknown provider in transaction history: {key}"),
        }
    }

    pub fn resolve(self) -> Result<Self> {
        if self != Self::Auto {
            if executable_exists(self.executable()) {
                return Ok(self);
            }
            bail!("{} is not installed or not in PATH", self.executable());
        }

        if let Some(os_release) = read_os_release() {
            if let Some(provider) = preferred_from_os_release(&os_release) {
                if executable_exists(provider.executable()) {
                    return Ok(provider);
                }
            }
        }

        const ORDER: &[Provider] = &[
            Provider::Apt,
            Provider::Dnf,
            Provider::Pacman,
            Provider::Apk,
            Provider::Zypper,
            Provider::Xbps,
            Provider::Portage,
            Provider::Eopkg,
            Provider::Swupd,
            Provider::Slackpkg,
            Provider::Opkg,
            Provider::Urpmi,
            Provider::Guix,
            Provider::Moss,
            Provider::Tazpkg,
            Provider::PrtGet,
            Provider::Flatpak,
            Provider::Snap,
            Provider::Nix,
            Provider::Brew,
        ];
        ORDER
            .iter()
            .copied()
            .find(|provider| executable_exists(provider.executable()))
            .context("no supported package manager was found in PATH")
    }

    pub const fn executable(self) -> &'static str {
        match self {
            Self::Auto => "auto",
            Self::Apt => "apt-get",
            Self::Dnf => "dnf",
            Self::Pacman => "pacman",
            Self::Apk => "apk",
            Self::Zypper => "zypper",
            Self::Xbps => "xbps-install",
            Self::Portage => "emerge",
            Self::Eopkg => "eopkg",
            Self::Swupd => "swupd",
            Self::Slackpkg => "slackpkg",
            Self::Opkg => "opkg",
            Self::Urpmi => "urpmi",
            Self::Guix => "guix",
            Self::Moss => "moss",
            Self::Tazpkg => "tazpkg",
            Self::PrtGet => "prt-get",
            Self::Flatpak => "flatpak",
            Self::Snap => "snap",
            Self::Nix => "nix",
            Self::Brew => "brew",
        }
    }

    /// Executables needed to support every core action for this provider.
    pub const fn required_executables(self) -> &'static [&'static str] {
        match self {
            Self::Auto => &[],
            Self::Apt => &["apt-get", "apt-cache", "dpkg-query"],
            Self::Dnf => &["dnf"],
            Self::Pacman => &["pacman"],
            Self::Apk => &["apk"],
            Self::Zypper => &["zypper"],
            Self::Xbps => &["xbps-install", "xbps-query", "xbps-remove"],
            Self::Portage => &["emerge", "qlist"],
            Self::Eopkg => &["eopkg"],
            Self::Swupd => &["swupd"],
            Self::Slackpkg => &["slackpkg"],
            Self::Opkg => &["opkg"],
            Self::Urpmi => &["urpmi", "urpmq", "urpme", "rpm"],
            Self::Guix => &["guix"],
            Self::Moss => &["moss"],
            Self::Tazpkg => &["tazpkg"],
            Self::PrtGet => &["prt-get"],
            Self::Flatpak => &["flatpak"],
            Self::Snap => &["snap"],
            Self::Nix => &["nix"],
            Self::Brew => &["brew"],
        }
    }

    pub fn missing_executables(self) -> Vec<&'static str> {
        self.required_executables()
            .iter()
            .copied()
            .filter(|executable| !executable_exists(executable))
            .collect()
    }

    pub const fn label(self) -> &'static str {
        match self {
            Self::Auto => "Auto",
            Self::Apt => "APT",
            Self::Dnf => "DNF",
            Self::Pacman => "Pacman",
            Self::Apk => "APK",
            Self::Zypper => "Zypper",
            Self::Xbps => "XBPS",
            Self::Portage => "Portage",
            Self::Eopkg => "eopkg",
            Self::Swupd => "swupd",
            Self::Slackpkg => "slackpkg",
            Self::Opkg => "opkg",
            Self::Urpmi => "URPMI",
            Self::Guix => "Guix",
            Self::Moss => "Moss",
            Self::Tazpkg => "TazPkg",
            Self::PrtGet => "prt-get",
            Self::Flatpak => "Flatpak",
            Self::Snap => "Snap",
            Self::Nix => "Nix",
            Self::Brew => "Homebrew",
        }
    }

    pub const fn key(self) -> &'static str {
        provider_key(self)
    }

    pub const fn validation_level(self) -> &'static str {
        match self {
            Self::Apt | Self::Dnf | Self::Pacman | Self::Apk | Self::Zypper => "transaction-tested",
            _ => "command-contract",
        }
    }

    pub fn plan(self, action: Action, values: &[String]) -> Result<Vec<CommandSpec>> {
        if self == Self::Apt && matches!(action, Action::Update) {
            return Ok(vec![
                CommandSpec::new("apt-get", &["update"], true),
                CommandSpec::new("apt-get", &["upgrade", "-y"], true),
            ]);
        }
        if self == Self::Apk && matches!(action, Action::Update) {
            return Ok(vec![
                CommandSpec::new("apk", &["update"], true),
                CommandSpec::new("apk", &["upgrade"], true),
            ]);
        }
        if matches!(action, Action::Update) {
            let plan = match self {
                Self::Portage => Some(vec![
                    CommandSpec::new("emerge", &["--sync"], true),
                    CommandSpec::new(
                        "emerge",
                        &["--ask=n", "--update", "--deep", "--newuse", "@world"],
                        true,
                    ),
                ]),
                Self::Eopkg => Some(vec![
                    CommandSpec::new("eopkg", &["update-repo"], true),
                    CommandSpec::new("eopkg", &["upgrade", "-y"], true),
                ]),
                Self::Slackpkg => Some(vec![
                    CommandSpec::new("slackpkg", &["update"], true),
                    CommandSpec::new(
                        "slackpkg",
                        &["-batch=on", "-default_answer=y", "upgrade-all"],
                        true,
                    ),
                ]),
                Self::Opkg => Some(vec![
                    CommandSpec::new("opkg", &["update"], true),
                    CommandSpec::new("opkg", &["upgrade"], true),
                ]),
                Self::Guix => Some(vec![
                    CommandSpec::new("guix", &["pull"], false),
                    CommandSpec::new("guix", &["package", "--upgrade"], false),
                ]),
                _ => None,
            };
            if let Some(plan) = plan {
                return Ok(plan);
            }
        }
        Ok(vec![self.single_command(action, values)?])
    }

    pub fn command(self, action: Action, values: &[String]) -> Result<CommandSpec> {
        let mut plan = self.plan(action, values)?;
        if plan.len() != 1 {
            bail!(
                "{} {} requires a multi-step plan",
                self.label(),
                action.label()
            );
        }
        Ok(plan.remove(0))
    }

    pub fn is_installed(self, package: &str) -> Result<Option<bool>> {
        use Provider::*;
        let (program, args): (&'static str, Vec<String>) = match self {
            Apt => ("dpkg-query", vec!["-W".into(), package.into()]),
            Dnf | Zypper => ("rpm", vec!["-q".into(), package.into()]),
            Pacman => ("pacman", vec!["-Q".into(), package.into()]),
            Apk => ("apk", vec!["info".into(), "-e".into(), package.into()]),
            Xbps => ("xbps-query", vec![package.into()]),
            Portage | Eopkg | Swupd | Slackpkg | Guix | Moss | Tazpkg | PrtGet => {
                return Ok(None);
            }
            Opkg => ("opkg", vec!["status".into(), package.into()]),
            Urpmi => ("rpm", vec!["-q".into(), package.into()]),
            Flatpak => ("flatpak", vec!["info".into(), package.into()]),
            Snap => ("snap", vec!["list".into(), package.into()]),
            Brew => (
                "brew",
                vec!["list".into(), "--versions".into(), package.into()],
            ),
            Nix => return Ok(None),
            Auto => bail!("the automatic provider must be resolved first"),
        };
        if !executable_exists(program) {
            return Ok(None);
        }
        CommandSpec {
            program,
            args,
            elevated: false,
        }
        .success_silent()
        .map(Some)
    }

    pub fn is_available(self, package: &str) -> Result<bool> {
        self.command(Action::Info, &[package.to_owned()])?
            .success_silent()
    }

    pub fn executable_path(self) -> Option<PathBuf> {
        find_executable(self.executable())
    }

    fn single_command(self, action: Action, values: &[String]) -> Result<CommandSpec> {
        use Action::*;
        use Provider::*;

        let (program, fixed, elevated): (&'static str, &[&str], bool) = match (self, action) {
            (Apt, Install) => ("apt-get", &["install", "-y"], true),
            (Apt, Search) => ("apt-cache", &["search"], false),
            (Apt, Info) => ("apt-cache", &["show"], false),
            (Apt, Remove) => ("apt-get", &["remove", "-y"], true),
            (Apt, Update) => ("apt-get", &["upgrade", "-y"], true),
            (Apt, List) => ("dpkg-query", &["-W"], false),
            (Dnf, Install) => ("dnf", &["install", "-y"], true),
            (Dnf, Search) => ("dnf", &["search"], false),
            (Dnf, Info) => ("dnf", &["info"], false),
            (Dnf, Remove) => ("dnf", &["remove", "-y"], true),
            (Dnf, Update) => ("dnf", &["upgrade", "-y"], true),
            (Dnf, List) => ("dnf", &["list", "installed"], false),
            (Pacman, Install) => ("pacman", &["-S", "--noconfirm"], true),
            (Pacman, Search) => ("pacman", &["-Ss"], false),
            (Pacman, Info) => ("pacman", &["-Si"], false),
            (Pacman, Remove) => ("pacman", &["-Rns", "--noconfirm"], true),
            (Pacman, Update) => ("pacman", &["-Syu", "--noconfirm"], true),
            (Pacman, List) => ("pacman", &["-Q"], false),
            (Apk, Install) => ("apk", &["add"], true),
            (Apk, Search) => ("apk", &["search"], false),
            (Apk, Info) => ("apk", &["info", "-a"], false),
            (Apk, Remove) => ("apk", &["del"], true),
            (Apk, Update) => ("apk", &["upgrade"], true),
            (Apk, List) => ("apk", &["info"], false),
            (Zypper, Install) => ("zypper", &["--non-interactive", "install"], true),
            (Zypper, Search) => ("zypper", &["search"], false),
            (Zypper, Info) => ("zypper", &["--non-interactive", "info"], false),
            (Zypper, Remove) => ("zypper", &["--non-interactive", "remove"], true),
            (Zypper, Update) => ("zypper", &["--non-interactive", "update"], true),
            (Zypper, List) => ("zypper", &["search", "--installed-only"], false),
            (Xbps, Install) => ("xbps-install", &["-Sy"], true),
            (Xbps, Search) => ("xbps-query", &["-Rs"], false),
            (Xbps, Info) => ("xbps-query", &["-RS"], false),
            (Xbps, Remove) => ("xbps-remove", &["-Ry"], true),
            (Xbps, Update) => ("xbps-install", &["-Syu"], true),
            (Xbps, List) => ("xbps-query", &["-l"], false),
            (Portage, Install) => ("emerge", &["--ask=n"], true),
            (Portage, Search | Info) => ("emerge", &["--search"], false),
            (Portage, Remove) => ("emerge", &["--ask=n", "--depclean"], true),
            (Portage, Update) => (
                "emerge",
                &["--ask=n", "--update", "--deep", "--newuse", "@world"],
                true,
            ),
            (Portage, List) => ("qlist", &["-I"], false),
            (Eopkg, Install) => ("eopkg", &["install", "-y"], true),
            (Eopkg, Search) => ("eopkg", &["search"], false),
            (Eopkg, Info) => ("eopkg", &["info"], false),
            (Eopkg, Remove) => ("eopkg", &["remove", "-y"], true),
            (Eopkg, Update) => ("eopkg", &["upgrade", "-y"], true),
            (Eopkg, List) => ("eopkg", &["list-installed"], false),
            (Swupd, Install) => ("swupd", &["bundle-add"], true),
            (Swupd, Search) => ("swupd", &["search"], false),
            (Swupd, Info) => ("swupd", &["bundle-info"], false),
            (Swupd, Remove) => ("swupd", &["bundle-remove"], true),
            (Swupd, Update) => ("swupd", &["update"], true),
            (Swupd, List) => ("swupd", &["bundle-list"], false),
            (Slackpkg, Install) => (
                "slackpkg",
                &["-batch=on", "-default_answer=y", "install"],
                true,
            ),
            (Slackpkg, Search) => ("slackpkg", &["search"], false),
            (Slackpkg, Info) => ("slackpkg", &["info"], false),
            (Slackpkg, Remove) => (
                "slackpkg",
                &["-batch=on", "-default_answer=y", "remove"],
                true,
            ),
            (Slackpkg, Update) => (
                "slackpkg",
                &["-batch=on", "-default_answer=y", "upgrade-all"],
                true,
            ),
            (Slackpkg, List) => ("slackpkg", &["search", "[ installed ]"], false),
            (Opkg, Install) => ("opkg", &["install"], true),
            (Opkg, Search) => ("opkg", &["find"], false),
            (Opkg, Info) => ("opkg", &["info"], false),
            (Opkg, Remove) => ("opkg", &["remove"], true),
            (Opkg, Update) => ("opkg", &["upgrade"], true),
            (Opkg, List) => ("opkg", &["list-installed"], false),
            (Urpmi, Install) => ("urpmi", &["--auto"], true),
            (Urpmi, Search) => ("urpmq", &["-y"], false),
            (Urpmi, Info) => ("urpmq", &["-i"], false),
            (Urpmi, Remove) => ("urpme", &["--auto"], true),
            (Urpmi, Update) => ("urpmi", &["--auto-update", "--auto"], true),
            (Urpmi, List) => ("rpm", &["-qa"], false),
            (Guix, Install) => ("guix", &["install"], false),
            (Guix, Search) => ("guix", &["search"], false),
            (Guix, Info) => ("guix", &["show"], false),
            (Guix, Remove) => ("guix", &["remove"], false),
            (Guix, Update) => ("guix", &["package", "--upgrade"], false),
            (Guix, List) => ("guix", &["package", "--list-installed"], false),
            (Moss, Install) => ("moss", &["--yes-all", "install"], true),
            (Moss, Search) => ("moss", &["search"], false),
            (Moss, Info) => ("moss", &["info"], false),
            (Moss, Remove) => ("moss", &["--yes-all", "remove"], true),
            (Moss, Update) => ("moss", &["--yes-all", "sync", "--update"], true),
            (Moss, List) => ("moss", &["list", "installed"], false),
            (Tazpkg, Install) => ("tazpkg", &["get-install"], true),
            (Tazpkg, Search) => ("tazpkg", &["search"], false),
            (Tazpkg, Info) => ("tazpkg", &["info"], false),
            (Tazpkg, Remove) => ("tazpkg", &["remove", "--auto"], true),
            (Tazpkg, Update) => ("tazpkg", &["upgrade", "--install"], true),
            (Tazpkg, List) => ("tazpkg", &["list"], false),
            (PrtGet, Install) => ("prt-get", &["depinst"], true),
            (PrtGet, Search) => ("prt-get", &["search"], false),
            (PrtGet, Info) => ("prt-get", &["info"], false),
            (PrtGet, Remove) => ("prt-get", &["remove"], true),
            (PrtGet, Update) => ("prt-get", &["sysup"], true),
            (PrtGet, List) => ("prt-get", &["listinst"], false),
            (Flatpak, Install) => ("flatpak", &["install", "-y"], false),
            (Flatpak, Search) => ("flatpak", &["search"], false),
            (Flatpak, Info) => ("flatpak", &["remote-info", "flathub"], false),
            (Flatpak, Remove) => ("flatpak", &["uninstall", "-y"], false),
            (Flatpak, Update) => ("flatpak", &["update", "-y"], false),
            (Flatpak, List) => ("flatpak", &["list"], false),
            (Snap, Install) => ("snap", &["install"], true),
            (Snap, Search) => ("snap", &["find"], false),
            (Snap, Info) => ("snap", &["info"], false),
            (Snap, Remove) => ("snap", &["remove"], true),
            (Snap, Update) => ("snap", &["refresh"], true),
            (Snap, List) => ("snap", &["list"], false),
            (Nix, Install) => ("nix", &["profile", "install"], false),
            (Nix, Search) => ("nix", &["search", "nixpkgs"], false),
            (Nix, Info) => ("nix", &["search", "nixpkgs"], false),
            (Nix, Remove) => ("nix", &["profile", "remove"], false),
            (Nix, Update) => ("nix", &["profile", "upgrade", "--all"], false),
            (Nix, List) => ("nix", &["profile", "list"], false),
            (Brew, Install) => ("brew", &["install"], false),
            (Brew, Search) => ("brew", &["search"], false),
            (Brew, Info) => ("brew", &["info"], false),
            (Brew, Remove) => ("brew", &["uninstall"], false),
            (Brew, Update) => ("brew", &["upgrade"], false),
            (Brew, List) => ("brew", &["list"], false),
            (Auto, _) => bail!("the automatic provider must be resolved first"),
        };

        let mut args = fixed
            .iter()
            .map(|arg| (*arg).to_owned())
            .collect::<Vec<_>>();
        if self == Nix && matches!(action, Install) {
            args.extend(values.iter().map(|value| format!("nixpkgs#{value}")));
        } else if self == Opkg && matches!(action, Search) {
            args.extend(values.iter().map(|value| format!("*{value}*")));
        } else {
            args.extend(values.iter().cloned());
        }
        Ok(CommandSpec {
            program,
            args,
            elevated,
        })
    }
}

fn read_os_release() -> Option<String> {
    read_os_release_from(&[
        std::path::Path::new("/etc/os-release"),
        std::path::Path::new("/usr/lib/os-release"),
    ])
}

fn read_os_release_from(paths: &[&std::path::Path]) -> Option<String> {
    paths
        .iter()
        .find_map(|path| std::fs::read_to_string(path).ok())
}

fn preferred_from_os_release(contents: &str) -> Option<Provider> {
    let mut identities = Vec::new();
    for line in contents.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if matches!(key, "ID" | "ID_LIKE") {
            identities.extend(
                value
                    .trim_matches(|character| character == '\'' || character == '"')
                    .split_ascii_whitespace(),
            );
        }
    }
    for identity in identities {
        let provider = match identity.to_ascii_lowercase().as_str() {
            "debian" | "ubuntu" | "linuxmint" | "pop" | "elementary" | "kali" | "neon"
            | "raspbian" | "devuan" | "deepin" | "zorin" => Provider::Apt,
            "fedora" | "rhel" | "centos" | "rocky" | "almalinux" | "ol" | "nobara" | "amazon"
            | "amzn" => Provider::Dnf,
            "arch" | "manjaro" | "endeavouros" | "artix" | "garuda" | "cachyos" => Provider::Pacman,
            "alpine" | "adelie" | "postmarketos" | "chimera" => Provider::Apk,
            "opensuse" | "opensuse-leap" | "opensuse-tumbleweed" | "suse" | "sles" => {
                Provider::Zypper
            }
            "void" => Provider::Xbps,
            "nixos" => Provider::Nix,
            "gentoo" | "funtoo" => Provider::Portage,
            "solus" => Provider::Eopkg,
            "clear-linux-os" | "clear-linux" => Provider::Swupd,
            "slackware" => Provider::Slackpkg,
            "openwrt" => Provider::Opkg,
            "mageia" | "mandriva" => Provider::Urpmi,
            "guix" | "guix-system" => Provider::Guix,
            "aeryn" | "aerynos" | "serpentos" => Provider::Moss,
            "slitaz" => Provider::Tazpkg,
            "crux" => Provider::PrtGet,
            _ => continue,
        };
        return Some(provider);
    }
    None
}

impl Action {
    const fn label(self) -> &'static str {
        match self {
            Self::Install => "install",
            Self::Search => "search",
            Self::Info => "info",
            Self::Remove => "remove",
            Self::Update => "update",
            Self::List => "list",
        }
    }
}

impl CommandSpec {
    fn new(program: &'static str, args: &[&str], elevated: bool) -> Self {
        Self {
            program,
            args: args.iter().map(|arg| (*arg).to_owned()).collect(),
            elevated,
        }
    }

    pub fn display(&self) -> String {
        let mut output = String::new();
        if self.elevated && unsafe { libc::geteuid() } != 0 {
            output.push_str(elevation_program().unwrap_or("sudo"));
            output.push(' ');
        }
        output.push_str(self.program);
        for arg in &self.args {
            output.push(' ');
            shell_quote_into(&mut output, arg);
        }
        output
    }

    pub fn execute(&self) -> Result<()> {
        let needs_sudo = self.elevated && unsafe { libc::geteuid() } != 0;
        let (mut command, launcher) = if needs_sudo {
            let helper = elevation_program().context(
                "this operation requires root; install sudo or doas, or run grab as root",
            )?;
            let mut command = Command::new(helper);
            command.arg(self.program);
            (command, helper)
        } else {
            (Command::new(self.program), self.program)
        };
        let status = command
            .tap_nix_cache_fallback(self.program)
            .args(&self.args)
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status()
            .with_context(|| format!("could not start {launcher}"))?;
        if !status.success() {
            bail!("{} exited with {status}", self.program);
        }
        Ok(())
    }

    fn success_silent(&self) -> Result<bool> {
        Command::new(self.program)
            .args(&self.args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .with_context(|| format!("could not start {}", self.program))
            .map(|status| status.success())
    }
}

trait NixCacheFallback {
    fn tap_nix_cache_fallback(&mut self, program: &str) -> &mut Self;
}

impl NixCacheFallback for Command {
    fn tap_nix_cache_fallback(&mut self, program: &str) -> &mut Self {
        if program == "nix" && env::var_os("XDG_CACHE_HOME").is_none() {
            let cache_home =
                env::temp_dir().join(format!("tinypm-nix-cache-{}", unsafe { libc::geteuid() }));
            if fs::create_dir_all(cache_home.join("nix")).is_ok() {
                self.env("XDG_CACHE_HOME", cache_home);
            }
        }
        self
    }
}

fn elevation_program() -> Option<&'static str> {
    ["sudo", "doas"]
        .into_iter()
        .find(|program| executable_exists(program))
}

pub fn resolve_alias(provider: Provider, package: &str) -> String {
    resolve_package(provider, package).resolved
}

pub fn resolve_package(provider: Provider, package: &str) -> PackageResolution {
    include_str!("share/tinypm/aliases.tsv")
        .lines()
        .filter(|line| !line.starts_with('#'))
        .filter_map(|line| {
            let mut fields = line.split('\t');
            Some((
                fields.next()?,
                fields.next()?,
                fields.next()?,
                fields.next()?,
            ))
        })
        .find(|(name, requested, _, _)| *name == provider_key(provider) && *requested == package)
        .map_or_else(
            || PackageResolution {
                resolved: package.to_owned(),
                reason: None,
            },
            |(_, _, resolved, reason)| PackageResolution {
                resolved: resolved.to_owned(),
                reason: Some(reason),
            },
        )
}

const fn provider_key(provider: Provider) -> &'static str {
    match provider {
        Provider::Auto => "auto",
        Provider::Apt => "apt",
        Provider::Dnf => "dnf",
        Provider::Pacman => "pacman",
        Provider::Apk => "apk",
        Provider::Zypper => "zypper",
        Provider::Xbps => "xbps",
        Provider::Portage => "portage",
        Provider::Eopkg => "eopkg",
        Provider::Swupd => "swupd",
        Provider::Slackpkg => "slackpkg",
        Provider::Opkg => "opkg",
        Provider::Urpmi => "urpmi",
        Provider::Guix => "guix",
        Provider::Moss => "moss",
        Provider::Tazpkg => "tazpkg",
        Provider::PrtGet => "prt-get",
        Provider::Flatpak => "flatpak",
        Provider::Snap => "snap",
        Provider::Nix => "nix",
        Provider::Brew => "brew",
    }
}

fn executable_exists(executable: &str) -> bool {
    find_executable(executable).is_some()
}

fn find_executable(executable: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|path| {
        std::env::split_paths(&path)
            .map(|dir| dir.join(executable))
            .find(|candidate| is_executable(candidate))
    })
}

#[cfg(unix)]
fn is_executable(path: &std::path::Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .is_ok_and(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
}

#[cfg(not(unix))]
fn is_executable(path: &std::path::Path) -> bool {
    path.is_file()
}

fn shell_quote_into(output: &mut String, value: &str) {
    if value
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || "_@%+=:,./#-".contains(ch))
    {
        output.push_str(value);
        return;
    }
    output.push('\'');
    for ch in value.chars() {
        if ch == '\'' {
            output.push_str("'\\''");
        } else {
            let _ = output.write_char(ch);
        }
    }
    output.push('\'');
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aliases_are_provider_specific() {
        assert_eq!(resolve_alias(Provider::Pacman, "gcc++"), "gcc");
        assert_eq!(resolve_alias(Provider::Dnf, "gcc++"), "gcc-c++");
        assert_eq!(resolve_alias(Provider::Apk, "curl"), "curl");
        let resolution = resolve_package(Provider::Pacman, "gcc++");
        assert!(resolution.is_alias());
        assert_eq!(resolution.resolved, "gcc");
        assert_eq!(
            resolution.reason,
            Some("Arch provides GCC and G++ together in the gcc package")
        );
        let passthrough = resolve_package(Provider::Pacman, "curl");
        assert!(!passthrough.is_alias());
        assert_eq!(passthrough.reason, None);
    }

    #[test]
    fn apt_install_command_is_safe_and_predictable() {
        let spec = Provider::Apt
            .command(Action::Install, &["weird package".into()])
            .unwrap();
        assert!(
            spec.display()
                .ends_with("apt-get install -y 'weird package'")
        );
    }

    #[test]
    fn nix_uses_modern_profiles() {
        let spec = Provider::Nix
            .command(Action::Install, &["ripgrep".into()])
            .unwrap();
        assert_eq!(spec.args.last().unwrap(), "nixpkgs#ripgrep");
    }

    #[test]
    fn apt_update_refreshes_metadata_before_upgrading() {
        let plan = Provider::Apt.plan(Action::Update, &[]).unwrap();
        assert_eq!(plan.len(), 2);
        assert!(plan[0].display().ends_with("apt-get update"));
        assert!(plan[1].display().ends_with("apt-get upgrade -y"));
    }

    #[test]
    fn apk_update_refreshes_indexes_before_upgrading() {
        let plan = Provider::Apk.plan(Action::Update, &[]).unwrap();
        assert_eq!(plan.len(), 2);
        assert!(plan[0].display().ends_with("apk update"));
        assert!(plan[1].display().ends_with("apk upgrade"));
    }

    #[test]
    fn info_uses_provider_metadata_command() {
        let apt = Provider::Apt
            .command(Action::Info, &["curl".into()])
            .unwrap();
        assert_eq!(apt.display(), "apt-cache show curl");

        let pacman = Provider::Pacman
            .command(Action::Info, &["curl".into()])
            .unwrap();
        assert_eq!(pacman.display(), "pacman -Si curl");

        let moss = Provider::Moss
            .command(Action::Info, &["curl".into()])
            .unwrap();
        assert_eq!(moss.display(), "moss info curl");
    }

    #[test]
    fn moss_uses_atomic_system_commands_noninteractively() {
        let install = Provider::Moss
            .command(Action::Install, &["tree".into()])
            .unwrap();
        assert!(install.elevated);
        assert_eq!(install.args, ["--yes-all", "install", "tree"]);
        let remove = Provider::Moss
            .command(Action::Remove, &["tree".into()])
            .unwrap();
        assert!(remove.elevated);
        assert_eq!(remove.args, ["--yes-all", "remove", "tree"]);
        let update = Provider::Moss.command(Action::Update, &[]).unwrap();
        assert!(update.elevated);
        assert_eq!(update.args, ["--yes-all", "sync", "--update"]);
        assert_eq!(
            Provider::Moss.command(Action::List, &[]).unwrap().display(),
            "moss list installed"
        );
    }

    #[test]
    fn tazpkg_uses_repository_and_noninteractive_commands() {
        let install = Provider::Tazpkg
            .command(Action::Install, &["nano".into()])
            .unwrap();
        assert!(install.elevated);
        assert_eq!(install.args, ["get-install", "nano"]);
        let remove = Provider::Tazpkg
            .command(Action::Remove, &["nano".into()])
            .unwrap();
        assert!(remove.elevated);
        assert_eq!(remove.args, ["remove", "--auto", "nano"]);
        let update = Provider::Tazpkg.command(Action::Update, &[]).unwrap();
        assert!(update.elevated);
        assert_eq!(update.args, ["upgrade", "--install"]);
        assert_eq!(
            Provider::Tazpkg
                .command(Action::Search, &["nano".into()])
                .unwrap()
                .display(),
            "tazpkg search nano"
        );
    }

    #[test]
    fn prt_get_uses_dependency_aware_crux_commands() {
        let install = Provider::PrtGet
            .command(Action::Install, &["nano".into()])
            .unwrap();
        assert!(install.elevated);
        assert_eq!(install.args, ["depinst", "nano"]);
        let remove = Provider::PrtGet
            .command(Action::Remove, &["nano".into()])
            .unwrap();
        assert!(remove.elevated);
        assert_eq!(remove.args, ["remove", "nano"]);
        let update = Provider::PrtGet.command(Action::Update, &[]).unwrap();
        assert!(update.elevated);
        assert_eq!(update.args, ["sysup"]);
        assert_eq!(
            Provider::PrtGet
                .command(Action::List, &[])
                .unwrap()
                .display(),
            "prt-get listinst"
        );
    }

    #[test]
    fn os_release_maps_distribution_families() {
        assert_eq!(
            preferred_from_os_release("ID=ubuntu\nID_LIKE=debian\n"),
            Some(Provider::Apt)
        );
        assert_eq!(
            preferred_from_os_release("ID=endeavouros\nID_LIKE=arch\n"),
            Some(Provider::Pacman)
        );
        assert_eq!(
            preferred_from_os_release("ID=opensuse-tumbleweed\nID_LIKE=opensuse suse\n"),
            Some(Provider::Zypper)
        );
        assert_eq!(preferred_from_os_release("ID=unknown\n"), None);
        assert_eq!(
            preferred_from_os_release("ID=gentoo\n"),
            Some(Provider::Portage)
        );
        assert_eq!(
            preferred_from_os_release("ID=funtoo\nID_LIKE=gentoo\n"),
            Some(Provider::Portage)
        );
        assert_eq!(
            preferred_from_os_release("ID=openwrt\n"),
            Some(Provider::Opkg)
        );
        assert_eq!(
            preferred_from_os_release("ID=mageia\n"),
            Some(Provider::Urpmi)
        );
        assert_eq!(
            preferred_from_os_release("ID=aerynos\n"),
            Some(Provider::Moss)
        );
        assert_eq!(
            preferred_from_os_release("ID=serpentos\n"),
            Some(Provider::Moss)
        );
        assert_eq!(
            preferred_from_os_release("ID=slitaz\n"),
            Some(Provider::Tazpkg)
        );
        assert_eq!(
            preferred_from_os_release("ID=crux\n"),
            Some(Provider::PrtGet)
        );
        assert_eq!(
            preferred_from_os_release("ID=artix\nID_LIKE=arch\n"),
            Some(Provider::Pacman)
        );
        assert_eq!(
            preferred_from_os_release("ID=postmarketos\nID_LIKE=alpine\n"),
            Some(Provider::Apk)
        );
    }

    #[test]
    fn os_release_prefers_admin_file_and_falls_back_to_vendor_file() {
        let root = tempfile::tempdir().unwrap();
        let admin = root.path().join("etc-os-release");
        let vendor = root.path().join("usr-lib-os-release");
        std::fs::write(&vendor, "ID=aerynos\n").unwrap();
        assert_eq!(
            read_os_release_from(&[&admin, &vendor]),
            Some("ID=aerynos\n".to_owned())
        );
        std::fs::write(&admin, "ID=arch\n").unwrap();
        assert_eq!(
            read_os_release_from(&[&admin, &vendor]),
            Some("ID=arch\n".to_owned())
        );
    }

    #[test]
    fn every_provider_has_a_plan_for_every_core_action() {
        for provider in Provider::supported() {
            for action in [
                Action::Install,
                Action::Search,
                Action::Info,
                Action::Remove,
                Action::Update,
                Action::List,
            ] {
                let values = if matches!(action, Action::Update | Action::List) {
                    &[][..]
                } else {
                    &["example".to_owned()][..]
                };
                let plan = provider.plan(action, values).unwrap_or_else(|error| {
                    panic!("{} {} plan failed: {error}", provider.key(), action.label())
                });
                assert!(
                    !plan.is_empty(),
                    "{} {} plan is empty",
                    provider.key(),
                    action.label()
                );
            }
        }
    }

    #[test]
    fn provider_validation_levels_are_explicit() {
        for provider in Provider::supported() {
            assert!(matches!(
                provider.validation_level(),
                "transaction-tested" | "command-contract"
            ));
        }
        assert_eq!(Provider::Apk.validation_level(), "transaction-tested");
        assert_eq!(Provider::Moss.validation_level(), "command-contract");
    }
}
