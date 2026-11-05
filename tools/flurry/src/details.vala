// One app: pick where to get it from, install, open or remove, and see what happened.

namespace Flurry {

    public class DetailsPage : Adw.NavigationPage {
        public App app { get; construct; }
        Store store;
        Window window;
        Offer? chosen = null;

        Gtk.Image icon;
        Gtk.Label name_label;
        Gtk.Label summary_label;
        Gtk.Label meta_label;
        Gtk.Box actions;
        Adw.PreferencesGroup sources_group;
        Gtk.ListBox sources_list;
        Adw.PreferencesGroup about_group;
        Gtk.ListBox about_list;
        Adw.Banner unfree_banner;
        Gtk.Revealer progress_revealer;
        Gtk.Label progress_label;
        Gtk.TextView log_view;
        Adw.ExpanderRow log_row;

        public DetailsPage (App app, Store store, Window window) {
            Object (app: app, title: app.name, tag: "details");
            this.store = store;
            this.window = window;
            build ();
            chosen = app.best (store.settings.source_order ());
            refresh ();
            app.changed.connect (refresh);
            if (store.current != null && store.current.app == app) watch (store.current);
        }

        void build () {
            var view = new Adw.ToolbarView ();
            view.add_top_bar (new Adw.HeaderBar ());

            unfree_banner = new Adw.Banner (_("Proprietary software: its license limits how you can use and share it"));
            view.add_top_bar (unfree_banner);

            var page = new Gtk.Box (Gtk.Orientation.VERTICAL, 24);
            page.margin_top = 18;
            page.margin_bottom = 32;
            page.margin_start = 18;
            page.margin_end = 18;

            // Header: icon, name, summary, actions.
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
            header.add_css_class ("details-header");
            icon = app_icon (app, 112);
            icon.valign = Gtk.Align.START;
            header.append (icon);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            text.valign = Gtk.Align.CENTER;
            text.hexpand = true;
            name_label = new Gtk.Label ("");
            name_label.xalign = 0;
            name_label.wrap = true;
            name_label.add_css_class ("title-1");
            summary_label = new Gtk.Label ("");
            summary_label.xalign = 0;
            summary_label.wrap = true;
            summary_label.add_css_class ("dim-label");
            meta_label = new Gtk.Label ("");
            meta_label.xalign = 0;
            meta_label.add_css_class ("caption");
            meta_label.add_css_class ("dim-label");
            actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions.margin_top = 10;
            text.append (name_label);
            text.append (summary_label);
            text.append (meta_label);
            text.append (actions);
            header.append (text);
            page.append (header);

            // Progress, shown while something runs.
            progress_revealer = new Gtk.Revealer ();
            var progress_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var progress_list = boxed_list ();
            var status_row = new Adw.ActionRow ();
            var spinner = new Adw.Spinner ();
            status_row.add_prefix (spinner);
            progress_label = new Gtk.Label ("");
            progress_label.xalign = 0;
            progress_label.wrap = true;
            progress_label.hexpand = true;
            progress_label.margin_top = 12;
            progress_label.margin_bottom = 12;
            status_row.add_prefix (progress_label);
            progress_list.append (status_row);
            log_row = new Adw.ExpanderRow ();
            log_row.title = _("Details");
            log_view = new Gtk.TextView ();
            log_view.editable = false;
            log_view.monospace = true;
            log_view.wrap_mode = Gtk.WrapMode.CHAR;
            log_view.add_css_class ("log-view");
            var log_scroll = new Gtk.ScrolledWindow ();
            log_scroll.min_content_height = 180;
            log_scroll.max_content_height = 320;
            log_scroll.child = log_view;
            log_row.add_row (log_scroll);
            progress_list.append (log_row);
            progress_box.append (progress_list);
            progress_revealer.child = progress_box;
            page.append (progress_revealer);

            sources_group = new Adw.PreferencesGroup ();
            sources_group.title = _("Get it from");
            sources_list = boxed_list ();
            sources_group.add (sources_list);
            page.append (sources_group);

            about_group = new Adw.PreferencesGroup ();
            about_group.title = _("About");
            about_list = boxed_list ();
            about_group.add (about_list);
            page.append (about_group);

            var clamp = new Adw.Clamp ();
            clamp.maximum_size = 860;
            clamp.child = page;
            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.child = clamp;
            view.content = scroll;
            child = view;
        }

