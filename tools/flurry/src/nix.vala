// nixpkgs through the `nix` command, which may be CppNix or Lix: both read the same nixpkgs.

namespace Flurry {

    /// One nixpkgs package from the index (top-level attributes only: apps, not library sets).
    public class NixEntry {
        public string attr;
        public string pname;
        public string version;
        public string description;
        public string homepage;
        public string main_program;
        public bool free;
        // Lowercased once, for searching.
        public string attr_lc;
        public string pname_lc;
        public string description_lc;
    }

    public class NixBackend : Object {
        public bool available { get; private set; default = false; }
        public bool is_lix { get; private set; default = false; }
        public string version_text { get; private set; default = ""; }
        public bool index_ready { get; private set; default = false; }
        public string index_status { get; private set; default = ""; }
        public string? anix { get; private set; default = null; }
        public string system { get; private set; }

        bool has_profile_add = false;
        GenericArray<NixEntry> entries = new GenericArray<NixEntry> ();
        HashTable<string, NixEntry> by_attr = new HashTable<string, NixEntry> (str_hash, str_equal);
        // attr -> (handle, store path name) for the user's profile.
        HashTable<string, string> profile_handles = new HashTable<string, string> (str_hash, str_equal);
        HashTable<string, string> profile_names = new HashTable<string, string> (str_hash, str_equal);
        GenericSet<string> system_names = new GenericSet<string> (str_hash, str_equal);
        GenericSet<string> config_packages = new GenericSet<string> (str_hash, str_equal);
        bool loading = false;

        public signal void index_changed ();

        // Every top-level package's name, version and description, in one evaluation. Anything
        // that throws (aliases for removed packages, broken packages) is skipped. Type checks come
        // before every attribute access, because tryEval only catches `throw` and `assert`.
        const string INDEX_EXPR = """lp: let
  pkgs = lp.@SYSTEM@;
  str = x: if builtins.isString x then x else if builtins.isList x && x != [ ] && builtins.isString (builtins.head x) then builtins.head x else "";
  isFree = l: if builtins.isAttrs l then l.free or true
    else if builtins.isList l then builtins.all (x: !(builtins.isAttrs x) || (x.free or true)) l
    else true;
  entry = n: let
    r = builtins.tryEval (let p = pkgs.${n}; in
      if builtins.isAttrs p && (p.type or "") == "derivation" then
        let m = if builtins.isAttrs (p.meta or null) then p.meta else { }; in
        if (m.broken or false) == true then null else
        let e = {
          a = n;
          p = str (p.pname or (builtins.parseDrvName (str (p.name or n))).name);
          v = str (p.version or "");
          d = str (m.description or "");
          h = str (m.homepage or "");
          m = str (m.mainProgram or "");
          f = isFree (m.license or null);
        }; in builtins.deepSeq e e
      else null);
  in if r.success then r.value else null;
in builtins.filter (x: x != null) (map entry (builtins.attrNames pkgs))""";

        construct {
            var machine = Posix.utsname ().machine;
            system = (machine == "arm64" ? "aarch64" : machine) + "-linux";
        }

        public string[] nix_argv (string[] args) {
            string[] argv = { "nix", "--extra-experimental-features", "nix-command flakes" };
            foreach (var a in args) argv += a;
            return argv;
        }

        public async void probe () {
            if (find_program ("nix") == null) {
                available = false;
                return;
            }
            var v = yield run ({ "nix", "--version" });
            available = v.ok;
            version_text = v.out_text.strip ();
            is_lix = version_text.down ().contains ("lix");
            // `nix profile install` became `nix profile add` in newer CppNix; Lix kept `install`.
            var add = yield run (nix_argv ({ "profile", "add", "--help" }));
            has_profile_add = add.ok;
            anix = find_program ("anix");
        }

