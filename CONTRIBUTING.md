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

Follow the existing style used throughout the project.

General guidelines:

* Write readable code.
* Keep functions reasonably small.
* Use descriptive variable names.
* Avoid unnecessary dependencies.
* Don't reformat unrelated files.
* Comment code when the reasoning isn't obvious.

Consistency is more important than personal preference.

---

# Documentation

Documentation is just as important as code.

If your contribution changes how something works, please update the relevant documentation.

This includes:

* Installation instructions
* Configuration guides
* Release notes
* User documentation
* Developer documentation

---

# Testing

Every contribution should be tested whenever possible.

Depending on your changes, this may include:

* Building the ISO
* Booting in QEMU
* Testing on real hardware
* Confirming existing features still work
* Verifying installer changes
* Checking logs for unexpected warnings or errors

If you weren't able to test something, mention that in your pull request.

---

# Reporting Bugs

Bug reports are always welcome.

A good bug report includes:

* Abora OS version
* Desktop environment
* Hardware information (when relevant)
* Steps to reproduce the issue
* Expected behavior
* Actual behavior
* Logs or screenshots if available

The more information you provide, the easier it is to investigate the problem.

---

# Feature Requests

Ideas and suggestions are welcome.

Before requesting a feature, consider whether it fits Abora OS's goal of making NixOS easier to use without adding unnecessary complexity.

If possible, explain:

* What problem the feature solves
* Why it would benefit users
* Any alternatives you've considered

---

# AI-Assisted Contributions

AI-assisted contributions are welcome.

If you use AI to help write code, documentation, translations, or artwork descriptions, you are responsible for reviewing, understanding, and testing everything you submit.

Maintainers may request changes regardless of how the contribution was created.

If an AI model made a significant contribution to your changes, please include a commit trailer such as:

Co-Authored-By: Claude - Opus 5
Co-Authored-By: ChatGPT - GPT-5.5
Co-Authored-By: Gemini - 2.5 Pro

Thanks!
---

# Licensing

By contributing to Abora OS, you agree that your contribution may be distributed under the project's license.

Only submit code, artwork, documentation, or other content that you have the right to contribute.

---

# Community

Be respectful and constructive.

Everyone starts somewhere, and respectful discussions make the project better for everyone.

Critique ideas and code not people.

---

# Thank You

Open-source projects only exist because people are willing to spend their time improving them.

Whether you've fixed a typo, reported a bug, tested a release, or contributed code, thank you for helping make Abora OS better.
