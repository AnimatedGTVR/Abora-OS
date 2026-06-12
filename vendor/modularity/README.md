# Modularity (Tareno Labs)

Modularity is a game engine editor for 2D and 3D projects.

The prebuilt binary is not committed to this repository. Run the setup target to extract it from the official release zip before building.

## Setup

Download `Modularity-1.0.0-Linux.zip` from:
https://pak.moduengine.xyz/Tareno-Labs-LLC/Modularity/releases/tag/Modularity-6.8.1-PreRelease

Then run:

```sh
make setup-modularity ZIP=/path/to/Modularity-1.0.0-Linux.zip
```

This extracts the runtime binary and shared libraries into `vendor/modularity/bin/` and `vendor/modularity/lib/`, which are gitignored.

## What gets extracted

- `bin/Modularity` — the engine editor executable
- `lib/libPhysX*.so` — bundled PhysX physics libraries
- `share/modularity/Resources/` — GLSL and Vulkan shaders (already committed)

## Nix package

The Nix derivation is at `nix/pkgs/modularity.nix`. It uses `autoPatchelfHook` to fix ELF library paths and wraps the binary so it launches with the correct working directory.

Build it standalone with:

```sh
nix build .#modularity
```
