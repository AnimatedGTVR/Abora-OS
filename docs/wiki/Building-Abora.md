# Building Abora

A NixOS system with flakes enabled is recommended.

```sh
git clone https://github.com/AnimatedGTVR/Abora-OS.git
cd Abora-OS
make doctor
make check
make iso
```

Useful targets:

```sh
make iso-all       # all desktop editions
make qemu-fresh    # clean VM installation
make qemu-disk     # boot the installed VM disk
make release       # complete release bundle
```

Build work belongs on `edge`. Do not publish an ISO until the checks pass and at least one clean install, reboot, update, and rollback have been tested.
