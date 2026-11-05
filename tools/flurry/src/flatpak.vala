// Flatpak apps (Flathub, or any other configured remote) through the `flatpak` command.

namespace Flurry {

    public class FlatpakBackend : Object {
        public bool available { get; private set; default = false; }
        public bool has_user_flathub { get; private set; default = false; }
        public bool has_system_flathub { get; private set; default = false; }
        public bool has_remote { get { return has_user_flathub || has_system_flathub; } }
        /// "auto", "user" or "system": where new apps go.
        public string scope_preference { get; set; default = "auto"; }

        HashTable<string, Offer> installed_apps = new HashTable<string, Offer> (str_hash, str_equal);
        string arch;

        construct {
            var machine = Posix.utsname ().machine;
            arch = machine == "arm64" ? "aarch64" : machine;
        }

        public async void probe () {
            available = find_program ("flatpak") != null;
            if (!available) return;
            has_user_flathub = false;
            has_system_flathub = false;
            var r = yield run ({ "flatpak", "remotes", "--columns=name,options" });
            foreach (var line in r.out_text.split ("\n")) {
                var cols = line.split ("\t");
                if (cols.length < 2 || cols[0].strip () != "flathub") continue;
                if (cols[1].contains ("user")) has_user_flathub = true;
                if (cols[1].contains ("system")) has_system_flathub = true;
            }
        }

        /// Adds Flathub for this user only (no password) and fetches its app list.
        public Job setup_flathub () {
            return new Job ({ "sh", "-c",
                "flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo && flatpak update --user --appstream -y" });
        }

        string install_scope () {
            if (scope_preference == "user") return "user";
            if (scope_preference == "system") return "system";
            return has_system_flathub ? "system" : "user";
        }

        public string? icon_for (string app_id, string? installation) {
            string[] roots = {
                Path.build_filename (Environment.get_user_data_dir (), "flatpak"),
                "/var/lib/flatpak",
            };
            foreach (var root in roots) {
                foreach (var size in new string[] { "128x128", "64x64" }) {
                    var p = Path.build_filename (root, "appstream", "flathub", arch, "active", "icons", size, app_id + ".png");
                    if (FileUtils.test (p, FileTest.EXISTS)) return p;
                }
                // Installed apps also export their icon.
                var exported = Path.build_filename (root, "exports", "share", "icons", "hicolor", "128x128", "apps", app_id + ".png");
                if (FileUtils.test (exported, FileTest.EXISTS)) return exported;
                var svg = Path.build_filename (root, "exports", "share", "icons", "hicolor", "scalable", "apps", app_id + ".svg");
                if (FileUtils.test (svg, FileTest.EXISTS)) return svg;
            }
            return null;
        }

        public async GenericArray<Offer> search (string query) {
            var results = new GenericArray<Offer> ();
            if (!available || query.strip () == "") return results;
            var r = yield run ({ "flatpak", "search", "--columns=application,name,description,version,remotes", query.strip () });
            if (!r.ok) return results;
            var seen = new GenericSet<string> (str_hash, str_equal);
            foreach (var line in r.out_text.split ("\n")) {
                var cols = line.split ("\t");
                if (cols.length < 5) continue;
                var id = cols[0].strip ();
                if (id == "" || seen.contains (id) || id.has_suffix (".Locale") || id.has_suffix (".Debug")) continue;
                seen.add (id);
                var o = new Offer (Source.FLATPAK, id, cols[1].strip ());
                o.summary = cols[2].strip ();
                o.version = cols[3].strip ();
                o.remote = cols[4].strip ().split (",")[0];
                o.icon_file = icon_for (id, null);
                apply_state (o);
                results.add (o);
            }
            return results;
        }

        public Offer make (string app_id, string name, string summary) {
            var o = new Offer (Source.FLATPAK, app_id, name);
            o.summary = summary;
            o.remote = "flathub";
            o.icon_file = icon_for (app_id, null);
            apply_state (o);
            return o;
        }

        public void apply_state (Offer o) {
            var inst = installed_apps.get (o.id);
            if (inst != null) {
                o.scope = inst.installation == "system" ? Scope.SYSTEM : Scope.USER;
                o.installation = inst.installation;
                o.installed_version = inst.installed_version;
                if (o.version == "") o.version = inst.installed_version ?? "";
            } else {
                o.scope = Scope.NONE;
                o.installation = null;
            }
        }

        public async void refresh_installed () {
            installed_apps.remove_all ();
            if (!available) return;
            var r = yield run ({ "flatpak", "list", "--app", "--columns=application,name,version,installation,origin" });
            foreach (var line in r.out_text.split ("\n")) {
                var cols = line.split ("\t");
                if (cols.length < 4) continue;
                var o = new Offer (Source.FLATPAK, cols[0].strip (), cols[1].strip ());
                o.installed_version = cols[2].strip ();
                o.version = o.installed_version;
                o.installation = cols[3].strip () == "system" ? "system" : "user";
                o.scope = o.installation == "system" ? Scope.SYSTEM : Scope.USER;
                o.remote = cols.length > 4 ? cols[4].strip () : "flathub";
                o.icon_file = icon_for (o.id, o.installation);
                installed_apps.insert (o.id, o);
            }
        }

        public GenericArray<Offer> installed () {
            var out = new GenericArray<Offer> ();
            foreach (var o in installed_apps.get_values ()) out.add (o);
            return out;
        }

        public async GenericArray<Offer> updates () {
            var out = new GenericArray<Offer> ();
            if (!available) return out;
            var r = yield run ({ "flatpak", "remote-ls", "--updates", "--app", "--columns=application,name,version" });
            foreach (var line in r.out_text.split ("\n")) {
                var cols = line.split ("\t");
                if (cols.length < 2 || cols[0].strip () == "") continue;
                var o = new Offer (Source.FLATPAK, cols[0].strip (), cols[1].strip ());
                o.version = cols.length > 2 ? cols[2].strip () : "";
                o.icon_file = icon_for (o.id, null);
                apply_state (o);
                out.add (o);
            }
            return out;
        }

        public Job install (Offer o) {
            // System installs ask for a password through Flatpak's own polkit helper.
            return new Job ({ "flatpak", "install", "-y", "--noninteractive", "--" + install_scope (), o.remote ?? "flathub", o.id });
        }

        public Job remove (Offer o) {
            return new Job ({ "flatpak", "uninstall", "-y", "--noninteractive", "--" + (o.installation ?? "user"), o.id });
        }

        public Job update_all () {
            return new Job ({ "flatpak", "update", "-y", "--noninteractive" });
        }
    }
}
