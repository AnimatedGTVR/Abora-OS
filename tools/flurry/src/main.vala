// Flurry: a software shop for NixOS and NixOS-based systems.

namespace Flurry {

    public class Application : Adw.Application {
        Store store;
        Window? window = null;
        string? start_page = null;
        string? start_search = null;

        public Application () {
            Object (application_id: "io.github.AnimatedGTVR.Flurry", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
            add_main_option ("page", 0, OptionFlags.NONE, OptionArg.STRING, _("Open on a page: explore, installed or updates"), "PAGE");
            add_main_option ("search", 's', OptionFlags.NONE, OptionArg.STRING, _("Start with a search"), "WORDS");
            add_main_option ("version", 0, OptionFlags.NONE, OptionArg.NONE, _("Show the version"), null);
        }

        public override int handle_local_options (VariantDict options) {
            if (options.contains ("version")) {
                print ("flurry %s\n", VERSION);
                return 0;
            }
            return -1;
        }

        public override int command_line (ApplicationCommandLine cmd) {
            var options = cmd.get_options_dict ();
            options.lookup ("page", "s", out start_page);
            options.lookup ("search", "s", out start_search);
            activate ();
            return 0;
        }

        public override void startup () {
            base.startup ();
            store = new Store ();
            var css = new Gtk.CssProvider ();
            css.load_from_string (STYLE);
            Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            var theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
            var icons = Environment.get_variable ("FLURRY_ICON_DIR");
            if (icons != null) theme.add_search_path (icons);

            var prefs = new SimpleAction ("preferences", null);
            prefs.activate.connect (() => {
                if (window != null) new Preferences (store, window).present (window);
            });
            add_action (prefs);
            set_accels_for_action ("app.preferences", { "<Control>comma" });

            var about = new SimpleAction ("about", null);
            about.activate.connect (show_about);
            add_action (about);

            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => this.quit ());
            add_action (quit);
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("window.close", { "<Control>w" });
        }

        public override void activate () {
            if (window == null) {
                window = new Window (this, store);
                store.start.begin ();
            }
            if (start_page != null) window.show_view (start_page);
            window.present ();
            if (start_search != null) {
                window.begin_search (start_search);
                start_search = null;
            }
        }

        void show_about () {
            var about = new Adw.AboutDialog ();
            about.application_name = "Flurry";
            about.application_icon = "io.github.AnimatedGTVR.Flurry";
            about.version = VERSION;
            about.developer_name = "The Abora OS contributors";
            about.comments = _("Apps from nixpkgs (with Nix or Lix), Flathub and Snap, in one place. For NixOS and every NixOS-based system.");
            about.license_type = Gtk.License.GPL_3_0;
            about.website = "https://github.com/AnimatedGTVR/Abora-OS";
            about.issue_url = "https://github.com/AnimatedGTVR/Abora-OS/issues";
            about.present (window);
        }
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
    return new Flurry.Application ().run (args);
}
