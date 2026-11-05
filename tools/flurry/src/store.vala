// The one place that knows every source: search, install state, the curated catalog, settings
// and the queue that runs installs one at a time.

namespace Flurry {

    public struct Pick {
        public string name;
        public string summary;
        public string icon;
        public string nix;
        public string flatpak;
        public string snap;
        /// "" = the user's source order; otherwise this app's best source.
        public string prefer;
    }

    public struct Shelf {
        public string title;
        public string icon;
        public Pick[] picks;
    }

    public class Settings : Object {
        public string order { get; set; default = "nix,flatpak,snap"; }
        public bool use_nix { get; set; default = true; }
        public bool use_flatpak { get; set; default = true; }
        public bool use_snap { get; set; default = true; }
        public string flatpak_scope { get; set; default = "auto"; }
        /// "user" (nix profile, no rebuild) or "system" (anix config + rebuild) for Nix installs.
        public string nix_target { get; set; default = "user"; }

        string path () {
            return Path.build_filename (Environment.get_user_config_dir (), "flurry", "flurry.ini");
        }

        public void load () {
            var kf = new KeyFile ();
            try {
                kf.load_from_file (path (), KeyFileFlags.NONE);
                if (kf.has_key ("sources", "order")) order = kf.get_string ("sources", "order");
                if (kf.has_key ("sources", "nix")) use_nix = kf.get_boolean ("sources", "nix");
                if (kf.has_key ("sources", "flatpak")) use_flatpak = kf.get_boolean ("sources", "flatpak");
                if (kf.has_key ("sources", "snap")) use_snap = kf.get_boolean ("sources", "snap");
                if (kf.has_key ("flatpak", "scope")) flatpak_scope = kf.get_string ("flatpak", "scope");
                if (kf.has_key ("nix", "target")) nix_target = kf.get_string ("nix", "target");
            } catch (Error e) {
                // First run, or an unreadable file: the defaults are fine.
            }
        }

        public void save () {
            var kf = new KeyFile ();
            kf.set_string ("sources", "order", order);
            kf.set_boolean ("sources", "nix", use_nix);
            kf.set_boolean ("sources", "flatpak", use_flatpak);
            kf.set_boolean ("sources", "snap", use_snap);
            kf.set_string ("flatpak", "scope", flatpak_scope);
            kf.set_string ("nix", "target", nix_target);
            try {
                DirUtils.create_with_parents (Path.get_dirname (path ()), 0755);
                kf.save_to_file (path ());
            } catch (Error e) {
                warning ("could not save settings: %s", e.message);
            }
        }

        public Source[] source_order () {
            Source[] out = {};
            foreach (var part in order.split (",")) {
                var s = Source.parse (part.strip ());
                if (s != null) out += s;
            }
            foreach (var s in new Source[] { Source.NIX, Source.FLATPAK, Source.SNAP }) {
                bool found = false;
                foreach (var o in out) if (o == s) found = true;
                if (!found) out += s;
            }
            return out;
        }
    }

    public enum Action { INSTALL, REMOVE }

    public class Task : Object {
        public App app { get; construct; }
        public Offer offer { get; construct; }
        public Action action { get; construct; }
        public Job job { get; construct; }
        public bool rebuild { get; construct; }
        public int status = -1;
        public signal void finished (int status);

        public Task (App app, Offer offer, Action action, Job job, bool rebuild) {
            Object (app: app, offer: offer, action: action, job: job, rebuild: rebuild);
        }
    }

    public class Store : Object {
        public NixBackend nix = new NixBackend ();
        public FlatpakBackend flatpak = new FlatpakBackend ();
        public SnapBackend snap = new SnapBackend ();
        public Settings settings = new Settings ();
        public bool probed { get; private set; default = false; }

        HashTable<string, App> apps = new HashTable<string, App> (str_hash, str_equal);
        Queue<Task> queue = new Queue<Task> ();
        public Task? current { get; private set; default = null; }

        public signal void ready ();
        public signal void installed_changed ();
        public signal void task_started (Task task);
        public signal void task_finished (Task task);

