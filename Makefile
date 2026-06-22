.PHONY: help iso iso-local qemu qemu-disk qemu-fresh qemu-serial qemu-fresh-serial qemu-debug qemu-fresh-debug qmec qemc check check-desktops preflight metadata release tinypm-package anix-package tinypm-image

help:
	@echo "Usage: make <target>"
	@echo "Targets:"
	@echo "  iso              - Build only the ISO"
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
	@echo "  check            - Run repository script checks"
	@echo "  check-desktops   - Evaluate every supported desktop profile"
	@echo "  preflight        - Run full release preflight checks"

iso:
	./scripts/build-iso.sh

metadata:
	./scripts/release-metadata.sh

tinypm-package:
	./scripts/package-tinypm.sh

anix-package:
	./scripts/package-anix.sh

tinypm-image:
	./scripts/build-tinypm-image.sh

release: iso tinypm-package anix-package metadata

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

check:
	./scripts/check-scripts.sh

check-desktops:
	./scripts/check-desktops.sh

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
