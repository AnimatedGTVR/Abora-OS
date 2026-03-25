.PHONY: help iso iso-local qemu qmec qemc check metadata release

help:
	@echo "Usage: make <target>"
	@echo "Targets:"
	@echo "  iso       - Build the real Nix ISO"
	@echo "  iso-local - Build a minimal local ISO without Nix"
	@echo "  metadata  - Generate release notes, manifest, and checksums for the current version"
	@echo "  release   - Build the ISO and refresh the release bundle"
	@echo "  qemu      - Boot the latest ISO in QEMU"
	@echo "  qmec      - Alias for qemu"
	@echo "  qemc      - Alias for qemu"
	@echo "  check     - Run repository script checks"

iso:
	./scripts/build-iso.sh

iso-local:
	./scripts/build-iso-local.sh

metadata:
	./scripts/release-metadata.sh

release:
	./scripts/build-iso.sh

qemu:
	./scripts/run-qemu.sh

qmec: qemu

qemc: qemu

check:
	./scripts/check-scripts.sh
