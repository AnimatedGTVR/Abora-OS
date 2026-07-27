.PHONY: help iso iso-all iso-cosmic iso-hyprland iso-gnome iso-kde iso-other iso-local qemu qemu-disk qemu-fresh qemu-serial qemu-fresh-serial qemu-debug qemu-fresh-debug qmec qemc check check-desktops check-all preflight metadata release tinypm-package anix-package tinypm-image test-installer test-installer-tty test-installer-kitty test-welcome test-config

help:
	@echo "Usage: make <target>"
	@echo "Targets:"
	@echo "  iso              - Build one ISO (defaults to Cosmic; override with ABORA_EDITION=gnome)"
	@echo "  iso-all          - Build Cosmic, Hyprland, GNOME, KDE, and Other ISOs"
	@echo "  iso-hyprland     - Build only the Hyprland ISO"
	@echo "  iso-gnome        - Build only the GNOME ISO"
	@echo "  iso-kde          - Build only the KDE Plasma ISO"
	@echo "  iso-other        - Build only the Other Desktops ISO"
	@echo "  metadata         - Generate release notes, manifest, and checksums"
	@echo "  tinypm-package   - Build the TinyPM release tarball"
	@echo "  anix-package     - Build the ANIX standalone tarball"
	@echo "  tinypm-image     - Build the TinyPM GHCR container image locally"
	@echo "  release          - Build the ISO, TinyPM package, ANIX package, and refresh the release bundle"
	@echo "  qemu             - Boot the latest ISO in QEMU (graphical window)"
	@echo "  qemu-fresh       - Delete old disk image, then boot the ISO (clean install test)"
	@echo "  qemu-disk        - Boot the installed QEMU hard drive without the ISO"
	@echo "  qemu-serial      - Boot in headless mode — all output in this terminal"
	@echo "  qemu-fresh-serial- Fresh disk + headless mode"
	@echo "  qemu-debug       - Graphical QEMU plus live serial output in this terminal"
	@echo "  qemu-fresh-debug - Fresh disk + graphical QEMU + terminal serial output"
	@echo "  qmec / qemc      - Aliases for qemu"
	@echo "  test-installer   - Run the MINT installer TUI from source, auto-detecting the terminal (no ISO build needed)"
	@echo "  test-installer-tty   - Same, but forces TTY-safe block-art rendering"
	@echo "  test-installer-kitty - Same, but forces real Kitty graphics-protocol rendering"
	@echo "  test-welcome     - Run the Abora Welcome GUI from source (no ISO build needed)"
	@echo "  test-config      - Run the Abora Config Editor GUI against a throwaway fixture config"
	@echo "  check            - Run repository script checks"
	@echo "  check-desktops   - Evaluate every supported desktop profile"
	@echo "  check-all        - Sweep every .sh/.nix/.py/.md file in the repo by type"
	@echo "  preflight        - Run full release preflight checks"

iso:
	ABORA_EDITION=$${ABORA_EDITION:-cosmic} ./scripts/build-iso.sh

iso-all:
	ABORA_EDITION=all ./scripts/build-iso.sh

iso-cosmic:
	ABORA_EDITION=cosmic ./scripts/build-iso.sh

iso-hyprland:
	ABORA_EDITION=hyprland ./scripts/build-iso.sh

iso-gnome:
	ABORA_EDITION=gnome ./scripts/build-iso.sh

iso-kde:
	ABORA_EDITION=kde ./scripts/build-iso.sh

iso-other:
	ABORA_EDITION=other ./scripts/build-iso.sh

metadata:
	./scripts/release-metadata.sh

tinypm-package:
	./scripts/package-tinypm.sh

anix-package:
	./scripts/package-anix.sh

tinypm-image:
	./scripts/build-tinypm-image.sh

release: iso-all tinypm-package anix-package metadata

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

qemu-debug:
	ABORA_QEMU_SERIAL_STDIO=1 ./scripts/run-qemu.sh

qemu-fresh-debug:
	ABORA_QEMU_FRESH=1 ABORA_QEMU_SERIAL_STDIO=1 ./scripts/run-qemu.sh

qmec: qemu

qemc: qemu

test-installer:
	cd vendor/mint && go run . abora install --pre-alpha

test-installer-tty:
	cd vendor/mint && go run . abora install --tty --pre-alpha

test-installer-kitty:
	cd vendor/mint && go run . abora install --kitty --pre-alpha

test-welcome:
	python3 scripts/abora-welcome-gui.py

test-config:
	@tmp="$$(mktemp -d)"; \
	cp scripts/test-fixtures/abora-local.nix "$$tmp/abora-local.nix"; \
	ABORA_SYSTEM_CONFIG="$$tmp" ABORA_CONFIG_SCRIPT="$(CURDIR)/scripts/abora-config.sh" \
		python3 scripts/abora-config-gui.py; \
	rm -rf "$$tmp"

check:
	./scripts/check-scripts.sh

check-desktops:
	./scripts/check-desktops.sh

check-all:
	./scripts/check-all-files.sh

preflight:
	./scripts/preflight.sh

setup-modularity:
	@[ -n "$(ZIP)" ] || { echo "Usage: make setup-modularity ZIP=/path/to/Modularity-1.0.0-Linux.zip"; exit 1; }
	@echo "Extracting Modularity from $(ZIP)..."
	@mkdir -p vendor/modularity/bin vendor/modularity/lib
	@unzip -jo "$(ZIP)" "Modularity-1.0.0-Linux/bin/Modularity" -d vendor/modularity/bin/
	@chmod +x vendor/modularity/bin/Modularity
	@unzip -jo "$(ZIP)" "Modularity-1.0.0-Linux/bin/linux.x86_64/release/libPhysX.so" \
	    "Modularity-1.0.0-Linux/bin/linux.x86_64/release/libPhysXCommon.so" \
	    "Modularity-1.0.0-Linux/bin/linux.x86_64/release/libPhysXFoundation.so" \
	    "Modularity-1.0.0-Linux/bin/linux.x86_64/release/libPhysXCooking.so" \
	    -d vendor/modularity/lib/
	@echo "Modularity ready at vendor/modularity/"
