# Release Guide

1. Update `VERSION`, release notes, and visible version references.
2. Run `make doctor` and `make check`.
3. Build every edition with `make iso-all`.
4. Perform a clean install and first boot on a VM and real hardware when available.
5. Test networking, GPU selection, update, recovery, and rollback.
6. Build the bundle with `make release`.
7. Verify generated checksums and release metadata.
8. Tag and publish only after the release checklist passes.

```sh
git tag "v$VERSION"
git push origin "v$VERSION"
```

See the [release checklist](../release-checklist.md) and [install checklist](../install-checklist.md). Keep Stable conservative; unfinished changes remain on Edge.
