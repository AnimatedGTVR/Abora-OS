# Provider support matrix

TinyPM treats provider support as a tested contract, not only a command-name
mapping. Every provider below has install, search, info, remove, update, and
installed-list plans covered by Rust tests. `tinypm doctor` additionally checks
the executables required by the selected backend.

| Provider | Primary systems | Validation level |
| --- | --- | --- |
| APT | Debian, Ubuntu and derivatives | Real container install/remove/undo |
| DNF | Fedora, RHEL-family and derivatives | Real container install/remove/undo |
| Pacman | Arch and derivatives | Real host inspection and real container install/remove/undo |
| APK | Alpine, postmarketOS, Adélie, Chimera | Real container install/remove/undo; CI regression |
| Zypper | openSUSE and SLE | Real container install/remove/undo |
| XBPS | Void Linux | Command contract; real-system testing needed |
| Portage | Gentoo and Funtoo | Command contract; real-system testing needed |
| eopkg | Solus | Command contract; real-system testing needed |
| swupd | Clear Linux | Command contract; real-system testing needed |
| slackpkg | Slackware | Command contract; real-system testing needed |
| opkg | OpenWrt | Command contract; real-system testing needed |
| URPMI | Mageia-family systems | Command contract; real-system testing needed |
| Guix | GNU Guix System and foreign installations | Command contract; real-system testing needed |
| Moss | AerynOS | Current upstream CLI contract; real-system testing needed |
| TazPkg | SliTaz | Official CLI contract; real-system testing needed |
| prt-get | CRUX | Official CLI contract; real-system testing needed |
| Flatpak | Cross-distribution applications | Command contract; real-system testing needed |
| Snap | Cross-distribution applications | Command contract; real-system testing needed |
| Nix | NixOS and foreign installations | Command contract; real-system testing needed |
| Homebrew | Linuxbrew | Command contract; real-system testing needed |

“Command contract” means argument-vector generation, dry-run behavior, provider
selection, safety validation, and registry reporting are automated. It does not
claim that a real package transaction has been exercised on that system yet.

## Adding another provider

A new provider must have authoritative, current documentation for all six core
actions and a noninteractive mutation mode. It must also define executable
health checks, distro detection identifiers where applicable, dry-run coverage,
and exact command tests. Real-system or disposable-image testing is required
before its validation level can be promoted.

PiSi and Source Mage are candidates, but they remain intentionally unsupported
until their current noninteractive transaction behavior can be verified from
maintained primary sources or a real test system.
