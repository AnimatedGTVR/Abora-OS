#!/usr/bin/env python3
"""Abora Config Editor — GUI front-end for `abora config`.

This is deliberately a thin GUI over the existing abora-config.sh CLI: all
validation (hostname format, valid desktops/GPUs, wallpaper names) and the
actual file writes stay in one place (the shell script) so the GUI can
never drift out of sync with what the CLI considers valid. The GUI only
reads abora-local.nix directly (for display) and shells out to
`abora config set`/`apply` (via pkexec) to make changes.
"""

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
    run via `make test-config` from the repo root) before giving up."""
    if os.environ.get('ABORA_LOGO'):
        return os.environ['ABORA_LOGO']
    for candidate in (
        '/etc/abora/Abora-LOGO.png',
        Path(__file__).resolve().parent.parent / 'assets' / 'Abora-LOGO.png',
    ):
        if Path(candidate).exists():
            return str(candidate)
    return '/etc/abora/Abora-LOGO.png'


LOGO_FILE     = _resolve_logo_path()
CONFIG_SCRIPT = os.environ.get('ABORA_CONFIG_SCRIPT', '/etc/abora/config.sh')
CONFIG_DIR    = Path(os.environ.get('ABORA_SYSTEM_CONFIG', '/etc/nixos'))
LOCAL_MODULE  = CONFIG_DIR / 'abora-local.nix'
WALLPAPER_DIR = Path(os.environ.get('ABORA_WALLPAPER_DIR', '/etc/abora/wallpapers'))
ZONE_DIR      = Path('/usr/share/zoneinfo')

VALID_DESKTOPS = [
    'none', 'gnome', 'plasma', 'hyprland', 'sway', 'xfce', 'cinnamon', 'mate',
    'budgie', 'lxqt', 'pantheon', 'i3', 'awesome', 'openbox', 'niri', 'river',
    'qtile', 'bspwm', 'fluxbox', 'icewm', 'herbstluftwm', 'cosmic', 'mangowm',
]
VALID_GPUS = ['auto', 'nouveau', 'nvidia', 'nvidia-open', 'amdgpu', 'intel', 'none']
DEFAULT_WALLPAPERS = [
    'alpine-glacier.jpg', 'tannheimer-mountains.jpg', 'titlis-alps.jpg', 'aurora-lofoten.jpg',
]
ANSI_RE = re.compile(r'\x1b\[[0-9;?]*[ -/]*[@-~]')

# Only these top-level zoneinfo directories are real continents/areas; the
# rest (Brazil, Canada, US, posix, right, Factory, ...) are legacy aliases
# that duplicate zones already reachable under their real continent.
ZONE_TOP_LEVEL = {'Africa', 'America', 'Antarctica', 'Arctic', 'Asia', 'Atlantic',
                  'Australia', 'Europe', 'Indian', 'Pacific'}


def sudo_prefix() -> list[str]:
    if shutil.which('pkexec'):
        return ['pkexec']
    for sudo in ('/run/wrappers/bin/sudo', 'sudo'):
        if shutil.which(sudo):
            return [sudo, '-A', '--']
    return ['pkexec']


def read_setting(key: str) -> str:
    if not LOCAL_MODULE.exists():
        return ''
    pattern = re.compile(r'^\s*abora\.' + re.escape(key) + r'\s*=\s*"([^"]*)"', re.MULTILINE)
    match = pattern.search(LOCAL_MODULE.read_text(errors='replace'))
    return match.group(1) if match else ''


def read_bool_setting(key: str, default: bool = False) -> bool:
    if not LOCAL_MODULE.exists():
        return default
    pattern = re.compile(r'^\s*abora\.' + re.escape(key) + r'\s*=\s*(true|false)', re.MULTILINE)
    match = pattern.search(LOCAL_MODULE.read_text(errors='replace'))
    if not match:
        return default
    return match.group(1) == 'true'


def clean_cli_message(message: str) -> str:
    return ANSI_RE.sub('', message).strip()


def list_timezones() -> list[str]:
    """Every real IANA zone on this system, e.g. America/Indiana/Knox --
    a hand-picked list would always miss zones like Indiana's, which has
    eight distinct real timezones within the same state."""
    zones: list[str] = []
    if not ZONE_DIR.exists():
        return ['UTC']
    for top in sorted(ZONE_DIR.iterdir()):
        if top.name not in ZONE_TOP_LEVEL:
            continue
        for path in sorted(top.rglob('*')):
            if path.is_file():
                zones.append(str(path.relative_to(ZONE_DIR)))
    zones.append('UTC')
    return zones


def list_wallpapers() -> list[str]:
    if WALLPAPER_DIR.is_dir():
        names = sorted(p.name for p in WALLPAPER_DIR.iterdir() if p.is_file())
        if names:
            return names
    return DEFAULT_WALLPAPERS


def logo_widget(size: int = 64) -> Gtk.Widget:
    if Path(LOGO_FILE).exists():
        img = Gtk.Image.new_from_file(LOGO_FILE)
        img.set_pixel_size(size)
        return img
    badge = Gtk.Label(label='A')
    badge.add_css_class('title-1')
    badge.set_size_request(size, size)
    return badge


class ConfigWindow(Adw.ApplicationWindow):
    __gtype_name__ = 'AboraConfigWindow'

    def __init__(self, app: Adw.Application):
        super().__init__(application=app, title='Abora System Settings',
                          default_width=560, default_height=640)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_LIGHT)
        self._original: dict[str, str] = {}
        self._build_ui()

    def _build_ui(self):
        toolbar = Adw.ToolbarView()
        self.set_content(toolbar)

        hb = Adw.HeaderBar()
        hb.pack_start(logo_widget(24))
        toolbar.add_top_bar(hb)
        self._apply_btn = Gtk.Button(label='Apply')
        self._apply_btn.add_css_class('suggested-action')
        self._apply_btn.set_sensitive(False)
        self._apply_btn.connect('clicked', lambda *_: self._apply())
        hb.pack_end(self._apply_btn)

        scroller = Gtk.ScrolledWindow(vexpand=True)
        toolbar.set_content(scroller)
        clamp = Adw.Clamp(maximum_size=520)
        scroller.set_child(clamp)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18,
                      margin_top=24, margin_bottom=24, margin_start=12, margin_end=12)
        clamp.set_child(box)

        header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, halign=Gtk.Align.CENTER)
        header.append(logo_widget(56))
        title = Gtk.Label(label='System Settings')
        title.add_css_class('title-1')
        header.append(title)
        box.append(header)

        if not LOCAL_MODULE.exists():
            note = Adw.StatusPage(
                title='No Abora configuration found',
                description=f'{LOCAL_MODULE} was not found. This only works on an installed Abora system.',
            )
            box.append(note)
            self._status_row = None
            return

        general = Adw.PreferencesGroup(title='General')
        box.append(general)
        self._hostname_row = Adw.EntryRow(title='Hostname')
        self._hostname_row.set_text(read_setting('hostname'))
        self._hostname_row.connect('notify::text', self._on_changed)
        general.add(self._hostname_row)

        self._timezone_row = Adw.ComboRow(title='Timezone')
        zones = list_timezones()
        self._timezone_model = Gtk.StringList.new(zones)
        self._timezone_row.set_model(self._timezone_model)
        self._timezone_row.set_enable_search(True)
        current_tz = read_setting('timezone') or 'UTC'
        if current_tz in zones:
            self._timezone_row.set_selected(zones.index(current_tz))
        self._timezone_row.connect('notify::selected', self._on_changed)
        general.add(self._timezone_row)

        self._kb_console_row = Adw.EntryRow(title='Console keymap')
        self._kb_console_row.set_text(read_setting('keyboard.console'))
        self._kb_console_row.connect('notify::text', self._on_changed)
        general.add(self._kb_console_row)

        self._kb_xkb_row = Adw.EntryRow(title='Keyboard layout (graphical)')
        self._kb_xkb_row.set_text(read_setting('keyboard.xkb'))
        self._kb_xkb_row.connect('notify::text', self._on_changed)
        general.add(self._kb_xkb_row)

        desktop_group = Adw.PreferencesGroup(title='Desktop')
        box.append(desktop_group)
        self._desktop_row = Adw.ComboRow(title='Desktop environment')
        self._desktop_model = Gtk.StringList.new(VALID_DESKTOPS)
        self._desktop_row.set_model(self._desktop_model)
        current_desktop = read_setting('desktop')
        if current_desktop in VALID_DESKTOPS:
            self._desktop_row.set_selected(VALID_DESKTOPS.index(current_desktop))
        self._desktop_row.connect('notify::selected', self._on_changed)
        desktop_group.add(self._desktop_row)

        self._wallpaper_row = Adw.ComboRow(title='Wallpaper')
        wallpapers = list_wallpapers()
        self._wallpaper_model = Gtk.StringList.new(wallpapers)
        self._wallpaper_row.set_model(self._wallpaper_model)
        current_wallpaper = read_setting('wallpaper')
        if current_wallpaper in wallpapers:
            self._wallpaper_row.set_selected(wallpapers.index(current_wallpaper))
        self._wallpaper_row.connect('notify::selected', self._on_changed)
        desktop_group.add(self._wallpaper_row)

        hw_group = Adw.PreferencesGroup(title='Hardware')
        box.append(hw_group)
        self._gpu_row = Adw.ComboRow(title='GPU driver')
        self._gpu_model = Gtk.StringList.new(VALID_GPUS)
        self._gpu_row.set_model(self._gpu_model)
        current_gpu = read_setting('gpu') or 'auto'
        if current_gpu in VALID_GPUS:
            self._gpu_row.set_selected(VALID_GPUS.index(current_gpu))
        self._gpu_row.connect('notify::selected', self._on_changed)
        hw_group.add(self._gpu_row)

        gaming_group = Adw.PreferencesGroup(title='Gaming')
        box.append(gaming_group)
        self._gaming_row = Adw.SwitchRow(title='Abora Gaming')
        self._gaming_row.set_subtitle('Steam, 32-bit graphics, GameMode, MangoHud, and launchers')
        self._gaming_row.set_active(read_bool_setting('gaming.enable', False))
        self._gaming_row.connect('notify::active', self._on_changed)
        gaming_group.add(self._gaming_row)

        self._gaming_big_picture_row = Adw.SwitchRow(title='Steam Big Picture launcher')
        self._gaming_big_picture_row.set_active(read_bool_setting('gaming.bigPictureShortcut', True))
        self._gaming_big_picture_row.connect('notify::active', self._on_changed)
        gaming_group.add(self._gaming_big_picture_row)

        self._gaming_gamescope_row = Adw.SwitchRow(title='Gamescope console session')
        self._gaming_gamescope_row.set_subtitle('Advanced living-room style Steam session')
        self._gaming_gamescope_row.set_active(read_bool_setting('gaming.gamescopeSession', True))
        self._gaming_gamescope_row.connect('notify::active', self._on_changed)
        gaming_group.add(self._gaming_gamescope_row)

        self._gaming_vulkan_row = Adw.SwitchRow(title='Vulkan tools')
        self._gaming_vulkan_row.set_subtitle('Install vulkaninfo for graphics readiness checks')
        self._gaming_vulkan_row.set_active(read_bool_setting('gaming.vulkanTools', True))
        self._gaming_vulkan_row.connect('notify::active', self._on_changed)
        gaming_group.add(self._gaming_vulkan_row)

        self._gaming_autostart_row = Adw.SwitchRow(title='Start Big Picture on login')
        self._gaming_autostart_row.set_subtitle('Best for TV/controller systems, noisy for laptops')
        self._gaming_autostart_row.set_active(read_bool_setting('gaming.bigPictureAutostart', False))
        self._gaming_autostart_row.connect('notify::active', self._on_changed)
        gaming_group.add(self._gaming_autostart_row)

        self._status_group = Adw.PreferencesGroup()
        box.append(self._status_group)
        self._status_row = Adw.ActionRow(title='No pending changes')
        self._status_group.add(self._status_row)

        self._original = self._current_values()

    # ── Change tracking ───────────────────────────────────────────────────
    def _current_values(self) -> dict[str, str]:
        zones = [self._timezone_model.get_string(i) for i in range(self._timezone_model.get_n_items())]
        desktops = VALID_DESKTOPS
        wallpapers = [self._wallpaper_model.get_string(i) for i in range(self._wallpaper_model.get_n_items())]
        gpus = VALID_GPUS
        return {
            'hostname': self._hostname_row.get_text(),
            'timezone': zones[self._timezone_row.get_selected()] if zones else 'UTC',
            'keyboard.console': self._kb_console_row.get_text(),
            'keyboard.xkb': self._kb_xkb_row.get_text(),
            'desktop': desktops[self._desktop_row.get_selected()],
            'wallpaper': wallpapers[self._wallpaper_row.get_selected()] if wallpapers else '',
            'gpu': gpus[self._gpu_row.get_selected()],
            'gaming': str(self._gaming_row.get_active()).lower(),
            'gaming.big-picture': str(self._gaming_big_picture_row.get_active()).lower(),
            'gaming.gamescope': str(self._gaming_gamescope_row.get_active()).lower(),
            'gaming.vulkan': str(self._gaming_vulkan_row.get_active()).lower(),
            'gaming.autostart': str(self._gaming_autostart_row.get_active()).lower(),
        }

    def _on_changed(self, *_args):
        if self._status_row is None:
            return
        current = self._current_values()
        changed = [key for key, value in current.items() if self._original.get(key, '') != value]
        if changed:
            self._status_row.set_title(f'{len(changed)} pending change(s)')
            self._apply_btn.set_sensitive(True)
        else:
            self._status_row.set_title('No pending changes')
            self._apply_btn.set_sensitive(False)

    # ── Apply ─────────────────────────────────────────────────────────────
    def _apply(self):
        current = self._current_values()
        changed = {key: value for key, value in current.items()
                   if self._original.get(key, '') != value}
        if not changed:
            return
        self._apply_btn.set_sensitive(False)
        self._status_row.set_title('Applying changes…')
        threading.Thread(target=self._apply_worker, args=(changed,), daemon=True).start()

    def _apply_worker(self, changed: dict[str, str]):
        # pkexec/sudo don't reliably pass through the calling process's
        # environment, so ABORA_SYSTEM_CONFIG has to ride inside the
        # escalated command itself (via `env`) -- otherwise abora-config.sh
        # would silently fall back to its own default (/etc/nixos) instead
        # of whatever config dir this GUI was actually pointed at (e.g. a
        # throwaway test fixture), which could mean writing to the real
        # system by accident during testing.
        prefix = sudo_prefix() + ['env', f'ABORA_SYSTEM_CONFIG={CONFIG_DIR}']
        for key, value in changed.items():
            proc = subprocess.run(
                prefix + [CONFIG_SCRIPT, 'set', key, value],
                capture_output=True, text=True, timeout=30,
            )
            if proc.returncode != 0:
                GLib.idle_add(self._on_apply_done, False, f'Setting {key}: {clean_cli_message(proc.stderr or proc.stdout)}')
                return
        proc = subprocess.run(prefix + [CONFIG_SCRIPT, 'apply'], capture_output=True, text=True, timeout=1800)
        if proc.returncode != 0:
            GLib.idle_add(self._on_apply_done, False, clean_cli_message(proc.stderr)[-800:] or 'Rebuild failed.')
            return
        GLib.idle_add(self._on_apply_done, True, '')

    def _on_apply_done(self, ok: bool, message: str):
        if ok:
            self._original = self._current_values()
            self._status_row.set_title('Applied. Changes are now active.')
        else:
            self._status_row.set_title('Apply failed')
            self._status_row.set_subtitle(message)
            self._apply_btn.set_sensitive(True)
        return False


class ConfigApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id='org.aboraos.ConfigEditor')

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = ConfigWindow(self)
        win.present()


def main():
    app = ConfigApp()
    app.run()


if __name__ == '__main__':
    main()
