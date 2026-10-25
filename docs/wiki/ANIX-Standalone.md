# ANIX on an Existing NixOS System

The supported way to add Abora and ANIX to an existing NixOS installation is the adoption wizard described in [Installation](Installation.md#existing-nixos-systems).

```sh
git clone --branch edge https://github.com/AnimatedGTVR/Abora-OS.git
cd Abora-OS
./abora adopt-nixos
```

Review the generated plan. The wizard preserves a backup under `/etc/nixos/abora-backups/`; it does not make an existing installation risk-free. Test the configuration before switching:

```sh
sudo nixos-rebuild test --flake /etc/nixos#abora
sudo nixos-rebuild switch --flake /etc/nixos#abora
```
