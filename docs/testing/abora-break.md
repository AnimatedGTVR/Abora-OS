# abora-break: break a test VM on purpose

`testing/abora-break` breaks an installed Abora **test VM** in the ways release-gate row 9 needs, so
`anix doctor` and `anix doctor repair` can be tested. It is a harness tool: it runs on your machine and
reaches the VM over SSH. It is never built into the ISO, the installer, the Nix modules or anything copied
to a user's machine, and `make check` fails if any of those mention it. The script it sends stops unless
`systemd-detect-virt --vm` reports a virtual machine.

## Setup

1. Install Abora in QEMU and forward SSH, for example `-netdev user,id=n0,hostfwd=tcp::2222-:22`.
2. On the VM, set `anix.services.openssh = true;` in `/etc/nixos/anix.nix`, run `anix apply`, and add your
   SSH key. The user needs passwordless `sudo` (or use `root`).
3. Build the tool: `cargo build --manifest-path testing/abora-break/Cargo.toml`.

## Use

```sh
abora-break list                                          # faults and the finding each should cause
abora-break --ssh abora@localhost --port 2222 failed-unit # break
abora-break --ssh abora@localhost --port 2222 restore failed-unit
abora-break --print stopped-dns                           # show the script, run nothing
```

| Fault | What it does | `anix doctor` should report |
| --- | --- | --- |
| `full-esp` | fills `/boot` until 32 MB is free (UEFI only) | `boot-space` warn, repair `gc-generations` |
| `stopped-dns` | points `/etc/resolv.conf` at `192.0.2.1`; the route stays up | `network-dns` fail, repair `restart-networkmanager` (restarts NetworkManager, then `resolvconf -u`) |
| `failed-unit` | starts `abora-break-test`, a unit that exits 1 | `services` fail, repair `reset-failed` |
| `wrong-gpu` | sets `abora.gpu` to a driver the VM doesn't load | `gpu-driver` fail (QEMU's virtio GPU isn't detected, so this needs a passed-through GPU) |
| `missing-abora-file` | removes `/etc/abora/theme-sync.sh` | `abora-file-theme-sync.sh` fail, repair `rebuild` |
| `read-only-root` | emergency read-only remount (SysRq u); `restore` reboots the VM, since ext4 won't go back to read-write | `disk-readonly` fail |

For each fault: break it, run `anix doctor`, check the finding, run `anix doctor repair` where one is
offered, run `anix doctor` again, then `restore` whatever the repair didn't undo. Backups are kept in
`/var/lib/abora-break` on the VM, so `restore` also works after a reboot. Record the results in
[the release plan](../next-release-plan.md#validation-results).
