// Anix Control: edit your ANIX config and run anix commands without a terminal.

namespace AnixControl {

    // feature name (as `anix enable <name>` knows it) -> anix.nix key, label, subtitle
    struct Feature { string name; string key; string label; string sub; }

    const Feature[] FEATURES = {
        { "bluetooth", "services.bluetooth", "Bluetooth", "Pair headphones, mice and keyboards" },
        { "printing", "services.printing", "Printing", "CUPS printer support" },
        { "flatpak", "services.flatpak", "Flatpak", "Apps from Flathub" },
        { "audio", "services.audio", "Audio", "PipeWire sound" },
        { "openssh", "services.openssh", "SSH server", "Let other computers log in to this one" },
        { "allowUnfree", "allowUnfree", "Proprietary software", "Allow apps like Discord and Steam" },
        { "experimentalNix", "experimentalNix", "Modern Nix commands", "nix-command and flakes" },
        { "thermald", "power.thermald", "thermald", "Intel laptop thermal daemon (laptops only)" },
        { "tlp", "power.tlp", "TLP", "Laptop battery tuning" },
        { "gaming", "gaming.enable", "Gaming layer", "Steam, Gamescope, MangoHud and launchers" },
        { "gc", "garbageCollect.enable", "Automatic cleanup", "Delete old system generations on a schedule" },
    };

    const string[] DESKTOPS = { "none", "gnome", "plasma", "hyprland", "sway", "xfce", "cinnamon", "mate", "budgie", "lxqt", "pantheon", "i3", "awesome", "openbox", "niri", "river", "qtile", "bspwm", "fluxbox", "icewm", "herbstluftwm", "cosmic", "mangowm", "lumina" };
    const string[] SHELLS = { "bash", "zsh", "fish" };

    // ── reading the config ──────────────────────────────────────────────────

    class Config : Object {
        public string text = "";
        public string path;
        public bool exists = false;

        public Config () {
            path = Path.build_filename (Environment.get_variable ("ANIX_SYSTEM_CONFIG") ?? "/etc/nixos", "anix.nix");
            reload ();
        }

        public void reload () {
            try {
                FileUtils.get_contents (path, out text);
                exists = true;
            } catch (Error e) {
                text = "";
                exists = false;
            }
        }

        string? match (string key, string value_pattern) {
            try {
                var re = new Regex ("^\\s*anix\\." + Regex.escape_string (key) + "\\s*=\\s*" + value_pattern, RegexCompileFlags.MULTILINE);
                MatchInfo info;
                if (re.match (text, 0, out info)) return info.fetch (1);
            } catch (Error e) {}
            return null;
        }

        public string str (string key) { return match (key, "\"([^\"]*)\";") ?? ""; }

        public bool? flag (string key) {
            var v = match (key, "(true|false);");
            if (v == null) return null;
            bool b = (v == "true");
            return b;
        }

        public string[] packages () {
            string[] out = {};
            var line = match ("packages", "with pkgs;\\s*\\[([^\\]]*)\\]");
            if (line == null) return out;
            foreach (var w in line.split_set (" \t\n")) if (w != "") out += w;
            return out;
        }
    }

    // ── the staged change set ───────────────────────────────────────────────

    class Plan : Object {
        // ordered ops; later edits to the same thing replace earlier ones
        public Json.Builder ops_builder = new Json.Builder ();
        HashTable<string, string> sets = new HashTable<string, string> (str_hash, str_equal);
        HashTable<string, bool> toggles = new HashTable<string, bool> (str_hash, str_equal);
        HashTable<string, bool> pkgs = new HashTable<string, bool> (str_hash, str_equal);
        public signal void changed ();

        public int count { get { return (int) (sets.size () + toggles.size () + pkgs.size ()); } }

