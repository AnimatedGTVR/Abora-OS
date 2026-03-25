.PHONY: help iso iso-local qemu qmec qemc check

help:
	@echo "Usage: make <target>"
	@echo "Targets:"
	@echo "  iso       - Build the real Nix ISO"
	@echo "  qemu      - Boot the latest ISO in QEMU"
	@echo "  qmec      - Alias for qemu"
	@echo "  qemc      - Alias for qemu"
	@echo "  check     - Run repository script checks"

iso:
	./scripts/build-iso.sh

qemu:
	./scripts/run-qemu.sh

qmec: qemu

qemc: qemu

check:
	./scripts/check-scripts.sh
