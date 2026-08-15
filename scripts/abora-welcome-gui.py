#!/usr/bin/env python3
"""Abora Welcome — GUI first-steps and update-check app for Abora OS."""

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib

import os
import re
import shutil
import subprocess
import threading
from pathlib import Path

def _resolve_logo_path() -> str:
    """Installed systems always have /etc/abora/Abora-LOGO.png; a dev
    checkout doesn't, so fall back to the repo-relative asset (works when
    run via `make test-welcome` from the repo root) before giving up."""
    if os.environ.get('ABORA_LOGO'):
        return os.environ['ABORA_LOGO']
    for candidate in (
        '/etc/abora/Abora-LOGO.png',
        Path(__file__).resolve().parent.parent / 'assets' / 'Abora-LOGO.png',
    ):
        if Path(candidate).exists():
            return str(candidate)
    return '/etc/abora/Abora-LOGO.png'


LOGO_FILE      = _resolve_logo_path()
UPDATE_SCRIPT  = os.environ.get('ABORA_UPDATE_SCRIPT', '/etc/abora/update.sh')
GAMING_WELCOME_SCRIPT = os.environ.get('ABORA_GAMING_WELCOME_GUI', '/etc/abora/gaming-welcome-gui.py')
CONFIG_PATH    = Path(os.environ.get('ABORA_SYSTEM_CONFIG', '/etc/nixos')) / 'abora-local.nix'
CHANNEL_FILE   = Path(os.environ.get('ABORA_SYSTEM_CONFIG', '/etc/nixos')) / 'abora' / 'channel'
SEEN_MARKER    = Path.home() / '.cache' / 'abora' / 'welcome-seen'
CONFIG_DIR     = Path.home() / '.config' / 'abora'
WELCOME_CONFIG = CONFIG_DIR / 'welcome.conf'


def show_on_startup() -> bool:
    if WELCOME_CONFIG.exists():
        for line in WELCOME_CONFIG.read_text(errors='replace').splitlines():
            if line.strip() == 'show_on_startup=false':
                return False
    return not SEEN_MARKER.exists()


def set_show_on_startup(enabled: bool):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    WELCOME_CONFIG.write_text(f'show_on_startup={str(enabled).lower()}\n')
    SEEN_MARKER.parent.mkdir(parents=True, exist_ok=True)
    if enabled:
        try:
            SEEN_MARKER.unlink()
        except FileNotFoundError:
            pass
    else:
        SEEN_MARKER.touch()


def sudo_prefix() -> list[str]:
    """This runs from a GUI session on an installed system, not a terminal
    with a real tty, so pkexec (its own native polkit auth dialog) is tried
    first; sudo is only usable here if the system has an askpass helper
    configured, which most installed systems won't."""
    if shutil.which('pkexec'):
        return ['pkexec']
    for sudo in ('/run/wrappers/bin/sudo', 'sudo'):
        if shutil.which(sudo):
            return [sudo, '-A', '--']
    return ['pkexec']


def read_local_setting(key: str) -> str:
    """Mirrors abora-welcome.sh/abora-config.sh's own sed-based reader so
    the GUI shows the exact same values the CLI tools do, without needing
    to shell out just to read a value."""
    if not CONFIG_PATH.exists():
        return ''
    pattern = re.compile(r'^\s*abora\.' + re.escape(key) + r'\s*=\s*"([^"]*)"', re.MULTILINE)
    match = pattern.search(CONFIG_PATH.read_text(errors='replace'))
    return match.group(1) if match else ''


def read_local_bool(key: str, default: bool = False) -> bool:
    if not CONFIG_PATH.exists():
        return default
    pattern = re.compile(r'^\s*abora\.' + re.escape(key) + r'\s*=\s*(true|false)', re.MULTILINE)
    match = pattern.search(CONFIG_PATH.read_text(errors='replace'))
    if not match:
        return default
    return match.group(1) == 'true'


def read_channel() -> str:
    if CHANNEL_FILE.exists():
        return CHANNEL_FILE.read_text().strip() or os.environ.get('ABORA_DEFAULT_CHANNEL', 'unstable')
    return os.environ.get('ABORA_DEFAULT_CHANNEL', 'unstable')