        public Shelf[] shelves = {
            { _("Browsers"), "web-browser-symbolic", {
                { "Zen Browser", _("A calm, private browser built on Firefox"), "app.zen_browser.zen", "", "app.zen_browser.zen", "", "flatpak" },
                { "Firefox", _("Fast, private and free web browser"), "firefox", "firefox", "org.mozilla.firefox", "firefox", "" },
                { "Chromium", _("The open-source browser behind Chrome"), "chromium", "chromium", "org.chromium.Chromium", "chromium", "" },
                { "Brave", _("Blocks ads and trackers by default"), "brave", "brave", "com.brave.Browser", "brave", "" },
                { "LibreWolf", _("Firefox, hardened for privacy"), "librewolf", "librewolf", "io.gitlab.librewolf-community", "", "" },
            } },
            { _("Chat & mail"), "chat-symbolic", {
                { "Discord", _("Voice, video and text with your communities"), "discord", "discord", "com.discordapp.Discord", "discord", "" },
                { "Signal", _("Private messenger"), "signal-desktop", "signal-desktop", "org.signal.Signal", "signal-desktop", "" },
                { "Telegram", _("Fast cloud-based messaging"), "telegram", "telegram-desktop", "org.telegram.desktop", "telegram-desktop", "" },
                { "Element", _("Secure chat on Matrix"), "element-desktop", "element-desktop", "im.riot.Riot", "element-desktop", "" },
                { "Thunderbird", _("Mail, calendar and contacts"), "thunderbird", "thunderbird", "org.mozilla.Thunderbird", "thunderbird", "" },
            } },
            { _("Music & video"), "folder-music-symbolic", {
                { "VLC", _("Plays almost any video or audio file"), "vlc", "vlc", "org.videolan.VLC", "vlc", "" },
                { "mpv", _("A minimal, powerful video player"), "mpv", "mpv", "io.mpv.Mpv", "", "" },
                { "Spotify", _("Music and podcasts"), "spotify-client", "spotify", "com.spotify.Client", "spotify", "" },
                { "OBS Studio", _("Record and stream your screen"), "com.obsproject.Studio", "obs-studio", "com.obsproject.Studio", "obs-studio", "" },
                { "Audacity", _("Record and edit audio"), "audacity", "audacity", "org.audacityteam.Audacity", "audacity", "" },
            } },
            { _("Create"), "applications-graphics-symbolic", {
                { "GIMP", _("Edit photos and images"), "gimp", "gimp", "org.gimp.GIMP", "gimp", "" },
                { "Inkscape", _("Vector graphics and drawing"), "inkscape", "inkscape", "org.inkscape.Inkscape", "inkscape", "" },
                { "Krita", _("Digital painting"), "krita", "krita", "org.kde.krita", "krita", "" },
                { "Blender", _("3D modelling, animation and rendering"), "blender", "blender", "org.blender.Blender", "blender", "" },
                { "darktable", _("Develop and manage your photos"), "darktable", "darktable", "org.darktable.Darktable", "", "" },
            } },
            { _("Work"), "x-office-document-symbolic", {
                { "LibreOffice", _("Documents, spreadsheets and presentations"), "libreoffice-main", "libreoffice", "org.libreoffice.LibreOffice", "libreoffice", "" },
                { "OnlyOffice", _("Office suite that opens Microsoft formats well"), "onlyoffice-desktopeditors", "onlyoffice-desktopeditors", "org.onlyoffice.desktopeditors", "onlyoffice-desktopeditors", "" },
                { "Obsidian", _("Notes in plain Markdown files"), "obsidian", "obsidian", "md.obsidian.Obsidian", "obsidian", "" },
                { "Bitwarden", _("Password manager"), "bitwarden", "bitwarden-desktop", "com.bitwarden.desktop", "bitwarden", "" },
                { "Joplin", _("Notes and to-dos that sync"), "joplin", "joplin-desktop", "net.cozic.joplin_desktop", "joplin-desktop", "" },
            } },
            { _("Code"), "utilities-terminal-symbolic", {
                { "VSCodium", _("VS Code without the telemetry"), "vscodium", "vscodium", "com.vscodium.codium", "codium", "" },
                { "Visual Studio Code", _("Microsoft's code editor"), "vscode", "vscode", "com.visualstudio.code", "code", "" },
                { "Zed", _("A fast, collaborative code editor"), "zed", "zed-editor", "dev.zed.Zed", "zed", "" },
                { "Neovim", _("Vim, extended"), "nvim", "neovim", "io.neovim.nvim", "nvim", "nix" },
                { "Ghostty", _("A fast, native terminal"), "com.mitchellh.ghostty", "ghostty", "", "ghostty", "nix" },
            } },
            { _("Games"), "input-gaming-symbolic", {
                // Steam needs system integration on NixOS (programs.steam); the Flatpak works anywhere.
                { "Steam", _("Valve's game store and launcher"), "steam", "", "com.valvesoftware.Steam", "steam", "flatpak" },
                { "Heroic", _("Epic, GOG and Amazon games"), "com.heroicgameslauncher.hgl", "heroic", "com.heroicgameslauncher.hgl", "heroic", "" },
                { "Lutris", _("All your games in one library"), "lutris", "lutris", "net.lutris.Lutris", "", "" },
                { "Prism Launcher", _("Minecraft instances, done right"), "org.prismlauncher.PrismLauncher", "prismlauncher", "org.prismlauncher.PrismLauncher", "prismlauncher", "" },
                { "RetroArch", _("Retro games and emulators"), "retroarch", "retroarch", "org.libretro.RetroArch", "retroarch", "" },
            } },
        };