        /// "Lix 2.95.4" or "Nix 2.35.2", from `nix --version`.
        public string pretty_version () {
            var parts = version_text.split (" ");
            var number = parts.length > 0 ? parts[parts.length - 1] : "";
            return (is_lix ? "Lix " : "Nix ") + number;
        }

        string cache_dir () {
            return Path.build_filename (Environment.get_user_cache_dir (), "flurry");
        }

        /// The nixpkgs revision `nixpkgs` resolves to, so the index is rebuilt only when it changes.
        async string revision_key () {
            var meta = yield run (nix_argv ({ "flake", "metadata", "nixpkgs", "--json" }));
            if (!meta.ok) return "";
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (meta.out_text);
                var root = parser.get_root ().get_object ();
                var locked = root.has_member ("locked") ? root.get_object_member ("locked") : null;
                string key = "";
                if (locked != null && locked.has_member ("narHash")) key = locked.get_string_member ("narHash");
                else if (root.has_member ("path")) key = root.get_string_member ("path");
                var clean = new StringBuilder ();
                for (int i = 0; i < key.length; i++) {
                    var c = key[i];
                    clean.append_c (c.isalnum () ? c : '_');
                }
                return clean.str;
            } catch (Error e) {
                return "";
            }
        }

        public async void load_index (bool rebuild = false) {
            if (!available || loading) return;
            loading = true;
            index_status = _("Checking nixpkgs…");
            index_changed ();
            var key = yield revision_key ();
            var dir = cache_dir ();
            DirUtils.create_with_parents (dir, 0755);
            var path = Path.build_filename (dir, "nixpkgs-%s-%s.json".printf (system, key != "" ? key : "offline"));

            string? text = null;
            if (!rebuild && FileUtils.test (path, FileTest.EXISTS)) {
                try { FileUtils.get_contents (path, out text); } catch (Error e) { text = null; }
            }
            if (text == null && key == "") {
                // Offline: use the newest index from an earlier run.
                text = newest_cached (dir);
            }
            if (text == null) {
                index_status = _("Building the package list. This happens once per nixpkgs update and takes a minute or two.");
                index_changed ();
                var expr = INDEX_EXPR.replace ("@SYSTEM@", system);
                var r = yield run (nix_argv ({ "eval", "--json", "nixpkgs#legacyPackages", "--apply", expr }));
                if (r.ok) {
                    text = r.out_text;
                    try {
                        FileUtils.set_contents (path, text);
                        prune_cache (dir, Path.get_basename (path));
                    } catch (Error e) {
                        warning ("could not save the package list: %s", e.message);
                    }
                } else {
                    index_status = _("Couldn't read nixpkgs: %s").printf (r.tail (3));
                    loading = false;
                    index_changed ();
                    return;
                }
            }
            parse_index (text);
            yield refresh_installed ();
            index_ready = true;
            index_status = "";
            loading = false;
            index_changed ();
        }

        string? newest_cached (string dir) {
            string? best = null;
            int64 best_time = 0;
            try {
                var d = Dir.open (dir);
                string? name;
                while ((name = d.read_name ()) != null) {
                    if (!name.has_prefix ("nixpkgs-" + system)) continue;
                    var full = Path.build_filename (dir, name);
                    var info = File.new_for_path (full).query_info ("time::modified", 0);
                    var t = info.get_modification_date_time ().to_unix ();
                    if (t > best_time) { best_time = t; best = full; }
                }
                if (best != null) {
                    string text;
                    FileUtils.get_contents (best, out text);
                    return text;
                }
            } catch (Error e) {}
            return null;
        }

        void prune_cache (string dir, string keep) {
            try {
                var d = Dir.open (dir);
                string? name;
                while ((name = d.read_name ()) != null) {
                    if (name.has_prefix ("nixpkgs-" + system) && name != keep) {
                        FileUtils.remove (Path.build_filename (dir, name));
                    }
                }
            } catch (Error e) {}
        }