def flathub_configured() -> bool:
    if not shutil.which('flatpak'):
        return False
    try:
        out = subprocess.run(
            ['flatpak', 'remotes', '--system'],
            capture_output=True, text=True, timeout=5,
        ).stdout
        return any(line.split()[0] == 'flathub' for line in out.splitlines() if line.split())
    except Exception:
        return False


def find_terminal_launcher() -> list[str] | None:
    """Best-effort terminal discovery so quick-action buttons (Doctor,
    Recovery, ...) can open the existing TUI tools people already know,
    instead of reimplementing each one as a GUI dialog."""
    term = os.environ.get('TERMINAL')
    candidates = [term] if term else []
    candidates += ['konsole', 'ptyxis', 'gnome-terminal', 'kitty', 'foot', 'alacritty', 'xterm']
    for candidate in candidates:
        if candidate and shutil.which(candidate):
            if candidate in ('gnome-terminal', 'ptyxis'):
                return [candidate, '--']
            return [candidate, '-e']
    return None


def run_in_terminal(command: list[str]):
    launcher = find_terminal_launcher()
    if launcher is None:
        subprocess.Popen(command)
        return
    subprocess.Popen(launcher + command)


def logo_widget(size: int = 64) -> Gtk.Widget:
    if Path(LOGO_FILE).exists():
        img = Gtk.Image.new_from_file(LOGO_FILE)
        img.set_pixel_size(size)
        return img
    badge = Gtk.Label(label='A')
    badge.add_css_class('title-1')
    badge.set_size_request(size, size)
    return badge


