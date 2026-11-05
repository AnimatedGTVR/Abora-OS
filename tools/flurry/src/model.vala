// What Flurry knows about an app: one App, offered by one or more sources.

namespace Flurry {

    public enum Source {
        NIX,
        FLATPAK,
        SNAP;

        public string label () {
            switch (this) {
                case NIX: return "Nixpkgs";
                case FLATPAK: return "Flathub";
                default: return "Snap Store";
            }
        }

        public string key () {
            switch (this) {
                case NIX: return "nix";
                case FLATPAK: return "flatpak";
                default: return "snap";
            }
        }

        public static Source? parse (string? text) {
            switch (text) {
                case "nix": return NIX;
                case "flatpak": return FLATPAK;
                case "snap": return SNAP;
                default: return null;
            }
        }

        public string icon_name () {
            switch (this) {
                case NIX: return "flurry-nix-symbolic";
                case FLATPAK: return "flurry-flatpak-symbolic";
                default: return "flurry-snap-symbolic";
            }
        }
    }

    /// Where an installed copy lives. CONFIG means it is listed in the declarative system config
    /// (anix.packages), so removing it is a rebuild; SYSTEM means something else in the system
    /// config brings it in, so Flurry can't remove it.
    public enum Scope {
        NONE,
        USER,
        SYSTEM,
        CONFIG;

        public string label () {
            switch (this) {
                case USER: return _("Installed for you");
                case SYSTEM: return _("Part of the system");
                case CONFIG: return _("In the system config");
                default: return "";
            }
        }
    }

    /// One source's copy of an app.
    public class Offer : Object {
        public Source source { get; construct; }
        /// The nixpkgs attribute, the Flatpak app id, or the snap name.
        public string id { get; construct; }
        public string name { get; set; }
        public string summary { get; set; default = ""; }
        public string version { get; set; default = ""; }
        public string homepage { get; set; default = ""; }
        public string main_program { get; set; default = ""; }
        public bool free { get; set; default = true; }
        public bool classic { get; set; default = false; }
        public string? icon_file { get; set; default = null; }
        public string? remote { get; set; default = null; }
        public Scope scope { get; set; default = Scope.NONE; }
        public string? installed_version { get; set; default = null; }
        /// How the source names the installed copy (nix profile element name or index).
        public string? handle { get; set; default = null; }
        /// Flatpak: "user" or "system" installation.
        public string? installation { get; set; default = null; }

        public bool installed { get { return scope != Scope.NONE; } }
        public bool removable { get { return scope == Scope.USER || scope == Scope.CONFIG; } }

        public Offer (Source source, string id, string name) {
            Object (source: source, id: id, name: name);
        }
    }

    /// Lowercase letters and digits only: "Firefox", "firefox" and "org.mozilla.firefox"'s last part
    /// all become "firefox", so the same app from different sources shows up once.
    public string app_key (string text) {
        var builder = new StringBuilder ();
        unichar c;
        int i = 0;
        while (text.get_next_char (ref i, out c)) {
            if (c.isalnum ()) builder.append_unichar (c.tolower ());
        }
        return builder.str;
    }

    public class App : Object {
        public string key { get; construct; }
        public GenericArray<Offer> offers = new GenericArray<Offer> ();
        /// A curated name and summary win over what sources report.
        public string? curated_name { get; set; default = null; }
        public string? curated_summary { get; set; default = null; }
        public string? curated_icon { get; set; default = null; }
        public Source? preferred_source { get; set; default = null; }
        /// Set while an install or removal runs.
        public bool busy { get; set; default = false; }
        public signal void changed ();

        public App (string key) {
            Object (key: key);
        }

        public Offer? offer (Source source) {
            foreach (var o in offers) if (o.source == source) return o;
            return null;
        }

        public void add_offer (Offer o) {
            for (int i = 0; i < offers.length; i++) {
                if (offers[i].source == o.source) {
                    offers[i] = o;
                    changed ();
                    return;
                }
            }
            offers.add (o);
            changed ();
        }

        public Offer? installed_offer () {
            foreach (var o in offers) if (o.installed) return o;
            return null;
        }

        public bool installed { get { return installed_offer () != null; } }

        /// The offer to show first: an installed one, else the app's own preference, else the user's
        /// source order.
        public Offer? best (Source[] order) {
            var inst = installed_offer ();
            if (inst != null) return inst;
            if (preferred_source != null) {
                var o = offer (preferred_source);
                if (o != null) return o;
            }
            foreach (var s in order) {
                var o = offer (s);
                if (o != null) return o;
            }
            return offers.length > 0 ? offers[0] : null;
        }

        public string name {
            owned get {
                if (curated_name != null) return curated_name;
                // Flathub and Snap names are written for people ("Visual Studio Code"); a nixpkgs
                // pname is a package name, so it's the last choice.
                var f = offer (Source.FLATPAK);
                if (f != null && f.name != "") return f.name;
                var s = offer (Source.SNAP);
                if (s != null && s.name != "") return s.name;
                var n = offer (Source.NIX);
                return n != null ? n.name : key;
            }
        }

        public string summary {
            owned get {
                if (curated_summary != null) return curated_summary;
                foreach (var src in new Source[] { Source.FLATPAK, Source.SNAP, Source.NIX }) {
                    var o = offer (src);
                    if (o != null && o.summary != "") return o.summary;
                }
                return "";
            }
        }

        public Icon icon {
            owned get {
                foreach (var o in offers) {
                    if (o.icon_file != null) return new FileIcon (File.new_for_path (o.icon_file));
                }
                string[] names = {};
                if (curated_icon != null) names += curated_icon;
                var f = offer (Source.FLATPAK);
                if (f != null) names += f.id;
                foreach (var o in offers) {
                    if (o.source == Source.NIX) {
                        names += o.id;
                        if (o.main_program != "") names += o.main_program;
                    } else if (o.source == Source.SNAP) {
                        names += o.id;
                    }
                }
                names += key;
                names += "application-x-executable";
                return new ThemedIcon.from_names (names);
            }
        }
    }
}
