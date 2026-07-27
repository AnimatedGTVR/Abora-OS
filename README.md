<p align="center">
  <img src="/assets/Abora-Text.png" alt="Abora OS" width="650">
</p>

<div align="center">


### A NixOS-based Linux distro made to be easier to install, use, and understand.

<br/>

<a href="https://aboraos.org">
  <img height="28" src="https://img.shields.io/badge/Website-aboraos.org-f0f0f0?style=for-the-badge" alt="Website">
</a>
<a href="https://deepwiki.com/AnimatedGTVR/Abora-OS">
  <img height="28" src="https://img.shields.io/badge/Ask%20DeepWiki-Abora%20OS-0ea5e9?style=for-the-badge" alt="Ask DeepWiki">
</a>
<a href="https://github.com/AnimatedGTVR/Abora-OS">
  <img height="28" src="https://img.shields.io/badge/GitHub-Abora--OS-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub">
</a>

<br/>
<br/>

<a href="https://github.com/AnimatedGTVR/Abora-OS/stargazers">
  <img height="22" src="https://img.shields.io/github/stars/AnimatedGTVR/Abora-OS?style=flat-square&label=Stars" alt="GitHub Stars">
</a>
<a href="https://github.com/AnimatedGTVR/Abora-OS/issues">
  <img height="22" src="https://img.shields.io/github/issues/AnimatedGTVR/Abora-OS?style=flat-square&label=Issues" alt="Issues">
</a>
<a href="https://github.com/AnimatedGTVR/Abora-OS/releases">
  <img height="22" src="https://img.shields.io/github/v/release/AnimatedGTVR/Abora-OS?style=flat-square&label=Release" alt="Latest Release">
</a>
<a href="LICENSE">
  <img height="22" src="https://img.shields.io/badge/License-See%20LICENSE-3b82f6?style=flat-square" alt="License">
</a>

</div>

---

> [!IMPORTANT]
> Abora OS has two release lines: **Stable** and **Edge**.

> [!TIP]
> Want more info, docs, downloads, screenshots, and updates? Visit **https://aboraos.org**.

---

## Screenshots

<div align="center">

<img src="/assets/Images/v4/screenshot-2026-07-27_03-54-02.png" width="410" alt="Abora Welcome on GNOME">
<img src="/assets/Images/v4/screenshot-2026-07-27_03-56-03.png" width="410" alt="Abora System Settings">
<img src="/assets/Images/v4/screenshot-2026-07-27_03-58-15.png" width="410" alt="fastfetch on GNOME">
<img src="/assets/Images/v4/screenshot-2026-07-27_05-32-15.png" width="410" alt="fastfetch on COSMIC">

</div>

---

## What is Abora OS?

Abora OS is a Linux distribution based on NixOS.

It keeps the good parts of NixOS — rollback support, reproducible systems, and powerful configuration — while making the experience easier with better defaults, desktop options, installer work, and Abora tooling.

Abora is built for people who want a powerful Linux system without fighting the system from the start.

---

## Release Lines

Abora ships on two branches, same idea as NixOS's stable/unstable split.

### Stable

The tagged, tested releases. Version numbers like:

```txt
2.5
3.0
3.14
4.0
```

This is what `abora update` tracks by default, and what most people should be running.

### Edge

Tracks `main` directly, no waiting for a tag. Same deal as `nixos-unstable`: newest installer work, desktop changes, ANIX changes, and fixes land here first, before anything's been fully vetted. Things can and do break.

Switch to it with:

```sh
sudo abora channel set unstable
```

Go back to stable the same way (`sudo abora channel set stable`) whenever you've had enough.

---

## Main Features

- NixOS base
- Rollback-friendly updates
- Multiple desktop options
- ANIX tooling
- Stable and Edge release lines
- Custom installer work
- Abora-specific defaults and cleanup

---

## ANIX

ANIX is Abora’s easier layer for common Nix-style system tasks.

```bash
anix update
anix switch
anix rollback
anix status
```

> [!NOTE]
> ANIX is meant to make Abora easier to manage, not hide how the system works.

---

## Download

Download Abora OS from the website or GitHub releases.

<div align="center">

<a href="https://aboraos.org">
  <img src="https://img.shields.io/badge/Download-Abora%20OS-f0f0f0?style=for-the-badge" alt="Download Abora OS">
</a>
<a href="https://github.com/AnimatedGTVR/Abora-OS/releases">
  <img src="https://img.shields.io/badge/GitHub-Releases-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub Releases">
</a>

</div>

---

## Building

Clone the repository:

```bash
git clone https://github.com/AnimatedGTVR/Abora-OS.git
cd Abora-OS
```

Build steps may change depending on the branch, release line, and ISO profile.

For current build info, check the website, release notes, or DeepWiki.

<div align="center">

<a href="https://deepwiki.com/AnimatedGTVR/Abora-OS">
  <img src="https://img.shields.io/badge/Ask%20DeepWiki-Abora%20OS-7c3aed?style=for-the-badge" alt="Ask DeepWiki">
</a>

</div>

---

## Contributing

Contributions are welcome.

Useful help includes:

- bug reports
- desktop testing
- installer testing
- documentation fixes
- ANIX improvements
- cleanup work

Open an issue or pull request if you want to help.

---

> [!WARNING]
> Edge builds may break. Use Stable if you want the safer path.

---

## Links

<div align="center">

<a href="https://aboraos.org">
  <img src="https://img.shields.io/badge/Visit%20Website-aboraos.org-f0f0f0?style=for-the-badge" alt="Visit Website">
</a>
<a href="https://deepwiki.com/AnimatedGTVR/Abora-OS">
  <img src="https://img.shields.io/badge/Ask%20DeepWiki-Abora%20OS-7c3aed?style=for-the-badge" alt="Ask DeepWiki">
</a>
<a href="https://github.com/AnimatedGTVR/Abora-OS">
  <img src="https://img.shields.io/badge/View%20Source-GitHub-181717?style=for-the-badge&logo=github&logoColor=white" alt="View Source">
</a>
<a href="https://xenoproject.tech">
  <img src="https://img.shields.io/badge/Xeno%20Tech-xenoproject.tech-2563eb?style=for-the-badge" alt="Xeno Tech">
</a>

</div>

---

## License

Abora OS is open source.

Check the repository license for exact terms.