        public void set_value (string key, string value, string current) {
            if (value == current) sets.remove (key); else sets.insert (key, value);
            changed ();
        }
        public void set_toggle (string name, bool on, bool current) {
            if (on == current) toggles.remove (name); else toggles.insert (name, on);
            changed ();
        }
        public void package (string name, bool add, bool present) {
            if (add == present) pkgs.remove (name); else pkgs.insert (name, add);
            changed ();
        }
        public bool pending_package (string name, out bool add) {
            return pkgs.lookup_extended (name, null, out add);
        }
        public void clear () { sets.remove_all (); toggles.remove_all (); pkgs.remove_all (); changed (); }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("planVersion").add_int_value (1);
            b.set_member_name ("language").add_string_value ("anix-control");
            b.set_member_name ("operations").begin_array ();
            foreach (var k in sets.get_keys ()) {
                b.begin_object ().set_member_name ("op").add_string_value ("set");
                b.set_member_name ("key").add_string_value (k);
                b.set_member_name ("value").add_string_value (sets.get (k)).end_object ();
            }
            foreach (var k in toggles.get_keys ()) {
                b.begin_object ().set_member_name ("op").add_string_value (toggles.get (k) ? "enable" : "disable");
                b.set_member_name ("feature").add_string_value (k).end_object ();
            }
            foreach (var k in pkgs.get_keys ()) {
                b.begin_object ().set_member_name ("op").add_string_value (pkgs.get (k) ? "package.add" : "package.remove");
                b.set_member_name ("name").add_string_value (k).end_object ();
            }
            b.end_array ().end_object ();
            return Json.to_string (b.get_root (), false);
        }
    }

    // ── running programs ────────────────────────────────────────────────────

    async string[] capture (string[] argv, out int status) {
        status = -1;
        try {
            var p = new Subprocess.newv (argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
            string? o;
            yield p.communicate_utf8_async (null, null, out o, null);
            status = p.get_exit_status ();
            return { o ?? "" };
        } catch (Error e) {
            return { e.message };
        }
    }

    string strip_ansi (string s) {
        try { return new Regex ("\\x1b\\[[0-9;?]*[ -/]*[@-~]").replace (s, -1, 0, ""); } catch (Error e) { return s; }
    }

    string[] root_cmd (string[] argv) {
        string[] c = { Environment.find_program_in_path ("pkexec") ?? "/run/wrappers/bin/pkexec", "env",
                       "ANIX_ASSUME_YES=1", "PATH=" + (Environment.get_variable ("PATH") ?? "/run/current-system/sw/bin") };
        foreach (var a in argv) c += a;
        return c;
    }

    // ── window ──────────────────────────────────────────────────────────────

    class Window : Adw.ApplicationWindow {
        Config cfg = new Config ();
        Plan plan = new Plan ();
        Adw.ToastOverlay toasts = new Adw.ToastOverlay ();
        Adw.ViewStack stack = new Adw.ViewStack ();
        Gtk.Revealer bar = new Gtk.Revealer ();
        Gtk.Label bar_label = new Gtk.Label ("");
        Gtk.Button apply_btn = new Gtk.Button.with_label ("Apply");
        Adw.PreferencesGroup pkg_group;
        Adw.PreferencesGroup history_group;
        Adw.PreferencesGroup health_group;
        Gtk.ListBox pkg_list;
        Adw.PreferencesPage page_system;
        string anix;
        Gtk.Box? busy_box = null;

        public Window (Gtk.Application app, string? page) {
            Object (application: app, title: "Anix Control", default_width: 880, default_height: 700, width_request: 360, height_request: 400);
            anix = Environment.find_program_in_path ("anix") ?? "";
            build ();
            plan.changed.connect (on_plan_changed);
            if (page != null) stack.visible_child_name = page;
        }

        void toast (string t) { toasts.add_toast (new Adw.Toast (t)); }

        void build () {
            stack.add_titled_with_icon (system_page (), "system", "System", "preferences-system-symbolic");
            stack.add_titled_with_icon (features_page (), "features", "Features", "emblem-system-symbolic");
            stack.add_titled_with_icon (packages_page (), "packages", "Packages", "package-x-generic-symbolic");
            stack.add_titled_with_icon (history_page (), "history", "History", "document-open-recent-symbolic");
            stack.add_titled_with_icon (health_page (), "health", "Health", "emblem-ok-symbolic");
            stack.add_titled_with_icon (updates_page (), "updates", "Updates", "software-update-available-symbolic");
            stack.notify["visible-child-name"].connect (() => {
                if (stack.visible_child_name == "history") load_history.begin ();
                if (stack.visible_child_name == "health") load_health.begin ();
            });

            var header = new Adw.HeaderBar ();
            var sw = new Adw.ViewSwitcher ();
            sw.stack = stack;
            sw.policy = Adw.ViewSwitcherPolicy.WIDE;
            header.title_widget = sw;
            var sbar = new Adw.ViewSwitcherBar ();
            sbar.stack = stack;

            // The apply bar: nothing changes on the system until this is pressed.
            var bar_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            bar_box.add_css_class ("toolbar");
            bar_box.margin_start = 12; bar_box.margin_end = 12;
            bar_label.hexpand = true; bar_label.xalign = 0;
            var discard = new Gtk.Button.with_label ("Discard");
            discard.clicked.connect (() => { plan.clear (); rebuild_pages (); });
            apply_btn.add_css_class ("suggested-action");
            apply_btn.clicked.connect (() => apply.begin ());
            bar_box.append (bar_label); bar_box.append (discard); bar_box.append (apply_btn);
            bar.child = bar_box;

            var tv = new Adw.ToolbarView ();
            tv.add_top_bar (header);
            tv.content = stack;
            tv.add_bottom_bar (bar);
            tv.add_bottom_bar (sbar);
            toasts.child = tv;
            set_content (toasts);

            var bp = new Adw.Breakpoint (Adw.BreakpointCondition.parse ("max-width: 700sp"));
            bp.add_setter (sbar, "reveal", true);
            bp.add_setter (header, "title-widget", null);
            add_breakpoint (bp);
        }

        void rebuild_pages () {
            cfg.reload ();
            var cur = stack.visible_child_name;
            stack.remove (stack.get_child_by_name ("system"));
            stack.remove (stack.get_child_by_name ("features"));
            stack.remove (stack.get_child_by_name ("packages"));
            // recreate in order, then restore the page
            var s = system_page (); var f = features_page (); var p = packages_page ();
            stack.add_titled_with_icon (s, "system", "System", "preferences-system-symbolic");
            stack.add_titled_with_icon (f, "features", "Features", "emblem-system-symbolic");
            stack.add_titled_with_icon (p, "packages", "Packages", "package-x-generic-symbolic");
            stack.visible_child_name = cur;
        }

        void on_plan_changed () {
            bar.reveal_child = plan.count > 0;
            bar_label.label = plan.count == 1 ? "1 change ready" : "%d changes ready".printf (plan.count);
        }

        // ── pages ──

        Gtk.Widget no_anix () {
            var sp = new Adw.StatusPage ();
            sp.icon_name = "dialog-warning-symbolic";
            sp.title = "ANIX isn't installed";
            sp.description = "Anix Control edits the ANIX layer. Install ANIX from github.com/XenoTechWorks/ANIX, or use Abora OS where it comes built in.";
            return sp;
        }

        Gtk.Widget no_config () {
            var sp = new Adw.StatusPage ();
            sp.icon_name = "document-new-symbolic";
            sp.title = "No ANIX config yet";
            sp.description = "Create /etc/nixos/anix.nix with sensible defaults. Nothing is rebuilt.";
            var b = new Gtk.Button.with_label ("Create Config");
            b.halign = Gtk.Align.CENTER;
            b.add_css_class ("pill"); b.add_css_class ("suggested-action");
            b.clicked.connect (() => init_config.begin ());
            sp.child = b;
            return sp;
        }

        async void init_config () {
            int st;
            var o = yield capture (root_cmd ({ anix, "init" }), out st);
            if (st == 0) { toast ("Config created"); rebuild_pages (); } else toast (strip_ansi (o[0]).strip ());
        }

        bool ready () { return anix != "" && cfg.exists; }

        Gtk.Widget wrap (Adw.PreferencesPage p) { return p; }

        Gtk.Widget system_page () {
            if (anix == "") return no_anix ();
            if (!cfg.exists) return no_config ();
            var page = new Adw.PreferencesPage ();
            var g = new Adw.PreferencesGroup ();
            g.title = "This computer";
            g.add (text_row ("Name on the network", "hostname", "hostname", "Letters, numbers and dashes"));
            g.add (text_row ("Timezone", "timezone", "timezone", "For example Europe/Paris"));
            g.add (text_row ("Keyboard layout", "keyboard.xkb", "keyboard.xkb", "For example us, de, fr"));
            page.add (g);

            var d = new Adw.PreferencesGroup ();
            d.title = "Look and shell";
            d.add (combo_row ("Desktop", "desktop", "desktop", DESKTOPS, "Changing it downloads a whole desktop"));
            d.add (combo_row ("Default shell", "shell", "shell", SHELLS, null));
            d.add (text_row ("Wallpaper file", "wallpaper", "wallpaper", "A name from the wallpaper list"));
            page.add (d);

            var n = new Adw.PreferencesGroup ();
            n.title = "Nix";
            n.description = "Lix is a community fork of Nix. Both use the same nixpkgs.";
            n.add (combo_row ("Package manager", "nixImplementation", "nix", { "nix", "lix" }, "Rebuilds the system with the one you pick"));
            page.add (n);
            return page;
        }

        Adw.EntryRow text_row (string title, string key, string plan_key, string tip) {
            var r = new Adw.EntryRow ();
            r.title = title;
            r.text = cfg.str (key);
            r.tooltip_text = tip;
            var original = r.text;
            r.changed.connect (() => {
                var v = r.text.strip ();
                if (v == "" ) { plan.set_value (plan_key, "", ""); return; }
                plan.set_value (plan_key, v, original);
            });
            return r;
        }

        Adw.ComboRow combo_row (string title, string key, string plan_key, string[] choices, string? sub) {
            var r = new Adw.ComboRow ();
            r.title = title;
            if (sub != null) r.subtitle = sub;
            r.model = new Gtk.StringList (choices);
            var cur = cfg.str (key);
            for (int i = 0; i < choices.length; i++) if (choices[i] == cur) r.selected = i;
            r.notify["selected"].connect (() => {
                if (r.selected < choices.length) plan.set_value (plan_key, choices[r.selected], cur);
            });
            return r;
        }

        Gtk.Widget features_page () {
            if (anix == "") return no_anix ();
            if (!cfg.exists) return no_config ();
            var page = new Adw.PreferencesPage ();
            var g = new Adw.PreferencesGroup ();
            g.title = "Features";
            foreach (var f in FEATURES) {
                var r = new Adw.SwitchRow ();
                r.title = f.label;
                r.subtitle = f.sub;
                bool? cur = cfg.flag (f.key);
                r.active = cur == true;
                var name = f.name;
                var was = cur == true;
                r.notify["active"].connect (() => plan.set_toggle (name, r.active, was));
                g.add (r);
            }
            page.add (g);
            return page;
        }

        Gtk.Widget packages_page () {
            if (anix == "") return no_anix ();
            if (!cfg.exists) return no_config ();
            var page = new Adw.PreferencesPage ();
            pkg_group = new Adw.PreferencesGroup ();
            pkg_group.title = "System-wide packages";
            pkg_group.description = "Installed for everyone. For just you, use Flurry.";
            var add = new Adw.EntryRow ();
            add.title = "Add a nixpkgs package (for example htop)";
            add.show_apply_button = true;
            add.apply.connect (() => {
                var n = add.text.strip ();
                if (n == "") return;
                try {
                    if (!new Regex ("^[A-Za-z0-9._+-]+$").match (n)) { toast ("That isn't a package name"); return; }
                } catch (Error e) {}
                plan.package (n, true, false);
                add.text = "";
                var row = new Adw.ActionRow ();
                row.title = n; row.subtitle = "Will be added";
                pkg_group.add (row);
            });
            pkg_group.add (add);
            foreach (var p in cfg.packages ()) {
                var row = new Adw.ActionRow ();
                row.title = p;
                var b = new Gtk.ToggleButton ();
                b.icon_name = "user-trash-symbolic"; b.valign = Gtk.Align.CENTER;
                b.add_css_class ("flat");
                b.tooltip_text = "Remove";
                var name = p;
                b.toggled.connect (() => {
                    plan.package (name, !b.active, true);
                    row.subtitle = b.active ? "Will be removed" : "";
                });
                row.add_suffix (b);
                pkg_group.add (row);
            }
            page.add (pkg_group);
            return page;
        }

        Gtk.Widget history_page () {
            var page = new Adw.PreferencesPage ();
            history_group = new Adw.PreferencesGroup ();
            history_group.title = "Every system change";
            history_group.description = "Each change runs as a transaction. If one breaks something it rolls back by itself; you can also undo one here.";
            page.add (history_group);
            return page;
        }

        Gtk.Widget health_page () {
            var page = new Adw.PreferencesPage ();
            health_group = new Adw.PreferencesGroup ();
            health_group.title = "System health";
            var fix = new Gtk.Button.with_label ("Repair");
            fix.valign = Gtk.Align.CENTER;
            fix.clicked.connect (() => repair.begin ());
            health_group.header_suffix = fix;
            page.add (health_group);
            return page;
        }

        Gtk.Widget updates_page () {
            var page = new Adw.PreferencesPage ();
            var g = new Adw.PreferencesGroup ();
            g.title = "Update";
            var r = new Adw.ActionRow ();
            r.title = "Update the system";
            r.subtitle = "Downloads the newest packages, builds, and switches. A failed update is rolled back.";
            var b = new Gtk.Button.with_label ("Update Now");
            b.valign = Gtk.Align.CENTER; b.add_css_class ("suggested-action");
            b.clicked.connect (() => run_root.begin ({ anix, "update" }, "Updating the system…"));
            r.add_suffix (b);
            g.add (r);
            var rb = new Adw.ActionRow ();
            rb.title = "Rebuild with the current config";
            rb.subtitle = "Same as “anix apply”.";
            var b2 = new Gtk.Button.with_label ("Rebuild");
            b2.valign = Gtk.Align.CENTER;
            b2.clicked.connect (() => run_root.begin ({ anix, "apply" }, "Rebuilding…"));
            rb.add_suffix (b2);
            g.add (rb);
            var gc = new Adw.ActionRow ();
            gc.title = "Free disk space";
            gc.subtitle = "Remove old system generations.";
            var b3 = new Gtk.Button.with_label ("Clean Up");
            b3.valign = Gtk.Align.CENTER;
            b3.clicked.connect (() => run_root.begin ({ anix, "gc", "old" }, "Cleaning up…"));
            gc.add_suffix (b3);
            g.add (gc);
            page.add (g);
            return page;
        }

        // ── actions ──

        async void apply () {
            var dialog = new Adw.AlertDialog ("Apply %d change(s)?".printf (plan.count),
                "Your system is rebuilt with these changes. This can take a few minutes. If the rebuild fails, everything is rolled back.");
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("go", "Apply");
            dialog.set_response_appearance ("go", Adw.ResponseAppearance.SUGGESTED);
            if ((yield dialog.choose (this, null)) != "go") return;
            string file;
            try {
                var dir = Path.build_filename (Environment.get_user_runtime_dir (), "anix-control");
                DirUtils.create_with_parents (dir, 0700);
                file = Path.build_filename (dir, "plan.json");
                FileUtils.set_contents (file, plan.to_json ());
            } catch (Error e) { toast (e.message); return; }
            var ok = yield run_root ({ anix, "apply-plan", file, "--yes" }, "Applying your changes…");
            if (ok) plan.clear ();
            rebuild_pages ();
        }

        // Runs a root command with a progress dialog that shows the output.
        async bool run_root (string[] argv, string title) {
            var dlg = new Adw.Dialog ();
            dlg.title = title;
            dlg.content_width = 640; dlg.content_height = 420;
            dlg.can_close = false;
            var tv = new Adw.ToolbarView ();
            tv.add_top_bar (new Adw.HeaderBar ());
            var view = new Gtk.TextView ();
            view.editable = false; view.monospace = true; view.wrap_mode = Gtk.WrapMode.CHAR;
            view.left_margin = view.right_margin = view.top_margin = view.bottom_margin = 10;
            var sc = new Gtk.ScrolledWindow (); sc.child = view; sc.vexpand = true;
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var status = new Gtk.Label (title); status.xalign = 0; status.margin_start = 12; status.margin_top = 8;
            var close = new Gtk.Button.with_label ("Close");
            close.sensitive = false; close.margin_bottom = 12; close.margin_end = 12; close.halign = Gtk.Align.END;
            close.clicked.connect (() => dlg.force_close ());
            box.append (status); box.append (sc); box.append (close);
            tv.content = box;
            dlg.child = tv;
            dlg.present (this);

            bool ok = false;
            try {
                var p = new Subprocess.newv (root_cmd (argv), SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
                var rd = new DataInputStream (p.get_stdout_pipe ());
                string? l;
                while ((l = yield rd.read_line_utf8_async ()) != null) {
                    var parts = strip_ansi (l).split ("\r");
                    Gtk.TextIter end; view.buffer.get_end_iter (out end);
                    view.buffer.insert (ref end, parts[parts.length - 1] + "\n", -1);
                    view.buffer.get_end_iter (out end);
                    view.scroll_to_iter (end, 0, false, 0, 0);
                }
                yield p.wait_async ();
                ok = p.get_exit_status () == 0;
            } catch (Error e) {
                Gtk.TextIter end; view.buffer.get_end_iter (out end);
                view.buffer.insert (ref end, e.message + "\n", -1);
            }
            status.label = ok ? "Done." : "That didn't work. Nothing was left half-changed; see the output below.";
            dlg.can_close = true; close.sensitive = true;
            yield wait_closed (dlg);
            return ok;
        }

        async void wait_closed (Adw.Dialog dlg) {
            SourceFunc cb = wait_closed.callback;
            dlg.closed.connect (() => { Idle.add ((owned) cb); });
            yield;
        }

        async void load_history () {
            Gtk.Widget? c;
            // remove previous rows (keep the group header)
            var rows = new GenericArray<Gtk.Widget> ();
            foreach (var r in hist_rows) history_group.remove (r);
            hist_rows = {};
            var dir = Environment.get_variable ("ABT_STATE_DIR") ?? "/var/lib/abora/abt";
            var ids = new GenericArray<string> ();
            try {
                var d = Dir.open (dir); string? n;
                while ((n = d.read_name ()) != null) ids.add (n);
            } catch (Error e) {
                var r = new Adw.ActionRow (); r.title = "No history yet"; r.subtitle = "Changes made with ANIX on Abora OS appear here.";
                history_group.add (r); hist_rows += r; return;
            }
            ids.sort ((a, b) => strcmp (b, a));
            for (int i = 0; i < ids.length && i < 30; i++) {
                try {
                    string t; FileUtils.get_contents (Path.build_filename (dir, ids[i], "transaction.json"), out t);
                    var o = Json.from_string (t).get_object ();
                    var row = new Adw.ActionRow ();
                    var state = o.get_string_member_with_default ("state", "?");
                    row.title = o.get_string_member_with_default ("name", ids[i]);
                    row.subtitle = "%s · %s".printf (o.get_string_member_with_default ("started", ""), state);
                    if (state == "committed") {
                        var undo = new Gtk.Button.with_label ("Undo");
                        undo.valign = Gtk.Align.CENTER;
                        var id = ids[i];
                        undo.clicked.connect (() => { run_root.begin ({ "abora-abt", "undo", id }, "Undoing…", (o2, r2) => { run_root.end (r2); load_history.begin (); }); });
                        row.add_suffix (undo);
                    }
                    history_group.add (row); hist_rows += row;
                } catch (Error e) {}
            }
            if (hist_rows.length == 0) {
                var r = new Adw.ActionRow (); r.title = "No history yet";
                history_group.add (r); hist_rows += r;
            }
        }
        Gtk.Widget[] hist_rows = {};
        Gtk.Widget[] health_rows = {};

        async void load_health () {
            foreach (var r in health_rows) health_group.remove (r);
            health_rows = {};
            var spin = new Adw.ActionRow (); spin.title = "Checking…"; spin.add_prefix (new Adw.Spinner ());
            health_group.add (spin); health_rows += spin;
            int st;
            var o = yield capture ({ "anix", "doctor", "--json" }, out st);
            health_group.remove (spin); health_rows = {};
            try {
                var root = Json.from_string (o[0]).get_object ();
                root.get_array_member ("findings").foreach_element ((a, i, n) => {
                    var f = n.get_object ();
                    var status = f.get_string_member ("status");
                    if (status == "skip") return;
                    var row = new Adw.ActionRow ();
                    row.title = f.get_string_member ("summary");
                    var ex = f.get_string_member_with_default ("explanation", "");
                    if (ex != "") row.subtitle = ex;
                    row.add_prefix (new Gtk.Image.from_icon_name (status == "ok" ? "emblem-ok-symbolic" : (status == "warn" ? "dialog-warning-symbolic" : "dialog-error-symbolic")));
                    health_group.add (row); health_rows += row;
                });
            } catch (Error e) {
                var row = new Adw.ActionRow (); row.title = "Couldn't run the health check"; row.subtitle = strip_ansi (o[0]).strip ();
                health_group.add (row); health_rows += row;
            }
        }

        async void repair () {
            yield run_root ({ anix, "doctor", "--fix" }, "Repairing…");
            load_health.begin ();
        }
    }

    class App : Adw.Application {
        string? page = null;
        public App () {
            Object (application_id: "org.abora.AnixControl", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
            add_main_option ("page", 0, OptionFlags.NONE, OptionArg.STRING, "Open on a page: system, features, packages, history, health, updates", "PAGE");
        }
        public override int command_line (ApplicationCommandLine cl) {
            cl.get_options_dict ().lookup ("page", "s", out page);
            activate ();
            return 0;
        }
        public override void activate () {
            var w = active_window ?? new Window (this, page);
            w.present ();
        }
    }
}

int main (string[] args) {
    return new AnixControl.App ().run (args);
}
