#!/usr/bin/env python3
"""Abora Gaming Welcome — a separate first-steps app for games specifically:
your gaming platforms at a glance, signing into Steam, and installing a
platform to get a game running through. Abora Welcome (abora-welcome-gui.py)
covers the system in general; this app is deliberately its own window with
its own focus, not a tab bolted onto that one."""

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
    if os.environ.get('ABORA_LOGO'):
        return os.environ['ABORA_LOGO']
    for candidate in (
        '/etc/abora/Abora-LOGO.png',
        Path(__file__).resolve().parents[2] / 'assets' / 'Abora-LOGO.png',
        Path(__file__).resolve().parent.parent / 'assets' / 'Abora-LOGO.png',
    ):
        if Path(candidate).exists():
            return str(candidate)
    return '/etc/abora/Abora-LOGO.png'


def _resolve_catalog_path() -> str:
    if os.environ.get('ABORA_APP_CATALOG'):
        return os.environ['ABORA_APP_CATALOG']
    for candidate in (
        '/etc/abora/app-catalog.sh',
        Path(__file__).resolve().parent / 'abora-app-catalog.sh',
    ):
        if Path(candidate).exists():
            return str(candidate)
    return '/etc/abora/app-catalog.sh'


LOGO_FILE      = _resolve_logo_path()
CATALOG_FILE   = _resolve_catalog_path()
CONFIG_PATH    = Path(os.environ.get('ABORA_SYSTEM_CONFIG', '/etc/nixos')) / 'abora-local.nix'
APPS_LIST_FILE = Path(os.environ.get('ABORA_SYSTEM_CONFIG', '/etc/nixos')) / 'abora' / 'apps.list'
COMMAND_TIMEOUT_SECONDS = int(os.environ.get('ABORA_GAMING_WELCOME_TIMEOUT', '7200'))

# Catalog rows this app cares about, in the friendly order they should show
# up in -- Steam first since it's the sign-in-required launcher most people
# are here for. id must match abora-app-catalog.sh's id field exactly.
GAMING_PLATFORM_ORDER = ['steam', 'lutris', 'heroic', 'bottles', 'wine', 'winetricks', 'gamemode', 'mangohud']


def command_failure_message(proc: subprocess.CompletedProcess) -> str:
    output = '\n'.join(part for part in (proc.stdout, proc.stderr) if part)
    output = output.strip()
    if not output:
        return 'Failed — run abora gaming doctor or abora logs from a terminal for details.'
    if re.search(r'fetcher-cache.*sqlite|sqlite.*disk I/O|disk I/O error', output, re.IGNORECASE):
        return (
            'Nix reported a local fetch-cache disk I/O error. '
            'This is usually a damaged user Nix cache or low disk space, not a bad gaming app. '
            'Try: abora gaming repair-cache, then run abora gaming doctor.'
        )
    if re.search(r'no space left on device|ENOSPC', output, re.IGNORECASE):
        return (
            'The rebuild appears to have run out of disk space. '
            'Free space or run: sudo nix-collect-garbage -d'
        )
    return output[-700:]


def read_local_bool(key: str, default: bool = False) -> bool:
    if not CONFIG_PATH.exists():
        return default
    pattern = re.compile(r'^\s*abora\.' + re.escape(key) + r'\s*=\s*(true|false)', re.MULTILINE)
    match = pattern.search(CONFIG_PATH.read_text(errors='replace'))
    if not match:
        return default
    return match.group(1) == 'true'


def read_gaming_catalog() -> list[dict]:
    """Parses the 'id|name|package|category|description|favorite' catalog
    lines out of abora-app-catalog.sh (the same file abora-apps.sh reads)
    rather than keeping a second hardcoded copy of the Gaming category
    here -- one source of truth for what a gaming platform app actually is."""
    entries: dict[str, dict] = {}
    try:
        text = Path(CATALOG_FILE).read_text(errors='replace')
    except OSError:
        return []
    for line in text.splitlines():
        parts = line.split('|')
        if len(parts) < 6:
            continue
        app_id, name, _pkg, category, description, _favorite = parts[:6]
        if category != 'Gaming':
            continue
        entries[app_id] = {'id': app_id, 'name': name, 'description': description}
    ordered = [entries[i] for i in GAMING_PLATFORM_ORDER if i in entries]
    ordered += [e for i, e in entries.items() if i not in GAMING_PLATFORM_ORDER]
    return ordered


