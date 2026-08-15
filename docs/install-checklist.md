# Abora Install Checklist

Use this after building a release candidate ISO and after running one real install.

## Live Session

- ISO reaches the live boot flow without dropping to an emergency shell
- live boot flow opens on `tty1`
- NetworkManager starts before the installer network step
- installer opens without dropping into a shell first
- Omarchy-inspired welcome screen appears before disk/account questions
- networking works in the live session
- `/etc/abora/setup.desktop` exists
- `/etc/abora/setup-launcher.sh` exists and is executable
- `/etc/abora/default-wallpaper.png` exists
- `/etc/abora/wallpapers/` contains the curated wallpaper set
- Fastfetch shows the Abora logo
- `abora gaming status` opens without a missing-command error

## VM Coverage

- QEMU fresh install works end to end with `make qemu-fresh`
- installed disk boots with `make qemu-disk`
- at least one Windows-host VM run is checked in VMware or Hyper-V when possible
- if testing Hyper-V Generation 2, secure boot is disabled
- if testing VirtualBox, boot is checked with default graphics settings first

## Installer

- MINT renders with color on `tty1`
- Abora text/logo appears without a `logo not found` fallback
- first screen offers Open terminal, Debug installer, and Build from source
- preflight failure offers Network tools, Debug tools, Open terminal, and retry
- Debug installer can show recent install/config logs before partitioning
- Build from source shows `make doctor`, `make iso`, and `make iso-all`
- network step can open `nmtui`
- network step can run Quick Wi-Fi connect without `nmtui`
- network step can turn Wi-Fi on and rescan
- disk selection and user creation remain interactive
- password mismatch recovery works
- GitHub login can be skipped cleanly
- generated config validation runs before `nixos-install`
- optional Gaming setup can be skipped cleanly
- optional Desktop Gaming + Big Picture writes the expected gaming settings
- install progress reaches the install phase
- install completes without fatal errors
- failed installs show useful recent log output
- failed installs offer Try installer again, Network tools, Debug tools, terminal, and power off
- `/tmp/abora-install.log` and `/tmp/abora-config.log` are present on failure
- `/tmp/abora-install.log` contains `network snapshot start`

## Failure Capture

When a tester reports a failed install, ask for:

```sh
abora bug-report
abora bug-report --github --web
abora logs --lines 200
cat /tmp/abora-install.log
cat /tmp/abora-config.log
abora network
abora support-report
```

If the system installed but updates or Wi-Fi fail after boot:

```sh
abora bug-report
abora bug-report --github --web
abora logs --lines 200
abora network
abora check-full
abora support-report
```

## ANIX Languages

- `anix language list` shows ANIX Native, MAKO, and ModuCPP
- `anix run examples/anix-v2/simple.anix --yes` works in a test config
- `anix diff-plan examples/anix-v2/workstation.mko` resolves through MAKO when `mko` is installed
- `anix diff-plan examples/anix-v2/workstation.moducpp` resolves through `moducpp-anix`

## Installed System

- installed system boots without the ISO attached
- bootloader starts without manual repair
- login prompt starts
- networking is enabled and functional
- `abora setup` launches the installed reconfiguration tool
- `tinypm` and `grab` are available
- `abora gaming status` and `abora gaming doctor` run after install
- on GNOME installs, Abora wallpapers appear in `Settings -> Appearance`
- on every supported desktop, first login starts on the Abora default wallpaper
- on GNOME installs, picking an Abora wallpaper updates accent/style automatically

## Bug Report

Collect:

```sh
abora bug-report
abora bug-report --github --web
abora logs --lines 200
abora network
abora support-report
journalctl -b --no-pager
```

Attach the generated support archive and installer logs if available.
Use [Bug Report Template](bug-report-template.md) for full reports.

For release screenshots, use [Screenshot Checklist](screenshots.md).
