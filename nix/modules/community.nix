{ lib, pkgs, config, ... }:
let
  source = if builtins.pathExists ./community.py then ./community.py
    else ../../scripts/support/abora-community.py;
  python = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  giPath = lib.makeSearchPath "lib/girepository-1.0" (with pkgs; [
    gtk4 libadwaita glib gdk-pixbuf (lib.getLib pango) harfbuzz graphene cairo gobject-introspection
  ]);
  libraryPath = lib.makeLibraryPath (with pkgs; [ gtk4 libadwaita glib gdk-pixbuf cairo ]);
  command = name: mode: pkgs.writeShellScriptBin name ''
    export GI_TYPELIB_PATH="${giPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
    export LD_LIBRARY_PATH="${libraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export PATH="${pkgs.libnotify}/bin:$PATH"
    export ABORA_SURVEY_URL=${lib.escapeShellArg config.abora.community.surveyUrl}
    export GSK_RENDERER="''${GSK_RENDERER:-cairo}"
    exec ${python}/bin/python3 ${source} ${mode} "$@"
  '';
  survey = command "abora-survey" "survey";
  learn = command "abora-learn" "learn";
  reminder = command "abora-survey-reminder" "notify";
  # xdg.desktopEntries is a home-manager option; NixOS needs real desktop files.
  surveyDesktop = pkgs.makeDesktopItem {
    name = "org.abora.Survey";
    desktopName = "Abora Survey";
    exec = "${survey}/bin/abora-survey";
    icon = "dialog-question";
    categories = [ "Utility" ];
  };
  learnDesktop = pkgs.makeDesktopItem {
    name = "org.abora.LearnNix";
    desktopName = "Learn Nix / NixOS";
    exec = "${learn}/bin/abora-learn";
    icon = "help-browser";
    categories = [ "Education" ];
  };
in {
  options.abora.community = {
    surveyUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://forms.gle/V6aoBimEZYRt2nUb7";
      description = "Optional HTTPS survey form URL. No local answers are uploaded.";
    };
    reminders = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable optional per-user survey reminders on installed systems.";
    };
  };
  config = {
    environment.systemPackages = [ survey learn surveyDesktop learnDesktop ];
    environment.etc = {
      "abora/community.py".source = source;
      "abora/community.nix".source = ./community.nix;
    };
    systemd.user.services.abora-survey-reminder = lib.mkIf config.abora.community.reminders {
      description = "Optional Abora survey reminder";
      after = [ "graphical-session.target" ];
      requisite = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${reminder}/bin/abora-survey-reminder";
      };
    };
    systemd.user.timers.abora-survey-reminder = lib.mkIf config.abora.community.reminders {
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      timerConfig = { OnActiveSec = "30min"; OnUnitActiveSec = "1d"; };
    };
  };
}
