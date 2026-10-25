# Modularity (Tareno Labs)

Modularity is a game engine editor for 2D and 3D projects.

The prebuilt binary is not committed to this repository. Run the setup target to extract it from the official release zip before building.

## Setup

Download the Modularity V7 Linux zip from the Tareno Labs release page:
https://pak.moduengine.xyz/Tareno-Labs-LLC/Modularity

Then run:

```sh
make setup-modularity ZIP=/path/to/Modularity-7.0.0-Linux.zip
```

If the zip uses a different top-level folder name, override it:

```sh
make setup-modularity ZIP=/path/to/modularity-v7-linux.zip MODULARITY_ZIP_ROOT=Modularity-V7-Linux
```

This extracts the runtime binary and shared libraries into `vendor/modularity/bin/` and `vendor/modularity/lib/`, which are gitignored.

## What gets extracted

- `bin/Modularity` — the engine editor executable
- `lib/*.so*` — bundled runtime libraries, including PhysX when shipped by the release
- `share/modularity/Resources/` — GLSL and Vulkan shaders (already committed)

## Nix package

The Nix derivation is at `nix/pkgs/modularity.nix`. It uses `autoPatchelfHook` to fix ELF library paths and wraps the binary so it launches with the correct working directory.

Build it standalone with:

```sh
nix build .#modularity
```
