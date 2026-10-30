.PHONY: help iso iso-local build-vm run qemu qemu-disk qemu-fresh qemu-serial qemu-fresh-serial qemu-debug qemu-fresh-debug qmec qemc doctor desktop-preview check check-desktops check-all preflight metadata release anix-package test-welcome test-config

help:
	@echo "Usage: make <target>"
	@echo "Targets:"
	@echo "  doctor           - Check your dev machine is ready to build Abora (run this first)"
	@echo "  desktop-preview  - Print Abora's NixOS config/packages for a desktop profile (PROFILE=gnome), no install needed"
	@echo "  iso              - Build the universal Abora installer ISO"
	@echo "  metadata         - Generate release notes, manifest, and checksums"
	@echo "  anix-package     - Build the ANIX standalone tarball"
	@echo "  release          - Build the ISO, ANIX package, and refresh the release bundle"
	@echo "  build-vm         - Clean-checkout ISO build for a dedicated build VM (clones/pulls a fresh copy, ignores local changes)"
	@echo "  qemu             - Boot the latest ISO in QEMU (graphical window)"
	@echo "  run              - Alias for qemu"
	@echo "  qemu-fresh       - Delete old disk image, then boot the ISO (clean install test)"
	@echo "  qemu-disk        - Boot the installed QEMU hard drive without the ISO"
	@echo "  qemu-serial      - Boot in headless mode — all output in this terminal"
	@echo "  qemu-fresh-serial- Fresh disk + headless mode"
	@echo "  qemu-debug       - Graphical QEMU plus live serial output in this terminal"
	@echo "  qemu-fresh-debug - Fresh disk + graphical QEMU + terminal serial output"
	@echo "  qmec / qemc      - Aliases for qemu"
	@echo "  test-welcome     - Run the Abora Welcome GUI from source (no ISO build needed)"
	@echo "  test-config      - Run the Abora Config Editor GUI against a throwaway fixture config"
	@echo "  check            - Run repository script checks"
	@echo "  check-desktops   - Evaluate every supported desktop profile"
	@echo "  check-all        - Sweep every .sh/.nix/.py/.md file in the repo by type"
	@echo "  preflight        - Run full release preflight checks"

iso:
	./scripts/build-iso.py

metadata:
	./scripts/release-metadata.py

anix-package:
	./scripts/package-anix.py

release: iso anix-package metadata

build-vm:
	./scripts/rebuild-vm.py

qemu:
	./scripts/run-qemu.py

run: qemu

qemu-fresh:
	ABORA_QEMU_FRESH=1 ./scripts/run-qemu.py

qemu-disk:
	ABORA_QEMU_BOOT=disk ./scripts/run-qemu.py

qemu-serial:
	ABORA_QEMU_NOGRAPHIC=1 ./scripts/run-qemu.py

qemu-fresh-serial:
	ABORA_QEMU_FRESH=1 ABORA_QEMU_NOGRAPHIC=1 ./scripts/run-qemu.py

qemu-debug:
	ABORA_QEMU_SERIAL_STDIO=1 ./scripts/run-qemu.py

qemu-fresh-debug:
	ABORA_QEMU_FRESH=1 ABORA_QEMU_SERIAL_STDIO=1 ./scripts/run-qemu.py

qmec: qemu

qemc: qemu

test-welcome:
	python3 scripts/abora-welcome-gui.py

test-config:
	@tmp="$$(mktemp -d)"; \
	cp scripts/test-fixtures/abora-local.nix "$$tmp/abora-local.nix"; \
	ABORA_SYSTEM_CONFIG="$$tmp" ABORA_CONFIG_SCRIPT="$(CURDIR)/scripts/abora-config.sh" \
		python3 scripts/abora-config-gui.py; \
	rm -rf "$$tmp"

doctor:
	./scripts/dev-doctor.py

desktop-preview:
	@[ -n "$(PROFILE)" ] || { echo "Usage: make desktop-preview PROFILE=gnome [XKB=us] [DESKTOP_USER=user]"; exit 1; }
	./scripts/abora-desktop-preview.sh "$(PROFILE)" "$(or $(XKB),us)" "$(or $(DESKTOP_USER),user)"

check:
	./scripts/check-scripts.py

check-desktops:
	./scripts/check-desktops.py

check-all:
	./scripts/check-all-files.py

preflight:
	./scripts/preflight.py

