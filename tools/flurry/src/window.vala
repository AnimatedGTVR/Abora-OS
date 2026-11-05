// The main window: Explore, Installed and Updates, with search over everything.

namespace Flurry {

    public class Window : Adw.ApplicationWindow {
        public Store store { get; construct; }
        Adw.ToastOverlay toasts;
        Adw.NavigationView nav;
        Adw.ViewStack views;
        Gtk.Stack pages;
        Gtk.SearchBar search_bar;
        Gtk.SearchEntry search_entry;
        Gtk.ToggleButton search_button;

        // Explore
        Gtk.Box sources_box;
        Adw.Banner index_banner;
        Gtk.Box shelves_box;
        bool shelves_built = false;

        // Search
        Gtk.Stack search_stack;
        Gtk.ListBox results_list;
        Adw.StatusPage no_results;
        Gtk.Label search_note;
        Cancellable? search_cancel = null;
        uint search_timeout = 0;

        // Installed / Updates
        Adw.PreferencesPage installed_page;
        GenericArray<Adw.PreferencesGroup> installed_groups = new GenericArray<Adw.PreferencesGroup> ();
        Gtk.Stack installed_stack;
        Gtk.Stack updates_stack;
        Gtk.ListBox updates_list;
        Gtk.Button update_all;
        Adw.PreferencesGroup system_group;

        public Window (Gtk.Application app, Store store) {
            Object (application: app, store: store, title: "Flurry", default_width: 1080, default_height: 760,
                    width_request: 360, height_request: 400);
            build ();
            store.ready.connect (on_ready);
            store.nix.index_changed.connect (on_index_changed);
            store.installed_changed.connect (() => {
                refresh_installed ();
            });
            store.task_finished.connect (on_task_finished);
        }

        public void toast (string text) {
            var t = new Adw.Toast (text);
            t.timeout = 4;
            toasts.add_toast (t);
        }

        void build () {
            var header = new Adw.HeaderBar ();
            search_button = new Gtk.ToggleButton ();
            search_button.icon_name = "system-search-symbolic";
            search_button.tooltip_text = _("Search (Ctrl+F)");
            header.pack_start (search_button);

            var menu = new Menu ();
            menu.append (_("Preferences"), "app.preferences");
            menu.append (_("Rebuild the Package List"), "win.reindex");
            menu.append (_("About Flurry"), "app.about");
            var menu_button = new Gtk.MenuButton ();
            menu_button.icon_name = "open-menu-symbolic";
            menu_button.menu_model = menu;
            menu_button.primary = true;
            menu_button.tooltip_text = _("Main Menu");
            header.pack_end (menu_button);

            views = new Adw.ViewStack ();
            views.add_titled_with_icon (build_explore (), "explore", _("Explore"), "flurry-explore-symbolic");
            views.add_titled_with_icon (build_installed (), "installed", _("Installed"), "flurry-installed-symbolic");
            var updates = views.add_titled_with_icon (build_updates (), "updates", _("Updates"), "flurry-updates-symbolic");
            views.notify["visible-child-name"].connect (() => {
                if (views.visible_child_name == "updates") check_updates.begin ();
            });

            var switcher = new Adw.ViewSwitcher ();
            switcher.stack = views;
            switcher.policy = Adw.ViewSwitcherPolicy.WIDE;
            header.title_widget = switcher;
            var switcher_bar = new Adw.ViewSwitcherBar ();
            switcher_bar.stack = views;
            updates.badge_number = 0;

            search_entry = new Gtk.SearchEntry ();
            search_entry.placeholder_text = _("Search nixpkgs, Flathub and Snap");
            search_entry.hexpand = true;
            var search_clamp = new Adw.Clamp ();
            search_clamp.maximum_size = 560;
            search_clamp.child = search_entry;
            search_bar = new Gtk.SearchBar ();
            search_bar.child = search_clamp;
            search_bar.connect_entry (search_entry);
            search_bar.key_capture_widget = this;
            search_bar.bind_property ("search-mode-enabled", search_button, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
            search_bar.notify["search-mode-enabled"].connect (() => {
                if (!search_bar.search_mode_enabled) {
                    search_entry.text = "";
                    pages.visible_child_name = "browse";
                }
            });
            search_entry.search_changed.connect (on_search_changed);
            search_entry.activate.connect (() => {
                var first = results_list.get_row_at_index (0) as AppRow;
                if (first != null) show_app (first.app);
            });

            pages = new Gtk.Stack ();
            pages.transition_type = Gtk.StackTransitionType.CROSSFADE;
            pages.add_named (views, "browse");
            pages.add_named (build_search (), "search");

            var toolbar = new Adw.ToolbarView ();
            toolbar.add_top_bar (header);
            toolbar.add_top_bar (search_bar);
            toolbar.content = pages;
            toolbar.add_bottom_bar (switcher_bar);
            toolbar.top_bar_style = Adw.ToolbarStyle.FLAT;

            var main_page = new Adw.NavigationPage (toolbar, "Flurry");
            main_page.tag = "main";
            nav = new Adw.NavigationView ();
            nav.add (main_page);
            toasts = new Adw.ToastOverlay ();
            toasts.child = nav;
            set_content (toasts);

            var narrow = new Adw.Breakpoint (Adw.BreakpointCondition.parse ("max-width: 640sp"));
            narrow.add_setter (switcher_bar, "reveal", true);
            narrow.add_setter (header, "title-widget", null);
            add_breakpoint (narrow);

            var reindex = new SimpleAction ("reindex", null);
            reindex.activate.connect (() => store.nix.load_index.begin (true));
            add_action (reindex);
        }

        // ── Explore ──────────────────────────────────────────────────────────

        Gtk.Widget build_explore () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 28);
            box.margin_top = 12;
            box.margin_bottom = 36;
            box.margin_start = 18;
            box.margin_end = 18;