        void refresh () {
            title = app.name;
            name_label.label = app.name;
            summary_label.label = app.summary;
            summary_label.visible = app.summary != "";
            icon.gicon = app.icon;
            var inst = app.installed_offer ();
            if (inst != null) chosen = inst;
            if (chosen == null || app.offer (chosen.source) == null) chosen = app.best (store.settings.source_order ());
            else chosen = app.offer (chosen.source);

            if (chosen != null) {
                var bits = new GenericArray<string> ();
                bits.add (chosen.source.label ());
                var v = chosen.installed_version ?? chosen.version;
                if (v != null && v != "") bits.add (v);
                if (chosen.installed) bits.add (chosen.scope.label ());
                meta_label.label = string.joinv (" · ", bits.data);
                unfree_banner.revealed = !chosen.free;
            } else {
                meta_label.label = "";
                unfree_banner.revealed = false;
            }
            build_actions ();
            build_sources ();
            build_about ();
        }

        void build_actions () {
            Gtk.Widget? c;
            while ((c = actions.get_first_child ()) != null) actions.remove (c);
            if (app.busy) {
                var b = new Gtk.Button.with_label (_("Working…"));
                b.sensitive = false;
                b.add_css_class ("pill");
                actions.append (b);
                return;
            }
            if (chosen == null) {
                var l = new Gtk.Label (_("No source has this app right now."));
                l.add_css_class ("dim-label");
                actions.append (l);
                return;
            }
            if (chosen.installed) {
                if (store.can_open (app)) {
                    var open = new Gtk.Button.with_label (_("Open"));
                    open.add_css_class ("pill");
                    open.add_css_class ("suggested-action");
                    open.clicked.connect (() => {
                        if (!store.open_app (app)) window.toast (_("Couldn't find a program to start for %s").printf (app.name));
                    });
                    actions.append (open);
                }
                if (chosen.removable) {
                    var remove = new Gtk.Button.from_icon_name ("user-trash-symbolic");
                    remove.tooltip_text = _("Remove");
                    remove.add_css_class ("circular");
                    remove.add_css_class ("destructive-action");
                    remove.valign = Gtk.Align.CENTER;
                    remove.clicked.connect (() => confirm_remove.begin ());
                    actions.append (remove);
                } else if (chosen.scope == Scope.SYSTEM) {
                    var l = new Gtk.Label (_("Your system config includes this; remove it there."));
                    l.add_css_class ("dim-label");
                    l.add_css_class ("caption");
                    l.wrap = true;
                    actions.append (l);
                }
            } else {
                var install = new Gtk.Button.with_label (_("Install"));
                install.add_css_class ("pill");
                install.add_css_class ("suggested-action");
                install.clicked.connect (() => start_install.begin ());
                actions.append (install);
                var hint = new Gtk.Label (install_hint ());
                hint.add_css_class ("dim-label");
                hint.add_css_class ("caption");
                hint.valign = Gtk.Align.CENTER;
                hint.wrap = true;
                actions.append (hint);
            }
        }

        string install_hint () {
            switch (chosen.source) {
                case Source.NIX:
                    return store.installs_to_system (chosen)
                        ? _("Adds it to the system config and rebuilds")
                        : _("Just for you, no rebuild");
                case Source.FLATPAK:
                    return _("Sandboxed, from Flathub");
                default:
                    return _("Needs your password");
            }
        }

        void build_sources () {
            clear_list (sources_list);
            Gtk.CheckButton? group = null;
            var inst = app.installed_offer ();
            foreach (var src in store.settings.source_order ()) {
                var o = app.offer (src);
                if (o == null) continue;
                var row = new Adw.ActionRow ();
                row.title = src.label ();
                var sub = new GenericArray<string> ();
                sub.add (o.id);
                if (o.version != "") sub.add (o.version);
                row.subtitle = Markup.escape_text (string.joinv (" · ", sub.data));
                var check = new Gtk.CheckButton ();
                if (group != null) check.group = group; else group = check;
                check.active = chosen == o;
                check.sensitive = inst == null && !app.busy;
                check.toggled.connect (() => {
                    if (check.active) { chosen = o; refresh (); }
                });
                row.add_prefix (check);
                row.activatable_widget = check;
                if (o.installed) row.add_suffix (source_badge (o.source, true));
                sources_list.append (row);
            }
            if (chosen != null && chosen.source == Source.NIX && !chosen.installed && store.nix.anix != null) {
                var target = new Adw.ComboRow ();
                target.title = _("Install for");
                target.model = new Gtk.StringList ({ _("Just me (no rebuild)"), _("Everyone (system config, rebuilds)") });
                target.selected = store.settings.nix_target == "system" ? 1 : 0;
                target.notify["selected"].connect (() => {
                    store.settings.nix_target = target.selected == 1 ? "system" : "user";
                    store.settings.save ();
                    build_actions ();
                });
                sources_list.append (target);
            }
            sources_group.visible = app.offers.length > 0;
        }

