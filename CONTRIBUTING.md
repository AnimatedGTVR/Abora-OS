# Contributing to Abora OS

First of all, thank you for taking the time to contribute to Abora OS.

Whether you're fixing a bug, improving documentation, testing a new feature, creating artwork, or helping other users, your contribution is appreciated.

Abora OS is a community-driven Linux distribution built on NixOS with the goal of making it easier to install, use, and understand. Every contribution helps move the project forward.

---

# Before You Start

Before working on a feature or fix, make sure you can successfully build and boot Abora OS.

Build the ISO:

```sh
make iso
```

Boot the latest build in QEMU:

```sh
make qemu
```

Run the project's checks:

```sh
make check
```

If something doesn't build before you make changes, it's usually best to ask before spending time debugging something unrelated to your work.

---

# Repository Layout

Some of the most important directories are:

* `assets/`  Wallpapers, branding, icons, Plymouth themes, and other artwork.
* `docs/`  Documentation, release notes, guides, and project information.
* `nix/`  NixOS modules and system configuration.
* `scripts/`  Build tools, installer scripts, release helpers, and utilities.
* `vendor/` Third-party projects bundled with Abora OS.

As the project grows, additional directories may be added. If you're unsure where something belongs, feel free to ask.

---

# Pull Requests

Please try to keep pull requests focused on a single change.

Good examples include:

* Fixing one bug
* Adding one feature
* Updating documentation
* Improving the installer
* Cleaning up a specific part of the codebase

Large pull requests that combine unrelated changes are much harder to review.

Before opening a pull request:

* Make sure the project still builds.
* Test your changes whenever possible.
* Update documentation if your change affects users.
* Remove temporary debugging code.
* Run `make check`.

Draft pull requests are welcome if you'd like feedback before finishing your work.

---

# Commit Messages

Write commit messages that explain what changed.

Good examples:

```text
Improve installer error handling
Update NVIDIA driver packages
Fix Plymouth splash timeout
Add COSMIC desktop option
```

Avoid commit messages like:

```text
update
fix
changes
misc
```

Clear commit messages make the project's history much easier to understand.


---

# Coding Style

If `git push origin edge` (or `stable`) is rejected because the remote moved first, the safe flow is:

```sh
git add -A
git commit -m "Describe your change"
git pull --rebase origin edge
git push origin edge
```

---

# Thank You

Open-source projects only exist because people are willing to spend their time improving them.

Whether you've fixed a typo, reported a bug, tested a release, or contributed code, thank you for helping make Abora OS better.
