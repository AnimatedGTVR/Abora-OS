.PHONY: help iso iso-local qemu qemu-disk qemu-fresh qemu-serial qemu-fresh-serial qmec qemc check check-desktops preflight metadata release tinypm-package tinypm-image

help:
	@echo "Usage: make <target>"
	@echo "Targets:"
	@echo "  iso              - Build only the ISO"
	@echo "  metadata         - Generate release notes, manifest, and checksums"
	@echo "  tinypm-package   - Build the TinyPM release tarball"
	@echo "  tinypm-image     - Build the TinyPM GHCR container image locally"
	@echo "  release          - Build the ISO, TinyPM package, and refresh the release bundle"
	@echo "  qemu             - Boot the latest ISO in QEMU (graphical window)"
	@echo "  qemu-fresh       - Delete old disk image, then boot the ISO (clean install test)"
	@echo "  qemu-disk        - Boot the installed QEMU hard drive without the ISO"
	@echo "  qemu-serial      - Boot in headless mode — all output in this terminal"
	@echo "  qemu-fresh-serial- Fresh disk + headless mode"
	@echo "  qmec / qemc      - Aliases for qemu"
	@echo "  check            - Run repository script checks"
	@echo "  check-desktops   - Evaluate every supported desktop profile"
	@echo "  preflight        - Run full release preflight checks"

iso:
	./scripts/build-iso.sh

metadata:
	./scripts/release-metadata.sh

tinypm-package:
	./scripts/package-tinypm.sh

tinypm-image:
	./scripts/build-tinypm-image.sh

release: iso tinypm-package metadata

qemu:
	./scripts/run-qemu.sh

qemu-fresh:
	ABORA_QEMU_FRESH=1 ./scripts/run-qemu.sh

qemu-disk:
	ABORA_QEMU_BOOT=disk ./scripts/run-qemu.sh

qemu-serial:
	ABORA_QEMU_NOGRAPHIC=1 ./scripts/run-qemu.sh

qemu-fresh-serial:
	ABORA_QEMU_FRESH=1 ABORA_QEMU_NOGRAPHIC=1 ./scripts/run-qemu.sh

qmec: qemu

qemc: qemu

check:
	./scripts/check-scripts.sh

check-desktops:
	./scripts/check-desktops.sh

preflight:
	./scripts/preflight.sh
