# Project Layout

- `.github/`: issue forms and CI workflows
- `assets/`: branding, wallpapers, screenshots, and boot artwork
- `configs/`: data used by Abora tools and Labs
- `docs/`: user, tester, and release documentation
- `nix/`: NixOS modules, desktop profiles, and live-image configuration
- `scripts/`: installer, updater, recovery, build, and validation tools
- `src/`: native component source
- `vendor/`: components shipped from separate upstream projects
- `flake.nix`: system and ISO outputs
- `Makefile`: common development and release commands

Keep system configuration in Nix, shared application logic in the appropriate source component, and shell limited to small launch or compatibility tasks. Experimental work belongs in Labs until it has a defined owner, interface, tests, and migration plan.
