#!/usr/bin/env bash

iso_name="abora"
iso_label="ABORA_$(date +%Y%m)"
iso_publisher="Abora OS <https://abora.os>"
iso_application="Abora OS Live Media"
iso_version="$(date +%Y.%m.%d)"
install_dir="abora"
buildmodes=("iso")
bootmodes=(
  "bios.syslinux"
  "uefi.systemd-boot"
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
bootstrap_tarball_compression=("zstd" "-c" "-T0 --long -19")
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/customize_airootfs.sh"]="0:0:755"
  ["/etc/sudoers.d/10-liveuser"]="0:0:440"
  ["/usr/local/bin/abora-live-info"]="0:0:755"
  ["/usr/share/abora"]="0:0:755"
)