        public Store () {
            settings.load ();
            flatpak.scope_preference = settings.flatpak_scope;
        }

        public bool source_on (Source s) {
            switch (s) {
                case Source.NIX: return settings.use_nix && nix.available;
                case Source.FLATPAK: return settings.use_flatpak && flatpak.available;
                default: return settings.use_snap && snap.available;
            }
        }

        public async void start () {
            yield nix.probe ();
            yield flatpak.probe ();
            yield snap.probe ();
            yield flatpak.refresh_installed ();
            yield snap.refresh_installed ();
            probed = true;
            ready ();
            if (source_on (Source.NIX)) {
                nix.index_changed.connect (() => {
                    if (nix.index_ready) refresh_states ();
                });
                yield nix.load_index ();
            }
        }

        public App app_for (string key) {
            var app = apps.get (key);
            if (app == null) {
                app = new App (key);
                apps.insert (key, app);
            }
            return app;
        }

        /// The App for a curated pick, with an offer from each source that has it.
        public App pick_app (Pick p) {
            var app = app_for (app_key (p.name));
            app.curated_name = p.name;
            app.curated_summary = p.summary;
            app.curated_icon = p.icon;
            app.preferred_source = Source.parse (p.prefer);
            if (p.flatpak != "" && flatpak.available && app.offer (Source.FLATPAK) == null) {
                app.add_offer (flatpak.make (p.flatpak, p.name, p.summary));
            }
            if (p.snap != "" && snap.available && app.offer (Source.SNAP) == null) {
                app.add_offer (snap.make (p.snap, p.name, p.summary));
            }
            if (p.nix != "" && nix.index_ready && app.offer (Source.NIX) == null) {
                var o = nix.lookup (p.nix);
                if (o != null) app.add_offer (o);
            }
            return app;
        }

        /// Files an offer under its App: the same app from several sources is one entry.
        App file_offer (Offer o) {
            string key;
            if (o.source == Source.FLATPAK) {
                var parts = o.id.split (".");
                var tail = app_key (parts[parts.length - 1]);
                var by_name = app_key (o.name);
                key = apps.contains (by_name) ? by_name : (apps.contains (tail) ? tail : by_name);
            } else {
                key = app_key (o.name);
                if (o.source == Source.NIX && !apps.contains (key) && apps.contains (app_key (o.id))) key = app_key (o.id);
            }
            var app = app_for (key);
            var existing = app.offer (o.source);
            if (existing == null || existing.id == o.id) app.add_offer (o);
            return app;
        }

        public delegate void ResultsFunc (GenericArray<App> apps, bool done);

        /// Searches every enabled source; each source's results arrive as soon as it answers.
        public async void search (string query, Cancellable cancel, owned ResultsFunc on_results) {
            var found = new GenericArray<App> ();
            var seen = new GenericSet<App> (direct_hash, direct_equal);
            int pending = 0;

            if (source_on (Source.NIX) && nix.index_ready) {
                foreach (var o in nix.search (query)) add_result (file_offer (o), found, seen);
                on_results (found, false);
            }
            SourceFunc resume = search.callback;
            if (source_on (Source.FLATPAK)) {
                pending++;
                flatpak.search.begin (query, (obj, res) => {
                    var offers = flatpak.search.end (res);
                    if (!cancel.is_cancelled ()) {
                        foreach (var o in offers) add_result (file_offer (o), found, seen);
                        on_results (found, false);
                    }
                    if (--pending == 0) resume ();
                });
            }
            if (source_on (Source.SNAP)) {
                pending++;
                snap.search.begin (query, (obj, res) => {
                    var offers = snap.search.end (res);
                    if (!cancel.is_cancelled ()) {
                        foreach (var o in offers) add_result (file_offer (o), found, seen);
                        on_results (found, false);
                    }
                    if (--pending == 0) resume ();
                });
            }
            if (pending > 0) yield;
            if (!cancel.is_cancelled ()) on_results (rank (found, query), true);
        }

        void add_result (App app, GenericArray<App> found, GenericSet<App> seen) {
            if (seen.contains (app)) return;
            seen.add (app);
            found.add (app);
        }

        GenericArray<App> rank (GenericArray<App> found, string query) {
            var q = app_key (query);
            var scores = new HashTable<App, int> (direct_hash, direct_equal);
            foreach (var app in found) {
                var k = app_key (app.name);
                int score = 0;
                if (k == q) score += 100;
                else if (k.has_prefix (q)) score += 60;
                else if (k.contains (q)) score += 40;
                score += 8 * (int) app.offers.length;
                if (app.offer (Source.FLATPAK) != null || app.offer (Source.SNAP) != null) score += 10;
                scores.insert (app, score);
            }
            found.sort_with_data ((a, b) => scores.get (b) - scores.get (a));
            return found;
        }

