# Install Checklist

## Live image

- boots in the intended firmware mode
- starts NetworkManager and the installer
- detects input, displays, network, and internal disks
- does not confuse install media with a target disk
- includes required Abora assets and commands

## Installer

- validates identity, passwords, timezone, keyboard, desktop, and GPU choices
- clearly distinguishes automatic, manual, and existing-partition modes
- shows the exact target before formatting
- validates generated configuration before `nixos-install`
- preserves `/tmp/abora-install.log` and `/tmp/abora-config.log` on failure
- offers useful recovery actions instead of a blank failure screen

## Installed system

- boots without the ISO
- reaches the selected desktop and login
- connects to the network and produces audio
- `abora doctor`, `anix doctor`, and `tinypm doctor` complete
- update and rollback work
- desktop, GPU, and boot configuration match the installer choices

Test every main edition in a VM and at least the default edition on real hardware before release.
