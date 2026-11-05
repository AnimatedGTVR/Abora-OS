// Small reusable pieces: the source badge, the app row (lists) and the app tile (Explore).

namespace Flurry {

    public delegate void Callback ();

    public Gtk.Widget source_badge (Source s, bool installed = false) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        box.add_css_class ("source-badge");
        box.add_css_class ("source-" + s.key ());
        if (installed) box.add_css_class ("installed");
        var icon = new Gtk.Image.from_icon_name (installed ? "object-select-symbolic" : s.icon_name ());
        icon.pixel_size = 12;
        box.append (icon);
        box.append (new Gtk.Label (s.label ()));
        box.valign = Gtk.Align.CENTER;
        return box;
    }

    public Gtk.Image app_icon (App app, int size) {
        var image = new Gtk.Image.from_gicon (app.icon);
        image.pixel_size = size;
        image.add_css_class ("app-icon");
        if (size >= 64) image.add_css_class ("icon-dropshadow");
        return image;
    }

    /// A list row: icon, name, summary, where it comes from, and its state.
    public class AppRow : Adw.ActionRow {
        public App app { get; construct; }
        Gtk.Box badges;
        Gtk.Image icon;
        Gtk.Widget state;
        Store store;

        public AppRow (App app, Store store) {
            Object (app: app, activatable: true);
            this.store = store;
            icon = app_icon (app, 40);
            add_prefix (icon);
            badges = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            badges.valign = Gtk.Align.CENTER;
            add_suffix (badges);
            var arrow = new Gtk.Image.from_icon_name ("go-next-symbolic");
            arrow.add_css_class ("dim-label");
            add_suffix (arrow);
            update ();
            app.changed.connect (update);
        }

        void update () {
            title = Markup.escape_text (app.name);
            subtitle = Markup.escape_text (app.summary);
            subtitle_lines = 1;
            icon.gicon = app.icon;
            Gtk.Widget? child;
            while ((child = badges.get_first_child ()) != null) badges.remove (child);
            if (app.busy) {
                var spinner = new Adw.Spinner ();
                badges.append (spinner);
                return;
            }
            var inst = app.installed_offer ();
            if (inst != null) {
                badges.append (source_badge (inst.source, true));
            } else {
                foreach (var o in app.offers) badges.append (source_badge (o.source));
            }
        }
    }

    /// An Explore tile: a card with the icon, name and summary.
    public class AppTile : Gtk.Button {
        public App app { get; construct; }
        Gtk.Image icon;
        Gtk.Label name_label;
        Gtk.Label summary_label;
        Gtk.Box status;

        public AppTile (App app) {
            Object (app: app);
            add_css_class ("card");
            add_css_class ("app-tile");
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            icon = app_icon (app, 56);
            box.append (icon);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            text.valign = Gtk.Align.CENTER;
            text.hexpand = true;
            name_label = new Gtk.Label ("");
            name_label.xalign = 0;
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.add_css_class ("heading");
            summary_label = new Gtk.Label ("");
            summary_label.xalign = 0;
            summary_label.wrap = true;
            summary_label.lines = 2;
            summary_label.ellipsize = Pango.EllipsizeMode.END;
            summary_label.max_width_chars = 28;
            summary_label.add_css_class ("caption");
            summary_label.add_css_class ("dim-label");
            status = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            status.margin_top = 4;
            text.append (name_label);
            text.append (summary_label);
            text.append (status);
            box.append (text);
            child = box;
            update ();
            app.changed.connect (update);
        }

        void update () {
            name_label.label = app.name;
            summary_label.label = app.summary;
            icon.gicon = app.icon;
            Gtk.Widget? c;
            while ((c = status.get_first_child ()) != null) status.remove (c);
            if (app.busy) {
                status.append (new Adw.Spinner ());
            } else if (app.installed) {
                status.append (source_badge (app.installed_offer ().source, true));
            } else {
                foreach (var o in app.offers) status.append (source_badge (o.source));
            }
        }
    }

    /// A boxed list that hides itself while empty.
    public Gtk.ListBox boxed_list () {
        var list = new Gtk.ListBox ();
        list.selection_mode = Gtk.SelectionMode.NONE;
        list.add_css_class ("boxed-list");
        return list;
    }

    public void clear_list (Gtk.ListBox list) {
        Gtk.Widget? child;
        while ((child = list.get_first_child ()) != null) list.remove (child);
    }
}
