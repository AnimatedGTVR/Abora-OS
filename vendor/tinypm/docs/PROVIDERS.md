# Provider Support

TinyPM selects an available provider from its catalog and host detection. Nix is preferred on Abora and NixOS. Other supported families include Flatpak, APT, DNF, Pacman, Zypper, APK, Homebrew, and Snap.

A provider implementation must define detection, package-name mapping where required, install/remove/update commands, availability checks, privilege behavior, and tests. Use argument arrays and keep dry-run output identical to the command that would execute.
