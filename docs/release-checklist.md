# Release Checklist

- version, release notes, download page, and visible branding agree
- repository checks pass
- all supported edition ISOs build
- checksums and release metadata are generated and verified
- live boot succeeds in supported firmware modes
- clean installation, reboot, update, and rollback succeed
- automatic, manual, and existing-partition paths protect unrelated data
- installer failures preserve actionable logs
- graphics, network, audio, suspend, and multi-monitor basics are tested where hardware is available
- Stable contains no intentionally unfinished feature
- known issues and upgrade instructions are published

Commands:

```sh
make doctor
make check
make iso-all
make release
```

A calendar date does not override a failed release gate.
