# ANIX

ANIX is Abora's system-management layer. It provides shorter workflows for profiles, generations, snapshots, testing, and rollback without replacing Nix or NixOS.

```sh
anix status
anix doctor
anix generations
anix save "before change"
anix diff nix gaming
anix test nix gaming
anix switch nix gaming
anix rollback nix
```

Use `anix --help` for the commands installed by your release. Prefer `diff` or `test` before switching a profile, and create a snapshot before large configuration changes.