class WelcomeWindow(Adw.ApplicationWindow):
    __gtype_name__ = 'AboraWelcomeWindow'

    def __init__(self, app: Adw.Application):
        super().__init__(application=app, title='Welcome to Abora OS',
                          default_width=560, default_height=680)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_LIGHT)
        self._update_available: str | None = None
        self._build_ui()

    # ── UI ────────────────────────────────────────────────────────────────
    def _tab_page(self) -> tuple[Gtk.Box, Adw.Clamp]:
        """A scrollable, clamped-width vertical box -- the same shell every
        tab page uses, so each tab only has to build its own content."""
        scroller = Gtk.ScrolledWindow(vexpand=True)
        page = Adw.Clamp(maximum_size=520)
        scroller.set_child(page)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18,
                      margin_top=24, margin_bottom=24, margin_start=12, margin_end=12)
        page.set_child(box)
        return box, scroller

    def _build_ui(self):
        toolbar = Adw.ToolbarView()
        self.set_content(toolbar)

        hb = Adw.HeaderBar()
        hb.pack_start(logo_widget(24))
        toolbar.add_top_bar(hb)

        self._stack = Adw.ViewStack()
        toolbar.set_content(self._stack)

        # A bottom tab bar (not the header bar) is the idiomatic libadwaita
        # pattern for a narrow single-window app like this -- it stays
        # usable at the window's default 560px width, where a header-bar
        # switcher would get cramped, and its left-to-right icon+label tabs
        # are the most approachable navigation for a first-run "welcome"
        # audience.
        switcher_bar = Adw.ViewSwitcherBar()
        switcher_bar.set_stack(self._stack)
        switcher_bar.set_reveal(True)
        toolbar.add_bottom_bar(switcher_bar)

        self._stack.add_titled_with_icon(self._build_home_tab(), 'home', 'Home', 'user-home-symbolic')
        self._stack.add_titled_with_icon(self._build_system_tab(), 'system', 'System', 'preferences-system-symbolic')

        self.connect('close-request', self._on_close)
        GLib.idle_add(self._check_for_updates)

    def _build_home_tab(self) -> Gtk.Widget:
        box, scroller = self._tab_page()

        header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, halign=Gtk.Align.CENTER)
        header.append(logo_widget(72))
        title = Gtk.Label(label='Welcome to Abora OS')
        title.add_css_class('title-1')
        header.append(title)
        subtitle = Gtk.Label(label='A few useful first steps.')
        subtitle.add_css_class('dim-label')
        header.append(subtitle)
        box.append(header)

        self._startup_switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self._startup_switch.set_active(show_on_startup())
        self._startup_switch.connect('notify::active', self._on_startup_toggled)
        startup_group = Adw.PreferencesGroup()
        box.append(startup_group)
        startup_row = Adw.ActionRow(title='Show on startup',
                                    subtitle='Open this welcome screen when you sign in')
        startup_row.add_suffix(self._startup_switch)
        startup_row.set_activatable_widget(self._startup_switch)
        startup_group.add(startup_row)

        # Updates card
        update_group = Adw.PreferencesGroup(title='Updates')
        box.append(update_group)
        self._update_row = Adw.ActionRow(title='Checking for updates…')
        self._update_spinner = Gtk.Spinner(spinning=True)
        self._update_row.add_suffix(self._update_spinner)
        update_group.add(self._update_row)

        button_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, halign=Gtk.Align.END)
        self._check_btn = Gtk.Button(label='Check Again')
        self._check_btn.connect('clicked', lambda *_: self._check_for_updates())
        self._update_btn = Gtk.Button(label='Update Now')
        self._update_btn.add_css_class('suggested-action')
        self._update_btn.set_sensitive(False)
        self._update_btn.connect('clicked', lambda *_: self._start_update())
        button_row.append(self._check_btn)
        button_row.append(self._update_btn)
        box.append(button_row)

        return scroller

    def _build_system_tab(self) -> Gtk.Widget:
        box, scroller = self._tab_page()

        gaming_enabled = read_local_bool('gaming.enable')
        status_group = Adw.PreferencesGroup(title='System')
        box.append(status_group)
        self._row_desktop  = Adw.ActionRow(title='Desktop', subtitle=read_local_setting('desktop') or 'unknown')
        self._row_wallpaper = Adw.ActionRow(title='Wallpaper', subtitle=read_local_setting('wallpaper') or 'unknown')
        self._row_gaming   = Adw.ActionRow(title='Gaming', subtitle='enabled' if gaming_enabled else 'off')
        self._row_channel  = Adw.ActionRow(title='Update channel', subtitle=read_channel())
        self._row_flathub  = Adw.ActionRow(title='Flathub', subtitle='configured' if flathub_configured() else 'not configured')
        for row in (self._row_desktop, self._row_wallpaper, self._row_gaming, self._row_channel, self._row_flathub):
            status_group.add(row)

        actions_group = Adw.PreferencesGroup(title='Quick Actions')
        box.append(actions_group)
        actions = [
            ('System Doctor', 'Check system health', ['abora', 'doctor']),
            ('App Manager', 'Install or remove applications', ['abora', 'apps']),
            ('Gaming Setup', 'Check or enable Steam and gaming helpers', ['abora', 'gaming', 'status']),
            ('First ANIX Snapshot', 'Save a restore point now', ['anix', 'save', 'anix: first Abora snapshot']),
            ('Switch Desktop', 'Change your desktop environment', ['abora', 'desktop', 'list']),
            ('Recovery Tools', 'Rollback and repair options', ['abora', 'recovery']),
        ]
        self._add_action_rows(actions_group, actions)

        # Abora Welcome tells you about your system in general; Abora Gaming
        # Welcome is its own separate app for games specifically (library,
        # Steam sign-in, installing a game) -- this is just a hand-off
        # button between the two, not a merge of the two experiences.
        if gaming_enabled:
            gaming_group = Adw.PreferencesGroup()
            box.append(gaming_group)
            gaming_row = Adw.ActionRow(
                title='Abora Gaming Welcome', subtitle='Your library, signing into Steam, and installing games',
                activatable=True)
            gaming_row.set_icon_name('input-gaming-symbolic')
            gaming_row.connect('activated', lambda *_: self._open_gaming_welcome())
            gaming_group.add(gaming_row)

        return scroller

    def _open_gaming_welcome(self):
        try:
            subprocess.Popen([GAMING_WELCOME_SCRIPT])
        except Exception:
            run_in_terminal(['abora', 'gaming', 'status'])

    def _add_action_rows(self, group: Adw.PreferencesGroup, actions: list[tuple[str, str, list[str]]]):
        for label, subtitle, command in actions:
            row = Adw.ActionRow(title=label, subtitle=subtitle, activatable=True)
            row.set_icon_name('go-next-symbolic')
            row.connect('activated', lambda _row, cmd=command: run_in_terminal(cmd))
            group.add(row)

    # ── Update checking ──────────────────────────────────────────────────
    def _check_for_updates(self):
        self._update_row.set_title('Checking for updates…')
        self._update_spinner.set_visible(True)
        self._update_spinner.start()
        self._check_btn.set_sensitive(False)
        self._update_btn.set_sensitive(False)
        threading.Thread(target=self._check_worker, daemon=True).start()

    def _check_worker(self):
        try:
            result = subprocess.run(
                [UPDATE_SCRIPT, '--check'],
                capture_output=True, text=True, timeout=30,
                env={**os.environ, 'ABORA_UPDATE_COMMAND': 'abora-update'},
            )
            available_ref = None
            for line in result.stdout.splitlines():
                if line.startswith('ABORA_UPDATE_AVAILABLE\t'):
                    parts = line.split('\t')
                    available_ref = parts[2] if len(parts) > 2 else None
            # Exit code 10 means "update available" (not a failure); 0 means
            # up to date. Anything else is a real check failure -- e.g. an
            # unresolvable channel -- and must not be reported as "up to
            # date" just because no ABORA_UPDATE_AVAILABLE line was printed.
            if result.returncode not in (0, 10):
                error = result.stderr.strip()[-800:] or f'abora-update exited with status {result.returncode}'
                GLib.idle_add(self._on_check_done, None, error)
                return
            GLib.idle_add(self._on_check_done, available_ref, None)
        except Exception as exc:
            GLib.idle_add(self._on_check_done, None, str(exc))

    def _on_check_done(self, available_ref: str | None, error: str | None):
        self._update_spinner.stop()
        self._update_spinner.set_visible(False)
        self._check_btn.set_sensitive(True)
        if error:
            self._update_row.set_title('Could not check for updates')
            self._update_row.set_subtitle(error)
        elif available_ref:
            self._update_available = available_ref
            self._update_row.set_title(f'Update available: {available_ref}')
            self._update_row.set_subtitle('Click "Update Now" to install it.')
            self._update_btn.set_sensitive(True)
        else:
            self._update_available = None
            self._update_row.set_title("You're up to date")
            self._update_row.set_subtitle('')
        return False

    def _start_update(self):
        self._update_btn.set_sensitive(False)
        self._check_btn.set_sensitive(False)
        self._update_row.set_title('Updating Abora OS…')
        self._update_row.set_subtitle('This can take a few minutes. Don\'t turn off your computer.')
        self._update_spinner.set_visible(True)
        self._update_spinner.start()
        threading.Thread(target=self._update_worker, daemon=True).start()

    def _update_worker(self):
        try:
            # pkexec/sudo don't reliably pass through the calling process's
            # environment, so anything abora-update.sh reads from the
            # environment has to ride inside the escalated command itself
            # (via `env`), not subprocess.run's own env= kwarg -- otherwise
            # a customized ABORA_SYSTEM_CONFIG would silently fall back to
            # the script's own default (/etc/nixos) once escalated.
            config_dir = os.environ.get('ABORA_SYSTEM_CONFIG', '/etc/nixos')
            command = sudo_prefix() + [
                'env', 'ABORA_UPDATE_COMMAND=abora-update', f'ABORA_SYSTEM_CONFIG={config_dir}',
                UPDATE_SCRIPT,
            ]
            proc = subprocess.run(command, capture_output=True, text=True, timeout=1800)
            GLib.idle_add(self._on_update_done, proc.returncode == 0, proc.stderr[-800:] if proc.returncode else '')
        except Exception as exc:
            GLib.idle_add(self._on_update_done, False, str(exc))

    def _on_update_done(self, ok: bool, message: str):
        self._update_spinner.stop()
        self._update_spinner.set_visible(False)
        self._check_btn.set_sensitive(True)
        if ok:
            self._update_row.set_title('Update complete')
            self._update_row.set_subtitle('Restart to finish applying the update.')
        else:
            self._update_row.set_title('Update failed')
            self._update_row.set_subtitle(message or 'See the terminal for details.')
            self._update_btn.set_sensitive(True)
        return False

    def _on_close(self, *_args):
        try:
            if not self._startup_switch.get_active():
                set_show_on_startup(False)
        except Exception:
            pass
        return False

    def _on_startup_toggled(self, switch: Gtk.Switch, *_args):
        try:
            set_show_on_startup(switch.get_active())
        except Exception:
            pass


class WelcomeApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id='org.aboraos.Welcome')

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = WelcomeWindow(self)
        win.present()


def main():
    app = WelcomeApp()
    app.run()


if __name__ == '__main__':
    main()
