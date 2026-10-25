# Abora Gaming

Abora Gaming is an optional layer for desktop gaming. It can configure Steam, Wine, Winetricks, GameMode, MangoHud, Vulkan tools, controllers, launchers, and an optional Gamescope Big Picture session.

```sh
abora gaming status
abora gaming enable
abora gaming steam on
abora gaming install steam
abora gaming install wine winetricks
abora gaming big-picture on
abora gaming logs
```

Gaming changes rebuild the NixOS configuration. Save work first and keep a bootable older generation. If the per-user fetch cache is damaged, run `abora gaming repair-cache`. Hardware support still depends on the kernel, Mesa or NVIDIA driver, firmware, and the game itself.