        void parse_index (string text) {
            entries = new GenericArray<NixEntry> ();
            by_attr.remove_all ();
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (text);
                parser.get_root ().get_array ().foreach_element ((arr, i, node) => {
                    var o = node.get_object ();
                    var e = new NixEntry ();
                    e.attr = o.get_string_member ("a");
                    e.pname = o.get_string_member ("p");
                    e.version = o.get_string_member ("v");
                    e.description = o.get_string_member ("d");
                    e.homepage = o.get_string_member ("h");
                    e.main_program = o.get_string_member ("m");
                    e.free = o.get_boolean_member ("f");
                    e.attr_lc = e.attr.down ();
                    e.pname_lc = e.pname.down ();
                    e.description_lc = e.description.down ();
                    entries.add (e);
                    by_attr.insert (e.attr, e);
                });
            } catch (Error e) {
                warning ("bad package list: %s", e.message);
            }
        }

        public int package_count () {
            return entries.length;
        }

        Offer to_offer (NixEntry e) {
            var o = new Offer (Source.NIX, e.attr, e.pname);
            o.summary = e.description;
            o.version = e.version;
            o.homepage = e.homepage;
            o.main_program = e.main_program;
            o.free = e.free;
            apply_state (o, e);
            return o;
        }

        void apply_state (Offer o, NixEntry e) {
            o.scope = Scope.NONE;
            o.handle = null;
            o.installed_version = null;
            if (config_packages.contains (e.attr)) {
                o.scope = Scope.CONFIG;
            } else if (profile_handles.contains (e.attr)) {
                o.scope = Scope.USER;
                o.handle = profile_handles.get (e.attr);
                var stored = profile_names.get (e.attr);
                if (stored != null && stored.has_prefix (e.pname + "-")) {
                    o.installed_version = stored.substring (e.pname.length + 1);
                }
            } else if (system_names.contains (e.pname + "-" + e.version)) {
                o.scope = Scope.SYSTEM;
            }
        }

        public void refresh_offer (Offer o) {
            var e = by_attr.get (o.id);
            if (e != null) apply_state (o, e);
        }

        public Offer? lookup (string attr) {
            var e = by_attr.get (attr);
            return e != null ? to_offer (e) : null;
        }

        /// Ranked: exact name, then name prefix, then name or attribute contains, then description.
        public GenericArray<Offer> search (string query, int limit = 40) {
            var results = new GenericArray<Offer> ();
            var q = query.strip ().down ();
            if (q == "" || !index_ready) return results;
            var words = q.split_set (" \t");
            var scored = new GenericArray<NixEntry> ();
            var scores = new HashTable<NixEntry, int> (direct_hash, direct_equal);
            foreach (var e in entries.data) {
                int score = 0;
                if (e.pname_lc == q || e.attr_lc == q) score = 100;
                else if (e.pname_lc.has_prefix (q) || e.attr_lc.has_prefix (q)) score = 70;
                else if (e.pname_lc.contains (q) || e.attr_lc.contains (q)) score = 50;
                else {
                    bool all = true;
                    foreach (var w in words) {
                        if (w == "") continue;
                        if (!e.description_lc.contains (w) && !e.pname_lc.contains (w)) { all = false; break; }
                    }
                    if (all) score = 20;
                }
                if (score == 0) continue;
                // Things with a program to run are more likely to be what someone shopping wants.
                if (e.main_program != "") score += 5;
                scored.add (e);
                scores.insert (e, score);
            }
            scored.sort_with_data ((a, b) => {
                var d = scores.get (b) - scores.get (a);
                return d != 0 ? d : a.pname.length - b.pname.length;
            });
            for (int i = 0; i < scored.length && i < limit; i++) results.add (to_offer (scored[i]));
            return results;
        }

        public async void refresh_installed () {
            if (!available) return;
            profile_handles.remove_all ();
            profile_names.remove_all ();
            var prefix = "legacyPackages." + system + ".";
            var list = yield run (nix_argv ({ "profile", "list", "--json" }));
            if (list.ok) {
                try {
                    var parser = new Json.Parser ();
                    parser.load_from_data (list.out_text);
                    var root = parser.get_root ().get_object ();
                    var elements = root.get_member ("elements");
                    // Named elements since Nix 2.20; a list (removed by index) in older Nix and Lix.
                    if (elements.get_node_type () == Json.NodeType.OBJECT) {
                        var obj = elements.get_object ();
                        foreach (var name in obj.get_members ()) {
                            note_profile_element (obj.get_object_member (name), name, prefix);
                        }
                    } else if (elements.get_node_type () == Json.NodeType.ARRAY) {
                        var arr = elements.get_array ();
                        for (uint i = 0; i < arr.get_length (); i++) {
                            note_profile_element (arr.get_object_element (i), i.to_string (), prefix);
                        }
                    }
                } catch (Error e) {
                    warning ("could not read the nix profile: %s", e.message);
                }
            }

            system_names.remove_all ();
            var refs = yield run ({ "nix-store", "--query", "--references", "/run/current-system/sw" });
            if (refs.ok) {
                foreach (var line in refs.out_text.split ("\n")) {
                    var base_name = Path.get_basename (line.strip ());
                    var dash = base_name.index_of_char ('-');
                    if (dash > 0) system_names.add (base_name.substring (dash + 1));
                }
            }

            config_packages.remove_all ();
            foreach (var p in read_anix_packages ()) config_packages.add (p);

            foreach (var e in entries.data) { /* state is applied lazily when offers are made */ }
        }

        void note_profile_element (Json.Object element, string handle, string prefix) {
            if (!element.has_member ("attrPath")) return;
            var attr = element.get_string_member ("attrPath");
            if (attr.has_prefix (prefix)) attr = attr.substring (prefix.length);
            profile_handles.insert (attr, handle);
            if (element.has_member ("storePaths")) {
                var paths = element.get_array_member ("storePaths");
                if (paths.get_length () > 0) {
                    var base_name = Path.get_basename (paths.get_string_element (0));
                    var dash = base_name.index_of_char ('-');
                    if (dash > 0) profile_names.insert (attr, base_name.substring (dash + 1));
                }
            }
        }

        /// The packages listed in ANIX's system config (one `anix.packages = with pkgs; [ ... ];`
        /// line, as `anix package add` writes it). Empty without ANIX.
        public string[] read_anix_packages () {
            string[] out = {};
            var dir = Environment.get_variable ("ANIX_SYSTEM_CONFIG") ?? "/etc/nixos";
            string text;
            try {
                if (!FileUtils.get_contents (Path.build_filename (dir, "anix.nix"), out text)) return out;
            } catch (Error e) {
                return out;
            }
            foreach (var line in text.split ("\n")) {
                var t = line.strip ();
                if (!t.has_prefix ("anix.packages")) continue;
                var open = t.index_of_char ('[');
                var close = t.last_index_of_char (']');
                if (open < 0 || close <= open) continue;
                foreach (var word in t.substring (open + 1, close - open - 1).split_set (" \t")) {
                    if (word != "") out += word;
                }
            }
            return out;
        }

        /// Installed in the user's profile, newest nixpkgs differs from the installed version.
        public GenericArray<Offer> updates () {
            var out = new GenericArray<Offer> ();
            foreach (var attr in profile_handles.get_keys ()) {
                var e = by_attr.get (attr);
                if (e == null) continue;
                var stored = profile_names.get (attr);
                if (stored != null && stored != e.pname + "-" + e.version) out.add (to_offer (e));
            }
            return out;
        }

        public GenericArray<Offer> installed () {
            var out = new GenericArray<Offer> ();
            var seen = new GenericSet<string> (str_hash, str_equal);
            foreach (var attr in config_packages.get_values ()) {
                var e = by_attr.get (attr);
                if (e != null && !seen.contains (attr)) { out.add (to_offer (e)); seen.add (attr); }
            }
            foreach (var attr in profile_handles.get_keys ()) {
                var e = by_attr.get (attr);
                if (e != null && !seen.contains (attr)) { out.add (to_offer (e)); seen.add (attr); }
                else if (e == null && !seen.contains (attr)) {
                    // Installed from something other than this nixpkgs (another flake, an old name).
                    var o = new Offer (Source.NIX, attr, attr);
                    o.scope = Scope.USER;
                    o.handle = profile_handles.get (attr);
                    o.summary = _("Installed from another flake");
                    out.add (o);
                    seen.add (attr);
                }
            }
            return out;
        }

        string[] unfree_env (Offer o) {
            return o.free ? new string[] {} : new string[] { "NIXPKGS_ALLOW_UNFREE=1" };
        }

        public Job install_user (Offer o) {
            string[] args = { "profile", has_profile_add ? "add" : "install" };
            if (!o.free) args += "--impure";
            args += "nixpkgs#" + o.id;
            return new Job (nix_argv (args), unfree_env (o));
        }

        public Job remove_user (Offer o) {
            return new Job (nix_argv ({ "profile", "remove", o.handle ?? o.id }));
        }

        public Job upgrade_user () {
            // CppNix 2.20+ wants --all; Lix (and older Nix) take a regex over attribute paths.
            return new Job (nix_argv ({ "profile", "upgrade", is_lix ? ".*" : "--all" }), { "NIXPKGS_ALLOW_UNFREE=1" });
        }

        /// Adds or removes a package in ANIX's system config and rebuilds, as one ANIX transaction
        /// (a failed rebuild is rolled back). Only on systems that have ANIX.
        public Job? change_system (Offer o, bool add) throws Error {
            if (anix == null) return null;
            var plan = write_plan ("{\"planVersion\":1,\"language\":\"flurry\",\"operations\":[{\"op\":\"%s\",\"name\":%s}]}"
                .printf (add ? "package.add" : "package.remove", Json.to_string (new Json.Node.alloc ().init_string (o.id), false)));
            return new Job (as_root ({ anix, "apply-plan", plan, "--yes" }, { "ANIX_ASSUME_YES=1" }));
        }

        /// Switches the system between Nix and Lix through ANIX (`anix set nix <nix|lix>`).
        public Job? switch_implementation (bool lix) throws Error {
            if (anix == null) return null;
            var plan = write_plan ("{\"planVersion\":1,\"language\":\"flurry\",\"operations\":[{\"op\":\"set\",\"key\":\"nix\",\"value\":\"%s\"}]}"
                .printf (lix ? "lix" : "nix"));
            return new Job (as_root ({ anix, "apply-plan", plan, "--yes" }, { "ANIX_ASSUME_YES=1" }));
        }

        string write_plan (string json) throws Error {
            var dir = Path.build_filename (Environment.get_user_runtime_dir (), "flurry");
            DirUtils.create_with_parents (dir, 0700);
            var path = Path.build_filename (dir, "plan-%lld.json".printf (get_real_time ()));
            FileUtils.set_contents (path, json);
            return path;
        }

        public string? program_path (Offer o) {
            if (o.main_program == "") return null;
            foreach (var dir in new string[] {
                Path.build_filename (Environment.get_home_dir (), ".nix-profile", "bin"),
                Path.build_filename (Environment.get_variable ("XDG_STATE_HOME") ?? Path.build_filename (Environment.get_home_dir (), ".local", "state"), "nix", "profile", "bin"),
                "/run/current-system/sw/bin",
            }) {
                var p = Path.build_filename (dir, o.main_program);
                if (FileUtils.test (p, FileTest.IS_EXECUTABLE)) return p;
            }
            return null;
        }
    }
}
