#!/usr/bin/env bash
set -euo pipefail

useradd -m -G wheel,audio,video,storage,network -s /bin/bash liveuser
passwd -d liveuser

install -d -m 0700 -o liveuser -g liveuser /home/liveuser/.config
cp -a /etc/skel/. /home/liveuser/
chown -R liveuser:liveuser /home/liveuser

install -d -m 0755 /usr/share/wallpapers/Abora
if [ -f /usr/share/abora/default-wallpaper.png ]; then
    install -m 0644 /usr/share/abora/default-wallpaper.png /usr/share/wallpapers/Abora/default.png
fi

systemctl enable NetworkManager.service
systemctl enable sddm.service

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat >/etc/systemd/system/getty@tty1.service.d/skip.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin liveuser --noclear %I $TERM
EOF

systemctl set-default graphical.target