        public GenericArray<App> installed_apps () {
            var out = new GenericArray<App> ();
            var seen = new GenericSet<App> (direct_hash, direct_equal);
            var all = new GenericArray<Offer> ();
            if (nix.available) foreach (var o in nix.installed ()) all.add (o);
            if (flatpak.available) foreach (var o in flatpak.installed ()) all.add (o);
            if (snap.available) foreach (var o in snap.installed ()) all.add (o);
            foreach (var o in all) {
                var app = file_offer (o);
                if (!seen.contains (app)) { seen.add (app); out.add (app); }
            }
            out.sort ((a, b) => strcmp (a.name.down (), b.name.down ()));
            return out;
        }

        public async GenericArray<App> update_list () {
            var out = new GenericArray<App> ();
            var offers = new GenericArray<Offer> ();
            if (nix.index_ready) foreach (var o in nix.updates ()) offers.add (o);
            foreach (var o in yield flatpak.updates ()) offers.add (o);
            foreach (var o in yield snap.updates ()) offers.add (o);
            foreach (var o in offers) out.add (file_offer (o));
            return out;
        }

        /// Re-reads what is installed everywhere and updates every known offer.
        public async void reload_installed () {
            yield nix.refresh_installed ();
            yield flatpak.refresh_installed ();
            yield snap.refresh_installed ();
            refresh_states ();
        }

        void refresh_states () {
            foreach (var app in apps.get_values ()) {
                foreach (var o in app.offers) {
                    switch (o.source) {
                        case Source.NIX: nix.refresh_offer (o); break;
                        case Source.FLATPAK: flatpak.apply_state (o); break;
                        default: snap.apply_state (o); break;
                    }
                }
                app.changed ();
            }
            installed_changed ();
        }

        /// Whether installing this offer rebuilds the system (Nix offer, system target, ANIX present).
        public bool installs_to_system (Offer o) {
            return o.source == Source.NIX && settings.nix_target == "system" && nix.anix != null;
        }

        public Task? enqueue (App app, Offer offer, Action action) throws Error {
            Job? job = null;
            bool rebuild = false;
            switch (offer.source) {
                case Source.NIX:
                    if (action == Action.INSTALL) {
                        if (installs_to_system (offer)) { job = nix.change_system (offer, true); rebuild = true; }
                        else job = nix.install_user (offer);
                    } else if (offer.scope == Scope.CONFIG) {
                        job = nix.change_system (offer, false);
                        rebuild = true;
                    } else {
                        job = nix.remove_user (offer);
                    }
                    break;
                case Source.FLATPAK:
                    job = action == Action.INSTALL ? flatpak.install (offer) : flatpak.remove (offer);
                    break;
                default:
                    job = action == Action.INSTALL ? snap.install (offer) : snap.remove (offer);
                    break;
            }
            if (job == null) return null;
            var task = new Task (app, offer, action, job, rebuild);
            app.busy = true;
            app.changed ();
            queue.push_tail (task);
            if (current == null) next.begin ();
            return task;
        }

        /// A whole-source job (update everything), queued like an install.
        public Task queue_job (string name, Job job) {
            var app = new App (name);
            var task = new Task (app, new Offer (Source.NIX, name, name), Action.INSTALL, job, false);
            queue.push_tail (task);
            if (current == null) next.begin ();
            return task;
        }

        async void next () {
            while (!queue.is_empty ()) {
                current = queue.pop_head ();
                task_started (current);
                current.status = yield current.job.run ();
                yield reload_installed ();
                current.app.busy = false;
                current.app.changed ();
                var done = current;
                current = null;
                done.finished (done.status);
                task_finished (done);
            }
        }

        public bool open_app (App app) {
            var o = app.installed_offer ();
            if (o == null) return false;
            switch (o.source) {
                case Source.FLATPAK:
                    launch_detached ({ "flatpak", "run", o.id });
                    return true;
                case Source.SNAP:
                    launch_detached ({ "snap", "run", o.id });
                    return true;
                default:
                    // A desktop entry whose program is this package's, else the program itself.
                    foreach (var info in AppInfo.get_all ()) {
                        var exe = info.get_executable ();
                        if (exe != null && o.main_program != "" && Path.get_basename (exe) == o.main_program) {
                            try { info.launch (null, null); return true; } catch (Error e) {}
                        }
                    }
                    var path = nix.program_path (o);
                    if (path == null) return false;
                    launch_detached ({ path });
                    return true;
            }
        }

        public bool can_open (App app) {
            var o = app.installed_offer ();
            if (o == null) return false;
            if (o.source != Source.NIX) return true;
            return o.main_program != "" && nix.program_path (o) != null;
        }
    }
}
