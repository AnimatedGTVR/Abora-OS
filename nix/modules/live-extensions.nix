{ pkgs, ... }:
{
  systemd.services.abora-live-extensions = {
    description = "Abora Live Extension Prompt";
    wantedBy = [ "display-manager.service" ];
    before = [ "display-manager.service" ];
    path = with pkgs; [ bash coreutils nix util-linux ];

    serviceConfig = {
      Type = "oneshot";
      StandardInput = "tty-force";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
    };

    script = ''
      set -euo pipefail

      state_file=/run/abora-live-extensions.done
      if [ -f "$state_file" ]; then
        exit 0
      fi
      touch "$state_file"

      clear || true
      printf '============================================\n'
      printf '         Abora Live Extension Setup         \n'
      printf '============================================\n\n'
      printf 'Install optional extensions before desktop starts.\n\n'
      printf '1) Try to install TinyPM extension\n'
      printf '2) Skip and continue boot\n\n'

      choice=2
      read -r -t 20 -p "Choose [1-2] (auto-skip in 20s): " choice || true

      if [ "$choice" = "1" ]; then
        printf '\nAttempting TinyPM install for live user...\n'
        if su - nixos -c 'nix profile install github:AnimatedGTVR/tinypm'; then
          printf 'TinyPM install completed.\n'
        else
          printf 'TinyPM install failed or source unavailable. Continuing boot.\n'
        fi
      else
        printf '\nSkipping extension install.\n'
      fi

      printf '\nContinuing desktop boot...\n'
      sleep 1
    '';
  };
}