def read_installed_apps() -> set[str]:
    if not APPS_LIST_FILE.exists():
        return set()
    ids = set()
    for line in APPS_LIST_FILE.read_text(errors='replace').splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            ids.add(line)
    return ids


def sudo_prefix() -> list[str]:
    """Return a GUI-safe privilege command.

    Gaming Welcome is usually launched from a desktop session, not a
    terminal with a real tty. pkexec gives its own password dialog; sudo -A
    only works when an askpass helper is configured. If neither exists,
    surface a clear in-app error instead of launching sudo in a way that can
    only fail.
    """
    if shutil.which('pkexec'):
        return ['pkexec']
    if os.environ.get('SUDO_ASKPASS'):
        for sudo in ('/run/wrappers/bin/sudo', 'sudo'):
            if shutil.which(sudo):
                return [sudo, '-A', '--']
    raise RuntimeError(
        'No graphical privilege helper found. Install pkexec/polkit or set SUDO_ASKPASS, '
        'then run abora gaming install from a terminal.'
    )


def sudo_prefix_or_status(window: 'GamingWelcomeWindow') -> list[str] | None:
    try:
        return sudo_prefix()
    except RuntimeError as exc:
        window._show_status(str(exc), error=True)
        return None


def command_env() -> list[str]:
    return ['env', f'ABORA_SYSTEM_CONFIG={os.environ.get("ABORA_SYSTEM_CONFIG", "/etc/nixos")}']


def command_path(tool: str) -> str:
    override = os.environ.get(f'ABORA_{tool.upper().replace("-", "_")}_SCRIPT')
    if override:
        return override
    resolved = shutil.which(tool)
    if resolved:
        return resolved
    installed_scripts = {
        'abora': '/etc/abora/abora.sh',
        'abora-update': '/etc/abora/update.sh',
    }
    for candidate in (f'/run/current-system/sw/bin/{tool}', installed_scripts.get(tool, '')):
        if not candidate:
            continue
        if Path(candidate).exists():
            return candidate
    return tool


def logo_widget(size: int = 64) -> Gtk.Widget:
    if Path(LOGO_FILE).exists():
        img = Gtk.Image.new_from_file(LOGO_FILE)
        img.set_pixel_size(size)
        return img
    badge = Gtk.Label(label='A')
    badge.add_css_class('title-1')
    badge.set_size_request(size, size)
    return badge


