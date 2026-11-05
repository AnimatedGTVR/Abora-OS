// Snaps through the `snap` command. NixOS doesn't ship snapd, so this source is usually off;
// it lights up wherever snapd is running.

namespace Flurry {

    public class SnapBackend : Object {
        public bool available { get; private set; default = false; }
        HashTable<string, Offer> installed_snaps = new HashTable<string, Offer> (str_hash, str_equal);
        Regex columns;

        construct {
            try {
                columns = new Regex ("\\s{2,}");
            } catch (Error e) {
                assert_not_reached ();
            }
        }

        public async void probe () {
            available = find_program ("snap") != null && FileUtils.test ("/run/snapd.socket", FileTest.EXISTS);
        }

        string[] split_columns (string line, int max) {
            try {
            return columns.split_full (line.strip (), -1, 0, 0, max);
            } catch (RegexError e) {
                return { line.strip () };
            }
        }

        public async GenericArray<Offer> search (string query) {
            var results = new GenericArray<Offer> ();
            if (!available || query.strip () == "") return results;
            var r = yield run ({ "snap", "find", query.strip () });
            if (!r.ok) return results;
            var lines = r.out_text.split ("\n");
            // Name  Version  Publisher  Notes  Summary
            for (int i = 1; i < lines.length; i++) {
                var cols = split_columns (lines[i], 5);
                if (cols.length < 5) continue;
                var o = new Offer (Source.SNAP, cols[0], cols[0]);
                o.version = cols[1];
                o.classic = cols[3].contains ("classic");
                o.summary = cols[4];
                apply_state (o);
                results.add (o);
            }
            return results;
        }

        public Offer make (string name, string title, string summary) {
            var o = new Offer (Source.SNAP, name, title);
            o.summary = summary;
            apply_state (o);
            return o;
        }

        public void apply_state (Offer o) {
            var inst = installed_snaps.get (o.id);
            o.scope = inst != null ? Scope.USER : Scope.NONE;
            o.installed_version = inst != null ? inst.installed_version : null;
        }

        public async void refresh_installed () {
            installed_snaps.remove_all ();
            if (!available) return;
            var r = yield run ({ "snap", "list" });
            var lines = r.out_text.split ("\n");
            // Name  Version  Rev  Tracking  Publisher  Notes
            for (int i = 1; i < lines.length; i++) {
                var cols = split_columns (lines[i], 6);
                if (cols.length < 2) continue;
                var notes = cols.length > 5 ? cols[5] : "";
                // Bases, snapd itself and other plumbing aren't apps.
                if (notes.contains ("base") || notes.contains ("snapd") || cols[0] == "snapd" || cols[0].has_prefix ("core") || cols[0].has_prefix ("gnome-") || cols[0].has_prefix ("gtk-common")) continue;
                var o = new Offer (Source.SNAP, cols[0], cols[0]);
                o.installed_version = cols[1];
                o.version = cols[1];
                o.scope = Scope.USER;
                installed_snaps.insert (o.id, o);
            }
        }

        public GenericArray<Offer> installed () {
            var out = new GenericArray<Offer> ();
            foreach (var o in installed_snaps.get_values ()) out.add (o);
            return out;
        }

        public async GenericArray<Offer> updates () {
            var out = new GenericArray<Offer> ();
            if (!available) return out;
            var r = yield run ({ "snap", "refresh", "--list" });
            var lines = r.out_text.split ("\n");
            for (int i = 1; i < lines.length; i++) {
                var cols = split_columns (lines[i], 5);
                if (cols.length < 2) continue;
                var o = new Offer (Source.SNAP, cols[0], cols[0]);
                o.version = cols[1];
                apply_state (o);
                out.add (o);
            }
            return out;
        }

        string snap_bin () {
            return find_program ("snap") ?? "/usr/bin/snap";
        }

        public Job install (Offer o) {
            string[] argv = { snap_bin (), "install", o.id };
            if (o.classic) argv += "--classic";
            return new Job (as_root (argv));
        }

        public Job remove (Offer o) {
            return new Job (as_root ({ snap_bin (), "remove", o.id }));
        }

        public Job update_all () {
            return new Job (as_root ({ snap_bin (), "refresh" }));
        }
    }
}