            var hero = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            hero.add_css_class ("hero");
            var title = new Gtk.Label (_("Every app, every source"));
            title.add_css_class ("hero-title");
            title.xalign = 0;
            title.wrap = true;
            var sub = new Gtk.Label (_("nixpkgs, Flathub and Snap in one place. Install just for you with no rebuild, or for the whole system."));
            sub.add_css_class ("hero-subtitle");
            sub.xalign = 0;
            sub.wrap = true;
            sources_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            sources_box.margin_top = 8;
            hero.append (title);
            hero.append (sub);
            hero.append (sources_box);
            box.append (hero);

            shelves_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 28);
            var loading = new Adw.Spinner ();
            loading.height_request = 48;
            shelves_box.append (loading);
            box.append (shelves_box);

            var clamp = new Adw.Clamp ();
            clamp.maximum_size = 1180;
            clamp.tightening_threshold = 900;
            clamp.child = box;
            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.child = clamp;

            index_banner = new Adw.Banner ("");
            var page = new Adw.ToolbarView ();
            page.add_top_bar (index_banner);
            page.content = scroll;
            return page;
        }

        Gtk.Widget source_chip (string icon, string text, bool ok, string? button = null, owned Callback? on_click = null) {
            var chip = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            chip.add_css_class ("source-chip");
            if (!ok) chip.add_css_class ("off");
            var img = new Gtk.Image.from_icon_name (icon);
            img.pixel_size = 14;
            chip.append (img);
            chip.append (new Gtk.Label (text));
            if (button != null) {
                var b = new Gtk.Button.with_label (button);
                b.add_css_class ("flat");
                b.add_css_class ("chip-button");
                b.clicked.connect (() => on_click ());
                chip.append (b);
            }
            return chip;
        }

        void build_sources () {
            Gtk.Widget? c;
            while ((c = sources_box.get_first_child ()) != null) sources_box.remove (c);
            var nix = store.nix;
            if (nix.available) {
                var text = nix.pretty_version ();
                if (nix.index_ready) text += " · " + _("%s packages").printf (format_count (nix.package_count ()));
                sources_box.append (source_chip (Source.NIX.icon_name (), text, store.settings.use_nix));
            } else {
                sources_box.append (source_chip (Source.NIX.icon_name (), _("Nix isn't installed"), false));
            }
            if (store.flatpak.available) {
                if (store.flatpak.has_remote) {
                    sources_box.append (source_chip (Source.FLATPAK.icon_name (), "Flathub", store.settings.use_flatpak));
                } else {
                    sources_box.append (source_chip (Source.FLATPAK.icon_name (), _("Flathub is off"), false, _("Set Up"), () => setup_flathub ()));
                }
            }
            if (store.snap.available) {
                sources_box.append (source_chip (Source.SNAP.icon_name (), "Snap Store", store.settings.use_snap));
            }
        }

        string format_count (int n) {
            var s = n.to_string ();
            var out = new StringBuilder ();
            for (int i = 0; i < s.length; i++) {
                if (i > 0 && (s.length - i) % 3 == 0) out.append_c (',');
                out.append_c (s[i]);
            }
            return out.str;
        }

        void build_shelves () {
            Gtk.Widget? c;
            while ((c = shelves_box.get_first_child ()) != null) shelves_box.remove (c);
            foreach (var shelf in store.shelves) {
                var section = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
                var heading = new Gtk.Label (shelf.title);
                heading.add_css_class ("title-3");
                heading.xalign = 0;
                section.append (heading);
                var flow = new Gtk.FlowBox ();
                flow.homogeneous = true;
                flow.selection_mode = Gtk.SelectionMode.NONE;
                flow.min_children_per_line = 1;
                flow.max_children_per_line = 3;
                flow.column_spacing = 12;
                flow.row_spacing = 12;
                foreach (var pick in shelf.picks) {
                    var app = store.pick_app (pick);
                    if (app.offers.length == 0 && store.nix.index_ready) continue;
                    var tile = new AppTile (app);
                    tile.clicked.connect (() => show_app (tile.app));
                    flow.append (tile);
                }
                section.append (flow);
                shelves_box.append (section);
            }
            shelves_built = true;
        }

        void on_ready () {
            build_sources ();
            build_shelves ();
            refresh_installed ();
            if (!store.nix.available && !store.flatpak.available && !store.snap.available) {
                index_banner.title = _("No package source found. Flurry needs Nix, Flatpak or Snap.");
                index_banner.revealed = true;
            }
        }

        void on_index_changed () {
            var nix = store.nix;
            if (!nix.index_ready && nix.index_status != "") {
                index_banner.title = nix.index_status;
                index_banner.revealed = true;
            } else {
                index_banner.revealed = false;
            }
            build_sources ();
            if (nix.index_ready) {
                // Curated apps now get their nixpkgs offer too.
                foreach (var shelf in store.shelves) foreach (var pick in shelf.picks) store.pick_app (pick);
                build_shelves ();
                refresh_installed ();
                if (search_bar.search_mode_enabled && search_entry.text.strip () != "") run_search ();
            }
        }

        void setup_flathub () {
            var task = store.queue_job ("flathub", store.flatpak.setup_flathub ());
            toast (_("Setting up Flathub…"));
            task.finished.connect ((status) => {
                store.flatpak.probe.begin ((obj, res) => {
                    store.flatpak.probe.end (res);
                    build_sources ();
                    build_shelves ();
                    toast (status == 0 ? _("Flathub is ready") : _("Couldn't set up Flathub: %s").printf (task.job.tail (1)));
                });
            });
        }

        // ── Search ───────────────────────────────────────────────────────────

        Gtk.Widget build_search () {
            search_stack = new Gtk.Stack ();

            var spinner_page = new Adw.StatusPage ();
            spinner_page.paintable = new Adw.SpinnerPaintable (spinner_page);
            spinner_page.title = _("Searching…");
            search_stack.add_named (spinner_page, "searching");

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            box.margin_top = 12;
            box.margin_bottom = 24;
            box.margin_start = 12;
            box.margin_end = 12;
            search_note = new Gtk.Label ("");
            search_note.add_css_class ("dim-label");
            search_note.add_css_class ("caption");
            search_note.xalign = 0;
            search_note.wrap = true;
            results_list = boxed_list ();
            results_list.row_activated.connect ((row) => show_app (((AppRow) row).app));
            box.append (search_note);
            box.append (results_list);
            var clamp = new Adw.Clamp ();
            clamp.maximum_size = 860;
            clamp.child = box;
            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.child = clamp;
            search_stack.add_named (scroll, "results");

            no_results = new Adw.StatusPage ();
            no_results.icon_name = "system-search-symbolic";
            no_results.title = _("Nothing found");
            search_stack.add_named (no_results, "empty");
            return search_stack;
        }

        void on_search_changed () {
            if (search_timeout != 0) GLib.Source.remove (search_timeout);
            search_timeout = 0;
            if (search_entry.text.strip () == "") {
                pages.visible_child_name = "browse";
                return;
            }
            pages.visible_child_name = "search";
            search_timeout = Timeout.add (250, () => {
                search_timeout = 0;
                run_search ();
                return GLib.Source.REMOVE;
            });
        }

        void run_search () {
            if (search_cancel != null) search_cancel.cancel ();
            var cancel = new Cancellable ();
            search_cancel = cancel;
            var query = search_entry.text.strip ();
            search_stack.visible_child_name = "searching";
            var nix = store.nix;
            search_note.label = store.source_on (Source.NIX) && !nix.index_ready
                ? _("nixpkgs results appear once the package list is ready.") : "";
            search_note.visible = search_note.label != "";
            store.search.begin (query, cancel, (apps, done) => {
                if (cancel.is_cancelled ()) return;
                clear_list (results_list);
                int shown = 0;
                foreach (var app in apps) {
                    if (shown++ >= 80) break;
                    results_list.append (new AppRow (app, store));
                }
                if (apps.length > 0) search_stack.visible_child_name = "results";
                else if (done) {
                    no_results.description = _("No source has anything called “%s”.").printf (Markup.escape_text (query));
                    search_stack.visible_child_name = "empty";
                }
            });
        }

        // ── Installed ────────────────────────────────────────────────────────

        Gtk.Widget build_installed () {
            installed_stack = new Gtk.Stack ();
            installed_page = new Adw.PreferencesPage ();
            installed_stack.add_named (installed_page, "list");
            var empty = new Adw.StatusPage ();
            empty.icon_name = "flurry-installed-symbolic";
            empty.title = _("Nothing installed yet");
            empty.description = _("Apps you install with Flurry show up here.");
            installed_stack.add_named (empty, "empty");
            return installed_stack;
        }

        void refresh_installed () {
            foreach (var g in installed_groups) installed_page.remove (g);
            installed_groups = new GenericArray<Adw.PreferencesGroup> ();
            var apps = store.installed_apps ();
            var groups = new HashTable<string, Gtk.ListBox> (str_hash, str_equal);
            string[] order = { "nix-user", "nix-config", "flatpak", "snap" };
            string[] titles = { _("nixpkgs, just for you"), _("nixpkgs, in the system config"), "Flathub", "Snap Store" };
            for (int i = 0; i < order.length; i++) {
                var group = new Adw.PreferencesGroup ();
                group.title = titles[i];
                var list = boxed_list ();
                list.row_activated.connect ((row) => show_app (((AppRow) row).app));
                group.add (list);
                group.visible = false;
                installed_page.add (group);
                installed_groups.add (group);
                groups.insert (order[i], list);
            }
            int count = 0;
            foreach (var app in apps) {
                var o = app.installed_offer ();
                if (o == null) continue;
                string key;
                switch (o.source) {
                    case Source.NIX: key = o.scope == Scope.CONFIG ? "nix-config" : "nix-user"; break;
                    case Source.FLATPAK: key = "flatpak"; break;
                    default: key = "snap"; break;
                }
                groups.get (key).append (new AppRow (app, store));
                count++;
            }
            for (int i = 0; i < order.length; i++) {
                installed_groups[i].visible = groups.get (order[i]).get_first_child () != null;
            }
            installed_stack.visible_child_name = count > 0 ? "list" : "empty";
        }

        // ── Updates ──────────────────────────────────────────────────────────

        Gtk.Widget build_updates () {
            updates_stack = new Gtk.Stack ();
            var checking = new Adw.StatusPage ();
            checking.paintable = new Adw.SpinnerPaintable (checking);
            checking.title = _("Checking for updates…");
            updates_stack.add_named (checking, "checking");

            var page = new Adw.PreferencesPage ();
            var group = new Adw.PreferencesGroup ();
            group.title = _("App updates");
            update_all = new Gtk.Button.with_label (_("Update All"));
            update_all.add_css_class ("suggested-action");
            update_all.valign = Gtk.Align.CENTER;
            update_all.clicked.connect (run_update_all);
            group.header_suffix = update_all;
            updates_list = boxed_list ();
            updates_list.row_activated.connect ((row) => show_app (((AppRow) row).app));
            group.add (updates_list);
            page.add (group);

            system_group = new Adw.PreferencesGroup ();
            system_group.title = _("The system itself");
            page.add (system_group);
            updates_stack.add_named (page, "list");

            var current = new Adw.StatusPage ();
            current.icon_name = "flurry-updates-symbolic";
            current.title = _("Everything is up to date");
            updates_stack.add_named (current, "none");
            return updates_stack;
        }

        bool system_row_added = false;

        void add_system_row () {
            if (system_row_added) return;
            system_row_added = true;
            var row = new Adw.ActionRow ();
            if (store.nix.anix != null && find_program ("anix-control") != null) {
                row.title = _("System updates");
                row.subtitle = _("NixOS and your desktop update together in Anix Control, with a rollback if anything breaks.");
                var b = new Gtk.Button.with_label (_("Open Anix Control"));
                b.valign = Gtk.Align.CENTER;
                b.clicked.connect (() => launch_detached ({ "anix-control", "--page", "updates" }));
                row.add_suffix (b);
            } else if (store.nix.anix != null) {
                row.title = _("System updates");
                row.subtitle = _("Run “anix update” in a terminal to update NixOS and the desktop.");
            } else {
                row.title = _("System updates");
                row.subtitle = _("NixOS itself updates with “sudo nixos-rebuild switch --upgrade”, or your flake’s own update.");
            }
            system_group.add (row);
        }

        async void check_updates () {
            updates_stack.visible_child_name = "checking";
            add_system_row ();
            var apps = yield store.update_list ();
            clear_list (updates_list);
            foreach (var app in apps) updates_list.append (new AppRow (app, store));
            update_all.sensitive = apps.length > 0 && store.current == null;
            var page = views.get_page (updates_stack);
            page.badge_number = apps.length;
            page.needs_attention = apps.length > 0;
            updates_list.visible = apps.length > 0;
            updates_stack.visible_child_name = "list";
            if (apps.length == 0) {
                var empty_row = new Adw.ActionRow ();
                empty_row.title = _("All apps are up to date");
                empty_row.add_prefix (new Gtk.Image.from_icon_name ("object-select-symbolic"));
                updates_list.append (empty_row);
                updates_list.visible = true;
            }
        }

        void run_update_all () {
            update_all.sensitive = false;
            Task? last = null;
            if (store.nix.available && store.nix.index_ready) { last = store.queue_job (_("nixpkgs apps"), store.nix.upgrade_user ()); watch_update (last); }
            if (store.flatpak.available) { last = store.queue_job ("Flathub", store.flatpak.update_all ()); watch_update (last); }
            if (store.snap.available) { last = store.queue_job ("Snap", store.snap.update_all ()); watch_update (last); }
            toast (_("Updating your apps…"));
            if (last != null) {
                last.finished.connect (() => {
                    toast (update_failures == 0 ? _("Apps updated") : _("Some updates failed; open an app's page to retry"));
                    update_failures = 0;
                    check_updates.begin ();
                });
            }
        }

        int update_failures = 0;

        void watch_update (Task task) {
            task.finished.connect ((status) => {
                if (status != 0) update_failures++;
            });
        }

        // ── Navigation ───────────────────────────────────────────────────────

        public void show_app (App app) {
            nav.push (new DetailsPage (app, store, this));
        }

        public void begin_search (string words) {
            search_bar.search_mode_enabled = true;
            search_entry.text = words;
            search_entry.set_position (-1);
        }

        public void show_view (string name) {
            views.visible_child_name = name;
        }

        void on_task_finished (Task task) {
            if (task.offer.name == task.app.key && task.app.offers.length == 0) return; // whole-source jobs
            string text;
            if (task.status == 0) {
                text = task.action == Action.INSTALL ? _("%s is installed").printf (task.app.name) : _("%s was removed").printf (task.app.name);
            } else {
                text = task.action == Action.INSTALL ? _("%s couldn't be installed").printf (task.app.name) : _("%s couldn't be removed").printf (task.app.name);
            }
            var t = new Adw.Toast (text);
            if (task.status == 0 && task.action == Action.INSTALL && store.can_open (task.app)) {
                t.button_label = _("Open");
                var app = task.app;
                t.button_clicked.connect (() => store.open_app (app));
            } else if (task.status != 0) {
                t.button_label = _("Details");
                var app = task.app;
                t.button_clicked.connect (() => show_app (app));
            }
            toasts.add_toast (t);
        }
    }
}