class GamingWelcomeWindow(Adw.ApplicationWindow):
    __gtype_name__ = 'AboraGamingWelcomeWindow'

    def __init__(self, app: Adw.Application):
        super().__init__(application=app, title='Abora Gaming Welcome',
                          default_width=520, default_height=640)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_LIGHT)
        self._platform_rows: dict[str, Adw.ActionRow] = {}
        self._platform_buttons: dict[str, Gtk.Button] = {}
        self._action_buttons: list[Gtk.Button] = []
        self._build_ui()

    def _build_ui(self):
        toolbar = Adw.ToolbarView()
        self.set_content(toolbar)

        hb = Adw.HeaderBar()
        hb.pack_start(logo_widget(24))
        toolbar.add_top_bar(hb)

        scroller = Gtk.ScrolledWindow(vexpand=True)
        toolbar.set_content(scroller)
        page = Adw.Clamp(maximum_size=480)
        scroller.set_child(page)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18,
                      margin_top=24, margin_bottom=24, margin_start=12, margin_end=12)
        page.set_child(box)

        header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, halign=Gtk.Align.CENTER)
        icon = Gtk.Image.new_from_icon_name('input-gaming-symbolic')
        icon.set_pixel_size(64)
        header.append(icon)
        title = Gtk.Label(label='Abora Gaming')
        title.add_css_class('title-1')
        header.append(title)
        subtitle = Gtk.Label(label='Get a platform ready, sign in, and start installing games.')
        subtitle.add_css_class('dim-label')
        subtitle.set_wrap(True)
        subtitle.set_justify(Gtk.Justification.CENTER)
        header.append(subtitle)
        box.append(header)

        if not read_local_bool('gaming.enable'):
            notice_group = Adw.PreferencesGroup()
            box.append(notice_group)
            notice = Adw.ActionRow(
                title='Abora Gaming is off',
                subtitle='Enabling it installs 32-bit graphics support, GameMode, and MangoHud alongside your platforms.')
            enable_btn = Gtk.Button(label='Turn On', valign=Gtk.Align.CENTER)
            enable_btn.add_css_class('suggested-action')
            enable_btn.connect('clicked', lambda *_: self._enable_gaming())
            notice.add_suffix(enable_btn)
            notice_group.add(notice)
            self._action_buttons.append(enable_btn)

        # Sign-in card — Steam is the one platform that gates everything
        # else behind an account, so it gets its own prominent action
        # instead of blending into the platform list below.
        signin_group = Adw.PreferencesGroup(title='Sign In')
        box.append(signin_group)
        self._signin_row = Adw.ActionRow(title='Steam')
        self._signin_button = Gtk.Button(valign=Gtk.Align.CENTER)
        self._signin_button.add_css_class('suggested-action')
        self._signin_row.add_suffix(self._signin_button)
        signin_group.add(self._signin_row)
        self._action_buttons.append(self._signin_button)
        self._refresh_signin_row()

        # Platforms card
        platforms_group = Adw.PreferencesGroup(
            title='Platforms', description='Install a launcher, then browse and install games from inside it.')
        box.append(platforms_group)
        for entry in read_gaming_catalog():
            row = Adw.ActionRow(title=entry['name'], subtitle=entry['description'])
            row.set_subtitle_lines(2)
            button = Gtk.Button(valign=Gtk.Align.CENTER)
            button.connect('clicked', lambda _btn, app_id=entry['id']: self._install(app_id))
            row.add_suffix(button)
            platforms_group.add(row)
            self._platform_rows[entry['id']] = row
            self._platform_buttons[entry['id']] = button
            self._action_buttons.append(button)
            self._set_platform_button_state(entry['id'], button)

        tools_group = Adw.PreferencesGroup(
            title='Troubleshooting',
            description='Quick checks for Steam, Vulkan, disk space, and local Nix cache problems.')
        box.append(tools_group)
        doctor_row = Adw.ActionRow(
            title='Gaming Doctor',
            subtitle='Check installed tools, enabled options, GPU access, Vulkan tools, and free space.')
        doctor_btn = Gtk.Button(label='Run', valign=Gtk.Align.CENTER)
        doctor_btn.connect('clicked', lambda *_: self._run_local_tool('Running Gaming Doctor…', ['doctor']))
        doctor_row.add_suffix(doctor_btn)
        tools_group.add(doctor_row)
        self._action_buttons.append(doctor_btn)

        cache_row = Adw.ActionRow(
            title='Repair Nix Cache',
            subtitle='Fix local fetch-cache SQLite errors that can break Steam or launcher installs.')
        cache_btn = Gtk.Button(label='Repair', valign=Gtk.Align.CENTER)
        cache_btn.connect('clicked', lambda *_: self._run_local_tool('Repairing local Nix cache…', ['repair-cache']))
        cache_row.add_suffix(cache_btn)
        tools_group.add(cache_row)
        self._action_buttons.append(cache_btn)

        self._status_group = Adw.PreferencesGroup()
        box.append(self._status_group)
        self._status_row = Adw.ActionRow()
        self._status_spinner = Gtk.Spinner()
        self._status_row.add_prefix(self._status_spinner)
        self._status_group.add(self._status_row)
        self._status_group.set_visible(False)

    # ── Steam sign-in ────────────────────────────────────────────────────
    def _steam_installed(self) -> bool:
        return 'steam' in read_installed_apps() or shutil.which('steam') is not None

    def _refresh_signin_row(self):
        if self._steam_installed():
            self._signin_row.set_subtitle('Installed — open Steam and sign in with your account')
            self._signin_button.set_label('Open Steam')
            self._set_button_handler(self._signin_button, self._launch_steam)
        else:
            self._signin_row.set_subtitle('Not installed yet')
            self._signin_button.set_label('Install Steam')
            self._set_button_handler(self._signin_button, lambda: self._install('steam'))

    def _set_button_handler(self, button: Gtk.Button, handler):
        # GTK doesn't offer a clean "replace the clicked handler" call, and
        # this button's action changes at runtime (install -> open once
        # installed), so track+disconnect the previous handler by id.
        existing = getattr(button, '_handler_id', None)
        if existing is not None:
            button.disconnect(existing)
        button._handler_id = button.connect('clicked', lambda *_: handler())

    def _launch_steam(self):
        try:
            subprocess.Popen(['steam'])
        except Exception as exc:
            self._show_status(f'Could not launch Steam: {exc}', error=True)

    # ── Enable gaming / install a platform ──────────────────────────────
    def _enable_gaming(self):
        # `abora gaming enable` only writes abora-local.nix -- it doesn't
        # rebuild (see its own --help: "After changing settings, run: sudo
        # abora update"). Chaining the update here makes "Turn On" a single
        # action instead of leaving the user to run a second command.
        prefix = sudo_prefix_or_status(self)
        if prefix is None:
            return
        self._run_background(
            'Turning on Abora Gaming (this can take a few minutes)…',
            prefix + command_env() + [
                'bash', '-c',
                f'{command_path("abora")} gaming enable && exec {command_path("abora-update")}'
            ],
            on_done=None,
        )

    def _install(self, app_id: str):
        prefix = sudo_prefix_or_status(self)
        if prefix is None:
            return
        self._run_background(
            f'Installing {app_id}…',
            prefix + command_env() + [command_path('abora'), 'gaming', 'install', app_id],
            on_done=lambda ok: self._on_install_done(app_id, ok),
        )

    def _run_local_tool(self, label: str, args: list[str]):
        self._run_background(
            label,
            command_env() + [command_path('abora'), 'gaming'] + args,
            on_done=None,
        )

    def _on_install_done(self, app_id: str, ok: bool):
        if not ok:
            return
        self._refresh_signin_row()
        if app_id in self._platform_rows:
            row = self._platform_rows[app_id]
            button = self._platform_buttons.get(app_id)
            if button is not None:
                self._set_platform_button_state(app_id, button)

    def _set_platform_button_state(self, app_id: str, button: Gtk.Button):
        # Steam gets the same shutil.which() fallback as the Sign In card
        # (_steam_installed()) -- otherwise a Steam installed outside Abora's
        # own app tracking (a manual package, a pre-existing install) shows
        # "Installed" up in Sign In but a live, clickable "Install" button
        # here for the same app.
        installed = app_id in read_installed_apps()
        if app_id == 'steam':
            installed = installed or self._steam_installed()
        if installed:
            button.set_label('Installed')
            button.set_sensitive(False)
        else:
            button.set_label('Install')
            button.set_sensitive(True)

    def _refresh_buttons(self):
        self._refresh_signin_row()
        for app_id, button in self._platform_buttons.items():
            self._set_platform_button_state(app_id, button)

    def _set_busy(self, busy: bool):
        for button in self._action_buttons:
            button.set_sensitive(not busy)

    # ── Background command runner with a shared status row ─────────────
    def _run_background(self, label: str, command: list[str], on_done):
        self._set_busy(True)
        self._status_group.set_visible(True)
        self._status_row.set_title(label)
        self._status_spinner.set_visible(True)
        self._status_spinner.start()

        def worker():
            try:
                proc = subprocess.run(command, capture_output=True, text=True, timeout=COMMAND_TIMEOUT_SECONDS)
                ok = proc.returncode == 0
                message = '' if ok else command_failure_message(proc)
            except subprocess.TimeoutExpired:
                ok = False
                message = (
                    f'This action did not finish after {COMMAND_TIMEOUT_SECONDS // 60} minutes. '
                    'The rebuild may still need more time on a slow connection or cold cache. '
                    'Try again from a terminal so you can watch progress: abora gaming doctor'
                )
            except Exception as exc:
                ok, message = False, str(exc)
            GLib.idle_add(self._on_background_done, ok, message, on_done)

        threading.Thread(target=worker, daemon=True).start()

    def _on_background_done(self, ok: bool, message: str, on_done):
        self._status_spinner.stop()
        self._status_spinner.set_visible(False)
        if ok:
            self._status_row.set_title('Done')
            self._status_row.set_subtitle('')
        else:
            self._status_row.set_title('Something went wrong')
            self._status_row.set_subtitle(message)
        if on_done:
            on_done(ok)
        self._refresh_buttons()
        self._set_busy(False)
        return False

    def _show_status(self, message: str, error: bool = False):
        self._status_group.set_visible(True)
        self._status_row.set_title('Error' if error else message)
        if error:
            self._status_row.set_subtitle(message)


class GamingWelcomeApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id='org.aboraos.GamingWelcome')

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = GamingWelcomeWindow(self)
        win.present()


def main():
    app = GamingWelcomeApp()
    app.run()


if __name__ == '__main__':
    main()
