{ lib, pkgs, config, ... }:
let
  # Unlike installed-base.nix, these paths are NOT "beside this file on an
  # installed system" -- they point straight into this flake's own source
  # tree (../../assets, two levels up from nix/modules/). That's what makes
  # this module importable by a plain NixOS system that never ran the Abora
  # installer: there is no file-copy step to depend on, just a flake input.
  assetsDir           = ../../assets;
  titleFile           = assetsDir + "/abora-title.txt";
  fastfetchLogoFile   = assetsDir + "/fastfetch-logo.txt";
  fastfetchConfigFile = assetsDir + "/fastfetch-config.jsonc";
  logoFile            = assetsDir + "/Abora-LOGO.png";
  # The installer copies whichever wallpaper the user picked to
  # default-wallpaper.png at install time; a standalone import has no
  # install-time picker, so this pins the current default collection image
  # (see abora_wallpaper_label in abora-desktop-profiles.sh).
  wallpaperFile       = assetsDir + "/wallpapers/collection/titlis-alps.jpg";
in
{
  options.abora.branding.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Install Abora OS branding -- fastfetch config/logo, the title banner,
      the Abora logo image, and a default wallpaper -- on a plain NixOS
      system, without requiring the full Abora installer or ISO. See
      nixosModules.anix for the matching config-layer counterpart; this
      module only ever touches /etc/abora and fastfetch's XDG config, never
      anything the rest of a hand-rolled NixOS config might already own.
    '';
  };

  config = lib.mkIf config.abora.branding.enable {
    environment.systemPackages = [ pkgs.fastfetch ];

    environment.etc = {
      "abora/title.txt".source = titleFile;
      "abora/fastfetch-logo.txt".source = fastfetchLogoFile;
      "abora/fastfetch-config.jsonc".source = fastfetchConfigFile;
      "abora/Abora-LOGO.png".source = logoFile;
      "abora/default-wallpaper.png".source = wallpaperFile;

      # Real fastfetch lookup paths (see installed-base.nix's own
      # etc/xdg + etc/skel wiring, mirrored here so `fastfetch` shows
      # Abora branding for both existing and freshly-created users).
      "xdg/fastfetch/config.jsonc".source = fastfetchConfigFile;
      "xdg/fastfetch/abora-logo.txt".source = fastfetchLogoFile;
      "skel/.config/fastfetch/config.jsonc".source = fastfetchConfigFile;
      "skel/.config/fastfetch/abora-logo.txt".source = fastfetchLogoFile;
    };
  };
}
