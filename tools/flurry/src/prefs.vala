// Preferences: which sources to use and in what order, Nix or Lix, and where Flatpaks go.

namespace Flurry {

    public class Preferences : Adw.PreferencesDialog {
        Store store;
        Window window;

        public Preferences (Store store, Window window) {
            this.store = store;
            this.window = window;
            title = _("Preferences");
            search_enabled = false;
            add (sources_page ());
        }

        Adw.PreferencesPage sources_page () {
            var page = new Adw.PreferencesPage ();
            page.title = _("Sources");
            page.icon_name = "flurry-explore-symbolic";
            var s = store.settings;

            var sources = new Adw.PreferencesGroup ();
            sources.title = _("Where apps come from");
            sources.description = _("Search shows every source that is on. When several have the same app, the first one in this order is picked.");
            sources.add (source_switch (Source.NIX, store.nix.available, store.nix.available ? store.nix.pretty_version () : _("Nix isn't installed")));
            sources.add (source_switch (Source.FLATPAK, store.flatpak.available, store.flatpak.available ? (store.flatpak.has_remote ? _("Flathub is set up") : _("Flathub isn't set up yet")) : _("Flatpak isn't installed")));
            sources.add (source_switch (Source.SNAP, store.snap.available, store.snap.available ? _("snapd is running") : _("snapd isn't running on this system")));

            string[] orders = { "nix,flatpak,snap", "flatpak,nix,snap", "flatpak,snap,nix", "snap,flatpak,nix" };
            var order = new Adw.ComboRow ();
            order.title = _("Preferred source");
            order.model = new Gtk.StringList ({
                "Nixpkgs → Flathub → Snap",
                "Flathub → Nixpkgs → Snap",
                "Flathub → Snap → Nixpkgs",
                "Snap → Flathub → Nixpkgs",
            });
            for (int i = 0; i < orders.length; i++) if (orders[i] == s.order) order.selected = i;
            order.notify["selected"].connect (() => {
                s.order = orders[order.selected];
                s.save ();
            });
            sources.add (order);
            page.add (sources);

            page.add (nix_group ());

            if (store.flatpak.available) {
                var fp = new Adw.PreferencesGroup ();
                fp.title = "Flatpak";
                var scope = new Adw.ComboRow ();
                scope.title = _("Install Flatpaks for");
                scope.subtitle = _("“Everyone” asks for your password");
                scope.model = new Gtk.StringList ({ _("Automatic"), _("Just me"), _("Everyone") });
                string[] scopes = { "auto", "user", "system" };
                for (int i = 0; i < scopes.length; i++) if (scopes[i] == s.flatpak_scope) scope.selected = i;
                scope.notify["selected"].connect (() => {
                    s.flatpak_scope = scopes[scope.selected];
                    store.flatpak.scope_preference = s.flatpak_scope;
                    s.save ();
                });
                fp.add (scope);
                page.add (fp);
            }
            return page;
        }

        Adw.SwitchRow source_switch (Source src, bool available, string subtitle) {
            var row = new Adw.SwitchRow ();
            row.title = src.label ();
            row.subtitle = subtitle;
            row.sensitive = available;
            var s = store.settings;
            switch (src) {
                case Source.NIX: row.active = s.use_nix && available; break;
                case Source.FLATPAK: row.active = s.use_flatpak && available; break;
                default: row.active = s.use_snap && available; break;
            }
            row.notify["active"].connect (() => {
                switch (src) {
                    case Source.NIX: s.use_nix = row.active; break;
                    case Source.FLATPAK: s.use_flatpak = row.active; break;
                    default: s.use_snap = row.active; break;
                }
                s.save ();
            });
            return row;
        }

        Adw.PreferencesGroup nix_group () {
            var nix = store.nix;
            var group = new Adw.PreferencesGroup ();
            group.title = _("Nix or Lix");
            group.description = _("Lix is a community fork of Nix. Both install from the same nixpkgs; pick the one you trust.");
            if (!nix.available) {
                var row = new Adw.ActionRow ();
                row.title = _("Nix isn't installed");
                group.add (row);
                return group;
            }

            var impl = new Adw.ComboRow ();
            impl.title = _("Package manager");
            impl.subtitle = _("Running now: %s").printf (nix.pretty_version ());
            impl.model = new Gtk.StringList ({ "Nix", "Lix" });
            impl.selected = nix.is_lix ? 1 : 0;
            group.add (impl);

            if (nix.anix == null) {
                // Plain NixOS: Flurry won't edit someone's configuration.nix, so show the line to add.
                var how = new Adw.ActionRow ();
                how.title = _("To switch, add this to your NixOS config and rebuild");
                how.subtitle = "nix.package = pkgs.lix;";
                how.subtitle_selectable = true;
                how.add_css_class ("monospace-subtitle");
                var copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
                copy.tooltip_text = _("Copy");
                copy.valign = Gtk.Align.CENTER;
                copy.add_css_class ("flat");
                impl.notify["selected"].connect (() => {
                    how.subtitle = impl.selected == 1 ? "nix.package = pkgs.lix;" : "nix.package = pkgs.nix;";
                });
                copy.clicked.connect (() => {
                    window.get_clipboard ().set_text (how.subtitle);
                    add_toast (new Adw.Toast (_("Copied")));
                });
                how.add_suffix (copy);
                group.add (how);
                return group;
            }

            bool reverting = false;
            impl.notify["selected"].connect (() => {
                if (reverting) return;
                var want_lix = impl.selected == 1;
                if (want_lix == nix.is_lix) return;
                confirm_switch.begin (want_lix, (obj, res) => {
                    if (!confirm_switch.end (res)) {
                        reverting = true;
                        impl.selected = nix.is_lix ? 1 : 0;
                        reverting = false;
                    }
                });
            });

            var target = new Adw.ComboRow ();
            target.title = _("Install nixpkgs apps for");
            target.subtitle = _("“Everyone” adds them to the system config and rebuilds");
            target.model = new Gtk.StringList ({ _("Just me (no rebuild)"), _("Everyone") });
            target.selected = store.settings.nix_target == "system" ? 1 : 0;
            target.notify["selected"].connect (() => {
                store.settings.nix_target = target.selected == 1 ? "system" : "user";
                store.settings.save ();
            });
            group.add (target);
            return group;
        }

        async bool confirm_switch (bool lix) {
            var name = lix ? "Lix" : "Nix";
            var dialog = new Adw.AlertDialog (_("Switch to %s?").printf (name),
                _("The system is rebuilt with %s as its package manager. This takes a few minutes; if it fails, the change is rolled back. Apps you installed stay installed.").printf (name));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("go", _("Switch and Rebuild"));
            dialog.set_response_appearance ("go", Adw.ResponseAppearance.SUGGESTED);
            if ((yield dialog.choose (this, null)) != "go") return false;
            try {
                var job = store.nix.switch_implementation (lix);
                if (job == null) return false;
                var task = store.queue_job (name, job);
                add_toast (new Adw.Toast (_("Rebuilding with %s…").printf (name)));
                task.finished.connect ((status) => {
                    store.nix.probe.begin ();
                    window.toast (status == 0 ? _("Now using %s").printf (name) : _("Couldn't switch to %s: %s").printf (name, task.job.tail (1)));
                });
                return true;
            } catch (Error e) {
                add_toast (new Adw.Toast (e.message));
                return false;
            }
        }
    }
}