        void build_about () {
            clear_list (about_list);
            if (chosen == null) { about_group.visible = false; return; }
            about_group.visible = true;
            add_info (_("Package"), chosen.id, true);
            if (chosen.installed_version != null && chosen.installed_version != "" && chosen.installed_version != chosen.version) {
                add_info (_("Installed version"), chosen.installed_version);
                add_info (_("Newest version"), chosen.version);
            } else if (chosen.version != "") {
                add_info (_("Version"), chosen.version);
            }
            if (chosen.main_program != "") add_info (_("Command"), chosen.main_program, true);
            add_info (_("License"), chosen.free ? _("Free software") : _("Proprietary"));
            if (chosen.homepage != "") {
                var row = new Adw.ActionRow ();
                row.title = _("Website");
                row.subtitle = Markup.escape_text (chosen.homepage);
                row.activatable = true;
                row.add_suffix (new Gtk.Image.from_icon_name ("adw-external-link-symbolic"));
                var url = chosen.homepage;
                row.activated.connect (() => {
                    var launcher = new Gtk.UriLauncher (url);
                    launcher.launch.begin (window, null);
                });
                about_list.append (row);
            }
        }

        void add_info (string title, string value, bool mono = false) {
            var row = new Adw.ActionRow ();
            row.title = title;
            row.subtitle = Markup.escape_text (value);
            row.subtitle_selectable = true;
            row.add_css_class ("property");
            if (mono) row.add_css_class ("monospace-subtitle");
            about_list.append (row);
        }

        async void start_install () {
            if (chosen == null) return;
            if (store.installs_to_system (chosen)) {
                var dialog = new Adw.AlertDialog (_("Add %s to the system?").printf (app.name),
                    _("Flurry adds it to your system config and rebuilds the system. That can take a few minutes. If the rebuild fails, the change is rolled back."));
                dialog.add_response ("cancel", _("Cancel"));
                dialog.add_response ("go", _("Add and Rebuild"));
                dialog.set_response_appearance ("go", Adw.ResponseAppearance.SUGGESTED);
                dialog.default_response = "go";
                if ((yield dialog.choose (window, null)) != "go") return;
            }
            run_task (Action.INSTALL);
        }

        async void confirm_remove () {
            var dialog = new Adw.AlertDialog (_("Remove %s?").printf (app.name),
                chosen.scope == Scope.CONFIG
                    ? _("It is taken out of your system config and the system is rebuilt.")
                    : _("You can install it again at any time."));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("remove", _("Remove"));
            dialog.set_response_appearance ("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            if ((yield dialog.choose (window, null)) != "remove") return;
            run_task (Action.REMOVE);
        }

        void run_task (Action action) {
            try {
                var task = store.enqueue (app, chosen, action);
                if (task == null) {
                    window.toast (_("This needs ANIX, which isn't on this system"));
                    return;
                }
                watch (task);
            } catch (Error e) {
                window.toast (e.message);
            }
        }

        void watch (Task task) {
            log_view.buffer.text = task.job.log.str;
            var verb = task.action == Action.INSTALL ? _("Installing %s…") : _("Removing %s…");
            progress_label.label = (store.current == task ? verb : _("Waiting for another install to finish…")).printf (app.name);
            if (task.rebuild) progress_label.label += "\n" + _("Rebuilding the system. This can take a few minutes.");
            progress_revealer.reveal_child = true;
            ulong line_id = task.job.line.connect ((text) => {
                Gtk.TextIter end;
                log_view.buffer.get_end_iter (out end);
                log_view.buffer.insert (ref end, text + "\n", -1);
                log_view.buffer.get_end_iter (out end);
                log_view.scroll_to_iter (end, 0, false, 0, 0);
            });
            ulong start_id = store.task_started.connect ((t) => {
                if (t == task) progress_label.label = verb.printf (app.name);
            });
            task.finished.connect ((status) => {
                task.job.disconnect (line_id);
                store.disconnect (start_id);
                if (status == 0) {
                    progress_revealer.reveal_child = false;
                } else {
                    progress_label.label = (task.action == Action.INSTALL ? _("%s couldn't be installed.") : _("%s couldn't be removed.")).printf (app.name)
                        + "\n" + task.job.tail (2);
                    log_row.expanded = true;
                }
                refresh ();
            });
        }
    }
}
