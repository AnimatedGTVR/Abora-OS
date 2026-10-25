# Recovery

Start with:

```sh
abora doctor
abora logs --lines 200
abora network
anix status
```

## Roll back

```sh
sudo abora rollback
# or
anix generations
anix rollback nix
```

## Test or rebuild

```sh
anix diff nix abora
anix test nix abora
sudo nixos-rebuild switch --flake /etc/nixos#abora
```

Use `abora recovery` for guided repair options. Before asking for help, create `abora support-report` and review the archive for private information.

If the system will not boot, choose an older generation from the boot menu. You can also boot an Abora ISO, mount the installed root partition, and inspect `/mnt/etc/nixos` and the installer logs.
