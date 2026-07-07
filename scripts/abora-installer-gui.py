#!/usr/bin/env python3
"""Abora OS GUI Installer — DENALI 3.14"""

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('Gdk', '4.0')
from gi.repository import Gtk, Adw, GLib, Gio, Gdk
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

# ── Runtime paths ──────────────────────────────────────────────────────────────
INSTALLER_BIN  = os.environ.get('ABORA_INSTALLER', '/etc/abora/installer.sh')
LOG_FILE       = '/tmp/abora-gui-installer.log'
VERSION        = os.environ.get('ABORA_VERSION', 'DENALI 3.14')

# ── Desktop choices ────────────────────────────────────────────────────────────
DESKTOPS = [
    ('cosmic',    'COSMIC',      'Modern Wayland DE by System76',      '🪐'),
    ('mangowm',   'MangoWM',     "Abora's own tiling compositor",      '🍋'),
    ('gnome',     'GNOME',       'Clean and powerful desktop',          '🎯'),
    ('plasma',    'KDE Plasma',  'Full-featured Qt desktop',            '🔷'),
    ('hyprland',  'Hyprland',    'Dynamic Wayland compositor',          '🌊'),
    ('sway',      'Sway',        'i3-compatible Wayland WM',            '💨'),
    ('xfce',      'XFCE',        'Lightweight and fast',                '🖥'),
    ('cinnamon',  'Cinnamon',    'Traditional Linux desktop',           '🍂'),
    ('mate',      'MATE',        'Classic GNOME 2 desktop',             '🧩'),
    ('budgie',    'Budgie',      'Modern and elegant',                  '🌸'),
    ('pantheon',  'Pantheon',    'elementary OS desktop',               '🔮'),
    ('lxqt',      'LXQt',        'Lightweight Qt desktop',              '⚡'),
    ('niri',      'Niri',        'Scrollable Wayland compositor',       '〰'),
    ('i3',        'i3',          'Classic tiling WM (X11)',             '📐'),
    ('awesome',   'AwesomeWM',   'Lua-scripted WM',                    '⭐'),
    ('openbox',   'Openbox',     'Minimalist stacking WM',              '📦'),
    ('none',      'No Desktop',  'CLI / server only',                   '💻'),
]

DESKTOP_LABELS = {d[0]: d[1] for d in DESKTOPS}

APP_BUNDLES = [
    ('favorites', 'Fan Favorites',  'Everyday apps: browser, office, media'),
    ('creative',  'Creative Suite', 'Design, photo, and video tools'),
    ('developer', 'Developer Kit',  'IDEs, terminal tools, language runtimes'),
    ('minimal',   'Minimal',        'Base system only — add apps yourself'),
]

LOCALES = [
    ('en_US.UTF-8', 'English (United States)'),
    ('en_GB.UTF-8', 'English (United Kingdom)'),
    ('de_DE.UTF-8', 'German (Deutschland)'),
    ('fr_FR.UTF-8', 'French (France)'),
    ('es_ES.UTF-8', 'Spanish (España)'),
    ('pt_BR.UTF-8', 'Portuguese (Brasil)'),
    ('ja_JP.UTF-8', 'Japanese (日本語)'),
    ('zh_CN.UTF-8', 'Chinese Simplified (中文)'),
    ('ko_KR.UTF-8', 'Korean (한국어)'),
    ('ru_RU.UTF-8', 'Russian (Русский)'),
    ('it_IT.UTF-8', 'Italian (Italiano)'),
    ('nl_NL.UTF-8', 'Dutch (Nederlands)'),
    ('pl_PL.UTF-8', 'Polish (Polski)'),
    ('sv_SE.UTF-8', 'Swedish (Svenska)'),
    ('tr_TR.UTF-8', 'Turkish (Türkçe)'),
    ('ar_SA.UTF-8', 'Arabic (العربية)'),
    ('he_IL.UTF-8', 'Hebrew (עברית)'),
    ('vi_VN.UTF-8', 'Vietnamese (Tiếng Việt)'),
]

KEYBOARDS = [
    ('us',  'US English'),
    ('gb',  'UK English'),
    ('de',  'German'),
    ('fr',  'French'),
    ('es',  'Spanish'),
    ('pt',  'Portuguese'),
    ('it',  'Italian'),
    ('nl',  'Dutch'),
    ('pl',  'Polish'),
    ('se',  'Swedish'),
    ('ru',  'Russian'),
    ('jp',  'Japanese'),
    ('cn',  'Chinese'),
    ('kr',  'Korean'),
    ('tr',  'Turkish'),
    ('br',  'Brazilian Portuguese'),
]

TIMEZONES = [
    ('UTC',                 'UTC (Coordinated Universal Time)'),
    ('America/New_York',    'Eastern — New York, Toronto'),
    ('America/Chicago',     'Central — Chicago, Mexico City'),
    ('America/Denver',      'Mountain — Denver, Phoenix'),
    ('America/Los_Angeles', 'Pacific — Los Angeles, Vancouver'),
    ('America/Anchorage',   'Alaska — Anchorage'),
    ('Pacific/Honolulu',    'Hawaii — Honolulu'),
    ('America/Sao_Paulo',   'South America — São Paulo'),
    ('America/Buenos_Aires','South America — Buenos Aires'),
    ('America/Bogota',      'South America — Bogotá'),
    ('Europe/London',       'Europe — London (GMT/BST)'),
    ('Europe/Paris',        'Europe — Paris, Berlin, Rome'),
    ('Europe/Madrid',       'Europe — Madrid, Amsterdam'),
    ('Europe/Warsaw',       'Europe — Warsaw, Prague'),
    ('Europe/Stockholm',    'Europe — Stockholm, Oslo, Helsinki'),
    ('Europe/Moscow',       'Europe — Moscow'),
    ('Europe/Istanbul',     'Europe/Asia — Istanbul'),
    ('Asia/Dubai',          'Gulf — Dubai, Abu Dhabi'),
    ('Asia/Kolkata',        'South Asia — India (IST)'),
    ('Asia/Dhaka',          'South Asia — Bangladesh'),
    ('Asia/Bangkok',        'Southeast Asia — Bangkok'),
    ('Asia/Singapore',      'Southeast Asia — Singapore'),
    ('Asia/Shanghai',       'East Asia — China (CST)'),
    ('Asia/Tokyo',          'East Asia — Japan (JST)'),
    ('Asia/Seoul',          'East Asia — South Korea'),
    ('Asia/Jakarta',        'Southeast Asia — Jakarta'),
    ('Africa/Cairo',        'Africa — Cairo, Egypt'),
    ('Africa/Lagos',        'Africa — Lagos, Nigeria'),
    ('Africa/Johannesburg', 'Africa — Johannesburg'),
    ('Africa/Nairobi',      'Africa — Nairobi'),
    ('Australia/Sydney',    'Australia — Sydney, Melbourne'),
    ('Australia/Perth',     'Australia — Perth'),
    ('Pacific/Auckland',    'Pacific — New Zealand'),
]

WALLPAPERS = [
    ('abora-dark.svg',         'Abora Dark'),
    ('abora-light.svg',        'Abora Light'),
    ('Daytime-MNT.jpg',        'Mountain — Day'),
    ('NightTime-MNT.png',      'Mountain — Night'),
    ('oceandusk.png',          'Ocean Dusk'),
    ('bluehorizon.png',        'Blue Horizon'),
    ('astronautwallpaper.png', 'Astronaut'),
    ('glacierreflection.png',  'Glacier Reflection'),
]

# ── CSS ────────────────────────────────────────────────────────────────────────

CSS = b"""
.page-title {
    font-size: 1.9em;
    font-weight: 800;
    letter-spacing: -0.03em;
}
.page-subtitle {
    font-size: 1.0em;
    opacity: 0.60;
}
.desktop-card {
    border-radius: 12px;
    padding: 14px 8px;
    border: 2px solid transparent;
}
.desktop-card.selected {
    border-color: @accent_color;
    background-color: alpha(@accent_color, 0.12);
}
.desktop-card-emoji {
    font-size: 1.8em;
}
.desktop-card-name {
    font-weight: 700;
    font-size: 0.88em;
}
.desktop-card-desc {
    font-size: 0.76em;
    opacity: 0.55;
}
.disk-row-dev {
    font-family: monospace;
    font-size: 0.88em;
    opacity: 0.70;
}
.warn-label { color: @warning_color; }
.log-view   { font-family: monospace; font-size: 0.84em; }
.step-active { font-weight: 700; color: @accent_color; }
.step-dim    { opacity: 0.35; }
"""

# ── Helpers ────────────────────────────────────────────────────────────────────

def hash_password(pw: str) -> str:
    """Return a SHA-512 crypt hash, or '' on failure."""
    if not pw:
        return ''
    try:
        r = subprocess.run(
            ['openssl', 'passwd', '-6', '--', pw],
            capture_output=True, text=True, timeout=10
        )
        return r.stdout.strip() if r.returncode == 0 else ''
    except Exception:
        return ''


def get_disks() -> list[tuple[str, str, str]]:
    """Return [(device, size, model), …] for internal block devices."""
    try:
        r = subprocess.run(
            ['lsblk', '-J', '-d', '-o', 'NAME,SIZE,TYPE,MODEL,HOTPLUG'],
            capture_output=True, text=True, timeout=8
        )
        data = json.loads(r.stdout)
        result = []
        for d in data.get('blockdevices', []):
            if d.get('type') != 'disk':
                continue
            name = d.get('name', '')
            if not name or name.startswith(('loop', 'sr', 'fd')):
                continue
            if d.get('hotplug') == '1':
                continue
            size  = d.get('size', '?')
            model = (d.get('model') or name).strip()
            result.append((f'/dev/{name}', size, model))
        return result
    except Exception:
        return []


def sudo_prefix() -> list[str]:
    """Return a privilege-escalation prefix, or [] if already root."""
    if os.getuid() == 0:
        return []
    for sudo in ('/run/wrappers/bin/sudo', 'sudo'):
        if shutil.which(sudo):
            return [sudo, '-E', '--']
    if shutil.which('pkexec'):
        return ['pkexec', '--user', 'root']
    return []


# ── State ──────────────────────────────────────────────────────────────────────

class State:
    disk          = ''
    hostname      = 'abora'
    username      = 'abora'
    password      = ''
    tz            = 'UTC'
    keyboard      = 'us'
    locale        = 'en_US.UTF-8'
    locale_label  = 'English (United States)'
    desktop       = 'cosmic'
    apps          = 'favorites'
    anix          = True
    wallpaper     = 'abora-dark.svg'


# ── Page helpers ───────────────────────────────────────────────────────────────

def heading_box(title: str, subtitle: str = '') -> Gtk.Box:
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    box.set_margin_bottom(24)
    t = Gtk.Label(label=title, xalign=0)
    t.add_css_class('page-title')
    t.set_wrap(True)
    box.append(t)
    if subtitle:
        s = Gtk.Label(label=subtitle, xalign=0)
        s.add_css_class('page-subtitle')
        s.set_wrap(True)
        box.append(s)
    return box


def clamped_scroll(child: Gtk.Widget, max_width: int = 640) -> Gtk.ScrolledWindow:
    sw = Gtk.ScrolledWindow(vexpand=True)
    sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    clamp = Adw.Clamp(maximum_size=max_width)
    clamp.set_child(child)
    sw.set_child(clamp)
    return sw


# ── Pages ─────────────────────────────────────────────────────────────────────

class WelcomePage(Adw.StatusPage):
    def __init__(self, _state: State):
        super().__init__(
            icon_name='computer-symbolic',
            title='Install Abora OS',
            description=(
                f'Welcome to Abora OS {VERSION}.\n'
                'This wizard will guide you through installation.\n\n'
                'Your selected disk will be completely erased.\n'
                'Back up any important data before continuing.'
            ),
            vexpand=True,
        )


class LanguagePage(Gtk.Widget):
    def __init__(self, state: State):
        super().__init__()
        self._state = state

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        inner.set_margin_top(8)
        inner.set_margin_bottom(8)
        inner.append(heading_box('Language & Region',
                                 'Choose your locale, timezone, and keyboard layout.'))

        grp = Adw.PreferencesGroup()
        inner.append(grp)

        locale_model = Gtk.StringList()
        for _, lbl in LOCALES:
            locale_model.append(lbl)
        self._locale_row = Adw.ComboRow(title='Language / Locale')
        self._locale_row.set_model(locale_model)
        self._locale_row.set_selected(0)
        grp.add(self._locale_row)

        tz_model = Gtk.StringList()
        for _, lbl in TIMEZONES:
            tz_model.append(lbl)
        self._tz_row = Adw.ComboRow(title='Timezone')
        self._tz_row.set_model(tz_model)
        self._tz_row.set_selected(0)
        grp.add(self._tz_row)

        kb_model = Gtk.StringList()
        for _, lbl in KEYBOARDS:
            kb_model.append(lbl)
        self._kb_row = Adw.ComboRow(title='Keyboard Layout')
        self._kb_row.set_model(kb_model)
        self._kb_row.set_selected(0)
        grp.add(self._kb_row)

        self._sw = clamped_scroll(inner)
        self._sw.set_parent(self)

    def do_size_allocate(self, width, height, baseline):
        self._sw.allocate(width, height, baseline)

    def do_measure(self, orientation, for_size):
        return self._sw.measure(orientation, for_size)

    def collect(self):
        li = self._locale_row.get_selected()
        ti = self._tz_row.get_selected()
        ki = self._kb_row.get_selected()
        self._state.locale       = LOCALES[li][0]
        self._state.locale_label = LOCALES[li][1]
        self._state.tz           = TIMEZONES[ti][0]
        self._state.keyboard     = KEYBOARDS[ki][0]


class IdentityPage(Gtk.Widget):
    def __init__(self, state: State):
        super().__init__()
        self._state = state

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        inner.set_margin_top(8)
        inner.set_margin_bottom(8)
        inner.append(heading_box('Your Details',
                                 'Set up your user account and machine name.'))

        grp = Adw.PreferencesGroup()
        inner.append(grp)

        self._username_row = Adw.EntryRow(title='Username')
        self._username_row.set_text(state.username)
        grp.add(self._username_row)

        self._hostname_row = Adw.EntryRow(title='Computer Name (hostname)')
        self._hostname_row.set_text(state.hostname)
        grp.add(self._hostname_row)

        pw_grp = Adw.PreferencesGroup(title='Password')
        inner.append(pw_grp)

        self._pw_row = Adw.PasswordEntryRow(title='Password')
        pw_grp.add(self._pw_row)

        self._pw2_row = Adw.PasswordEntryRow(title='Confirm Password')
        pw_grp.add(self._pw2_row)

        self._err = Gtk.Label(label='', xalign=0)
        self._err.add_css_class('warn-label')
        self._err.set_margin_top(8)
        inner.append(self._err)

        self._sw = clamped_scroll(inner)
        self._sw.set_parent(self)

    def do_size_allocate(self, width, height, baseline):
        self._sw.allocate(width, height, baseline)

    def do_measure(self, orientation, for_size):
        return self._sw.measure(orientation, for_size)

    def validate(self) -> bool:
        un = self._username_row.get_text().strip()
        hn = self._hostname_row.get_text().strip()
        pw  = self._pw_row.get_text()
        pw2 = self._pw2_row.get_text()
        if not re.fullmatch(r'[a-z][a-z0-9_-]{0,30}', un):
            self._err.set_label('Username: start with a letter, a-z 0-9 _ - only, max 31 chars.')
            return False
        if not re.fullmatch(r'[a-z][a-z0-9-]{0,62}', hn):
            self._err.set_label('Hostname: start with a letter, a-z 0-9 - only, max 63 chars.')
            return False
        if not pw:
            self._err.set_label('Password cannot be empty.')
            return False
        if pw != pw2:
            self._err.set_label('Passwords do not match.')
            return False
        self._err.set_label('')
        return True

    def collect(self):
        self._state.username = self._username_row.get_text().strip()
        self._state.hostname = self._hostname_row.get_text().strip()
        self._state.password = self._pw_row.get_text()


class _DesktopCard(Gtk.Button):
    def __init__(self, did: str, name: str, desc: str, emoji: str, on_select):
        super().__init__()
        self.did = did
        self.add_css_class('flat')
        self.add_css_class('desktop-card')
        self.connect('clicked', lambda _: on_select(did))

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                        halign=Gtk.Align.CENTER)
        em = Gtk.Label(label=emoji)
        em.add_css_class('desktop-card-emoji')
        nm = Gtk.Label(label=name, wrap=True, justify=Gtk.Justification.CENTER)
        nm.add_css_class('desktop-card-name')
        ds = Gtk.Label(label=desc, wrap=True, justify=Gtk.Justification.CENTER,
                       max_width_chars=16)
        ds.add_css_class('desktop-card-desc')
        for w in (em, nm, ds):
            inner.append(w)
        self.set_child(inner)

    def set_selected(self, sel: bool):
        if sel:
            self.add_css_class('selected')
        else:
            self.remove_css_class('selected')


class DesktopPage(Gtk.Box):
    def __init__(self, state: State):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._state = state
        self._cards: dict[str, _DesktopCard] = {}

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        inner.set_margin_top(8)
        inner.set_margin_start(8)
        inner.set_margin_end(8)
        inner.set_margin_bottom(8)
        inner.append(heading_box('Desktop Environment',
                                 'Choose how your desktop will look and feel.'))

        flow = Gtk.FlowBox(
            max_children_per_line=4,
            min_children_per_line=2,
            selection_mode=Gtk.SelectionMode.NONE,
            column_spacing=8,
            row_spacing=8,
            homogeneous=True,
        )
        for did, name, desc, emoji in DESKTOPS:
            card = _DesktopCard(did, name, desc, emoji, self._select)
            card.set_selected(did == state.desktop)
            self._cards[did] = card
            flow.append(card)
        inner.append(flow)

        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.set_child(inner)
        self.append(sw)

    def _select(self, did: str):
        for card in self._cards.values():
            card.set_selected(False)
        if did in self._cards:
            self._cards[did].set_selected(True)
        self._state.desktop = did

    def collect(self):
        pass  # updated live


class DiskPage(Gtk.Box):
    def __init__(self, state: State):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._state = state
        self._disk_rows: list[tuple[str, Gtk.CheckButton]] = []
        self._grp: Adw.PreferencesGroup | None = None
        self._first_btn: Gtk.CheckButton | None = None

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        inner.set_margin_top(8)
        inner.set_margin_bottom(8)
        inner.append(heading_box('Installation Disk',
                                 'Select the disk to install Abora OS on.'))

        warn = Gtk.Box(spacing=8)
        warn.set_margin_bottom(16)
        wi = Gtk.Image.new_from_icon_name('dialog-warning-symbolic')
        wi.add_css_class('warn-label')
        wl = Gtk.Label(label='All data on the selected disk will be permanently erased.',
                       xalign=0, wrap=True)
        wl.add_css_class('warn-label')
        warn.append(wi)
        warn.append(wl)
        inner.append(warn)

        self._grp = Adw.PreferencesGroup(title='Available Disks')
        inner.append(self._grp)

        self._empty_lbl = Gtk.Label(
            label='No suitable disks found. Make sure a disk is attached.',
            xalign=0, wrap=True
        )
        self._empty_lbl.set_margin_top(12)
        self._empty_lbl.set_visible(False)
        inner.append(self._empty_lbl)

        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        clamp = Adw.Clamp(maximum_size=640)
        clamp.set_child(inner)
        sw.set_child(clamp)
        self.append(sw)

        self._refresh()

    def _refresh(self):
        while (c := self._grp.get_first_child()) is not None:
            self._grp.remove(c)
        self._disk_rows.clear()
        self._first_btn = None

        disks = get_disks()
        self._empty_lbl.set_visible(not disks)
        for dev, size, model in disks:
            row = Adw.ActionRow(title=f'{model}  ({size})')
            dlbl = Gtk.Label(label=dev, valign=Gtk.Align.CENTER)
            dlbl.add_css_class('disk-row-dev')
            row.add_suffix(dlbl)

            cb = Gtk.CheckButton(valign=Gtk.Align.CENTER)
            if self._first_btn is None:
                self._first_btn = cb
                cb.set_active(True)
                self._state.disk = dev
            else:
                cb.set_group(self._first_btn)
            cb.connect('toggled', self._on_toggle, dev)
            row.add_prefix(cb)
            row.set_activatable_widget(cb)
            self._grp.add(row)
            self._disk_rows.append((dev, cb))

    def _on_toggle(self, cb: Gtk.CheckButton, dev: str):
        if cb.get_active():
            self._state.disk = dev

    def collect(self):
        for dev, cb in self._disk_rows:
            if cb.get_active():
                self._state.disk = dev
                break


class AppsPage(Gtk.Widget):
    def __init__(self, state: State):
        super().__init__()
        self._state = state
        self._radios: list[tuple[str, Gtk.CheckButton]] = []

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        inner.set_margin_top(8)
        inner.set_margin_bottom(8)
        inner.append(heading_box('Starter Apps',
                                 'Choose a pre-installed app bundle. You can always change this later.'))

        grp = Adw.PreferencesGroup()
        inner.append(grp)

        first_btn = None
        for bid, name, desc in APP_BUNDLES:
            row = Adw.ActionRow(title=name, subtitle=desc)
            cb = Gtk.CheckButton(valign=Gtk.Align.CENTER)
            if first_btn is None:
                first_btn = cb
            else:
                cb.set_group(first_btn)
            cb.set_active(bid == state.apps)
            row.add_prefix(cb)
            row.set_activatable_widget(cb)
            grp.add(row)
            self._radios.append((bid, cb))

        self._sw = clamped_scroll(inner)
        self._sw.set_parent(self)

    def do_size_allocate(self, width, height, baseline):
        self._sw.allocate(width, height, baseline)

    def do_measure(self, orientation, for_size):
        return self._sw.measure(orientation, for_size)

    def collect(self):
        for bid, cb in self._radios:
            if cb.get_active():
                self._state.apps = bid
                break


class OptionsPage(Gtk.Widget):
    def __init__(self, state: State):
        super().__init__()
        self._state = state

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        inner.set_margin_top(8)
        inner.set_margin_bottom(8)
        inner.append(heading_box('Options', 'Fine-tune your installation.'))

        sgrp = Adw.PreferencesGroup(title='System Management')
        inner.append(sgrp)

        anix_row = Adw.ActionRow(
            title='Enable ANIX',
            subtitle='Profile switching, rollback, and snapshot management',
        )
        self._anix_sw = Gtk.Switch(valign=Gtk.Align.CENTER, active=state.anix)
        anix_row.add_suffix(self._anix_sw)
        anix_row.set_activatable_widget(self._anix_sw)
        sgrp.add(anix_row)

        wgrp = Adw.PreferencesGroup(title='Default Wallpaper')
        inner.append(wgrp)

        wp_model = Gtk.StringList()
        for _, lbl in WALLPAPERS:
            wp_model.append(lbl)
        self._wp_row = Adw.ComboRow(title='Wallpaper')
        self._wp_row.set_model(wp_model)
        sel = next((i for i, (wf, _) in enumerate(WALLPAPERS) if wf == state.wallpaper), 0)
        self._wp_row.set_selected(sel)
        wgrp.add(self._wp_row)

        self._sw = clamped_scroll(inner)
        self._sw.set_parent(self)

    def do_size_allocate(self, width, height, baseline):
        self._sw.allocate(width, height, baseline)

    def do_measure(self, orientation, for_size):
        return self._sw.measure(orientation, for_size)

    def collect(self):
        self._state.anix     = self._anix_sw.get_active()
        wi = self._wp_row.get_selected()
        self._state.wallpaper = WALLPAPERS[wi][0]


class SummaryPage(Gtk.Widget):
    def __init__(self, state: State):
        super().__init__()
        self._state = state
        self._grp: Adw.PreferencesGroup | None = None

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        inner.set_margin_top(8)
        inner.set_margin_bottom(8)
        inner.append(heading_box('Review', 'Confirm your choices before installation begins.'))

        self._grp = Adw.PreferencesGroup(title='Installation Summary')
        inner.append(self._grp)

        warn = Gtk.Box(spacing=8)
        warn.set_margin_top(20)
        wi = Gtk.Image.new_from_icon_name('dialog-warning-symbolic')
        wi.add_css_class('warn-label')
        wl = Gtk.Label(xalign=0, wrap=True)
        wl.set_markup('<b>This will permanently erase the selected disk.</b>\nThis action cannot be undone.')
        wl.add_css_class('warn-label')
        warn.append(wi)
        warn.append(wl)
        inner.append(warn)

        self._sw = clamped_scroll(inner)
        self._sw.set_parent(self)

    def do_size_allocate(self, width, height, baseline):
        self._sw.allocate(width, height, baseline)

    def do_measure(self, orientation, for_size):
        return self._sw.measure(orientation, for_size)

    def refresh(self, state: State):
        while (c := self._grp.get_first_child()) is not None:
            self._grp.remove(c)

        desktop_lbl = DESKTOP_LABELS.get(state.desktop, state.desktop)
        bundle_lbl  = next((n for b, n, _ in APP_BUNDLES if b == state.apps), state.apps)
        wp_lbl      = next((l for f, l in WALLPAPERS if f == state.wallpaper), state.wallpaper)

        for title, value in [
            ('Disk',       state.disk or '(none selected)'),
            ('Username',   state.username),
            ('Hostname',   state.hostname),
            ('Desktop',    desktop_lbl),
            ('App Bundle', bundle_lbl),
            ('Locale',     state.locale_label),
            ('Timezone',   state.tz),
            ('Keyboard',   state.keyboard),
            ('Wallpaper',  wp_lbl),
            ('ANIX',       'Enabled' if state.anix else 'Disabled'),
        ]:
            row = Adw.ActionRow(title=title)
            lbl = Gtk.Label(label=value, valign=Gtk.Align.CENTER, selectable=True)
            row.add_suffix(lbl)
            self._grp.add(row)


class InstallingPage(Gtk.Box):
    def __init__(self, _state: State):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.set_margin_top(16)
        self.set_margin_bottom(12)
        self.set_margin_start(16)
        self.set_margin_end(16)

        self._title = Gtk.Label(label='Installing Abora OS…', xalign=0)
        self._title.add_css_class('page-title')
        self.append(self._title)

        self._status = Gtk.Label(label='Preparing…', xalign=0)
        self._status.add_css_class('page-subtitle')
        self.append(self._status)

        self._bar = Gtk.ProgressBar(pulse_step=0.04)
        self.append(self._bar)

        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._buf = Gtk.TextBuffer()
        tv = Gtk.TextView(buffer=self._buf, editable=False,
                          monospace=True, cursor_visible=False)
        tv.add_css_class('log-view')
        sw.set_child(tv)
        self._tv = tv
        self.append(sw)

    def pulse(self):
        self._bar.pulse()
        return True

    def append_log(self, text: str):
        end = self._buf.get_end_iter()
        self._buf.insert(end, text)
        self._tv.scroll_mark_onscreen(self._buf.get_insert())

    def set_done(self, success: bool, msg: str = ''):
        self._bar.set_fraction(1.0 if success else 0.0)
        if success:
            self._title.set_label('Installation Complete!')
            self._status.set_label('Abora OS has been installed. Remove the live medium and reboot.')
        else:
            self._title.set_label('Installation Failed')
            self._status.set_label(msg or 'An error occurred. Check the log above for details.')


# ── Page order ─────────────────────────────────────────────────────────────────

PAGES_ORDER = ['welcome', 'language', 'identity', 'desktop', 'disk', 'apps',
               'options', 'summary', 'installing']
STEP_NAMES  = ['Welcome', 'Language', 'Identity', 'Desktop', 'Disk', 'Apps',
               'Options', 'Review', 'Installing']


# ── Main window ────────────────────────────────────────────────────────────────

class AboraInstallerWindow(Adw.ApplicationWindow):

    def __init__(self, app: Adw.Application):
        super().__init__(
            application=app,
            title='Install Abora OS',
            default_width=960,
            default_height=700,
        )
        self._state        = State()
        self._cur          = 0
        self._installing   = False
        self._pulse_id     = None
        self._build_ui()

    def _build_ui(self):
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_content(root)

        hb = Adw.HeaderBar()
        self._wt = Adw.WindowTitle(title='Install Abora OS', subtitle='')
        hb.set_title_widget(self._wt)
        root.append(hb)

        # Step bar
        self._step_bar = Gtk.Box(spacing=4, halign=Gtk.Align.CENTER)
        self._step_bar.set_margin_top(6)
        self._step_bar.set_margin_bottom(6)
        self._step_lbls: list[Gtk.Label] = []
        for i, name in enumerate(STEP_NAMES):
            if i:
                sep = Gtk.Label(label='›')
                sep.add_css_class('step-dim')
                self._step_bar.append(sep)
            lbl = Gtk.Label(label=name)
            lbl.add_css_class('step-dim')
            self._step_bar.append(lbl)
            self._step_lbls.append(lbl)
        root.append(self._step_bar)
        root.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # Stack
        self._stack = Gtk.Stack(
            vexpand=True,
            transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
            transition_duration=200,
        )
        self._stack.set_margin_start(16)
        self._stack.set_margin_end(16)
        self._pages: dict[str, Gtk.Widget] = {}

        for name, cls in [
            ('welcome',    WelcomePage),
            ('language',   LanguagePage),
            ('identity',   IdentityPage),
            ('desktop',    DesktopPage),
            ('disk',       DiskPage),
            ('apps',       AppsPage),
            ('options',    OptionsPage),
            ('summary',    SummaryPage),
            ('installing', InstallingPage),
        ]:
            w = cls(self._state)
            self._pages[name] = w
            self._stack.add_named(w, name)

        root.append(self._stack)
        root.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # Nav bar
        nav = Gtk.Box(spacing=8, halign=Gtk.Align.END)
        nav.set_margin_top(12)
        nav.set_margin_bottom(12)
        nav.set_margin_end(16)

        self._back = Gtk.Button(label='← Back')
        self._back.connect('clicked', self._go_back)
        nav.append(self._back)

        self._next = Gtk.Button(label='Next →')
        self._next.add_css_class('suggested-action')
        self._next.connect('clicked', self._go_next)
        nav.append(self._next)

        root.append(nav)

        self._refresh_nav()
        self._refresh_steps()

    # ── Navigation ─────────────────────────────────────────────────────────────

    def _go_back(self, _btn):
        if self._installing or self._cur == 0:
            return
        self._stack.set_transition_type(Gtk.StackTransitionType.SLIDE_RIGHT)
        self._cur -= 1
        self._stack.set_visible_child_name(PAGES_ORDER[self._cur])
        self._stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self._refresh_nav()
        self._refresh_steps()

    def _go_next(self, _btn):
        if self._installing:
            return

        name = PAGES_ORDER[self._cur]
        page = self._pages[name]

        # Validate current page
        if name == 'identity':
            if not page.validate():
                return
        if name == 'disk' and not self._state.disk:
            return

        # Collect from current page
        if hasattr(page, 'collect'):
            page.collect()

        # Trigger install from summary
        if name == 'summary':
            self._start_install()
            return

        # Refresh summary before showing it
        if name == 'options':
            self._pages['summary'].refresh(self._state)

        self._cur += 1
        self._stack.set_visible_child_name(PAGES_ORDER[self._cur])
        self._refresh_nav()
        self._refresh_steps()

    def _refresh_nav(self):
        name = PAGES_ORDER[self._cur]
        is_installing = name == 'installing'

        self._back.set_visible(self._cur > 0 and not is_installing)
        self._back.set_sensitive(not self._installing)

        self._next.set_visible(not is_installing)
        self._next.set_sensitive(not self._installing)

        if name == 'welcome':
            self._next.set_label('Begin →')
            self._next.remove_css_class('destructive-action')
            self._next.add_css_class('suggested-action')
        elif name == 'summary':
            self._next.set_label('Install Now')
            self._next.remove_css_class('suggested-action')
            self._next.add_css_class('destructive-action')
        else:
            self._next.set_label('Next →')
            self._next.remove_css_class('destructive-action')
            self._next.add_css_class('suggested-action')

        self._wt.set_subtitle(
            f'Step {self._cur + 1} of {len(PAGES_ORDER)}'
            if not is_installing else 'Installing…'
        )

    def _refresh_steps(self):
        for i, lbl in enumerate(self._step_lbls):
            if i == self._cur:
                lbl.add_css_class('step-active')
                lbl.remove_css_class('step-dim')
            else:
                lbl.remove_css_class('step-active')
                lbl.add_css_class('step-dim')

    # ── Installation ───────────────────────────────────────────────────────────

    def _write_batch_params(self, path: str):
        pw_hash = hash_password(self._state.password)
        dl = DESKTOP_LABELS.get(self._state.desktop, self._state.desktop)
        with open(path, 'w') as f:
            f.write('# Generated by abora-installer-gui\n')
            for k, v in [
                ('disk',                    self._state.disk),
                ('hostname_value',          self._state.hostname),
                ('username_value',          self._state.username),
                ('user_password_hash',      pw_hash),
                ('root_password_mode',      'same'),
                ('root_password_hash',      ''),
                ('timezone_value',          self._state.tz),
                ('keyboard_value',          self._state.keyboard),
                ('xkb_layout_value',        self._state.keyboard),
                ('locale_value',            self._state.locale),
                ('language_label',          self._state.locale_label),
                ('desktop_profile',         self._state.desktop),
                ('desktop_label',           dl),
                ('desktop_variant_id',      self._state.desktop),
                ('wallpaper_name',          self._state.wallpaper),
                ('starter_apps_bundle',     self._state.apps),
                ('install_apps_during_setup', 'no'),
                ('anix_enabled',            'yes' if self._state.anix else 'no'),
            ]:
                f.write(f'{k}={shlex.quote(v)}\n')

    def _start_install(self):
        self._installing = True
        self._cur = PAGES_ORDER.index('installing')
        self._stack.set_visible_child_name('installing')
        self._refresh_nav()
        self._refresh_steps()

        ip: InstallingPage = self._pages['installing']
        self._pulse_id = GLib.timeout_add(80, ip.pulse)

        threading.Thread(target=self._run_install, daemon=True).start()

    def _run_install(self):
        ip: InstallingPage = self._pages['installing']

        # Write params file
        try:
            fd, params = tempfile.mkstemp(prefix='abora-batch-', suffix='.sh', dir='/tmp')
            os.close(fd)
            self._write_batch_params(params)
        except Exception as e:
            GLib.idle_add(ip.set_done, False, f'Failed to write params: {e}')
            return

        prefix = sudo_prefix()
        cmd    = prefix + ['bash', INSTALLER_BIN, '--batch', params]

        def log(line: str):
            GLib.idle_add(ip.append_log, line)
            try:
                with open(LOG_FILE, 'a') as lf:
                    lf.write(line)
            except Exception:
                pass

        log(f'[gui] cmd: {" ".join(cmd)}\n')

        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            for line in proc.stdout:
                log(line)
            proc.wait()
            success = proc.returncode == 0
        except Exception as e:
            log(f'\n[error] {e}\n')
            success = False
        finally:
            try:
                os.unlink(params)
            except Exception:
                pass

        if self._pulse_id is not None:
            GLib.source_remove(self._pulse_id)
            self._pulse_id = None

        GLib.idle_add(ip.set_done, success)
        if success:
            GLib.idle_add(self._show_reboot_dialog)

    def _show_reboot_dialog(self):
        dialog = Adw.MessageDialog(
            transient_for=self,
            heading='Installation Complete',
            body='Abora OS is installed. Remove the live medium, then reboot to enjoy your new system.',
        )
        dialog.add_response('stay',   'Stay in Live')
        dialog.add_response('reboot', 'Reboot Now')
        dialog.set_response_appearance('reboot', Adw.ResponseAppearance.SUGGESTED)
        dialog.connect('response', lambda d, r: (
            d.close(),
            subprocess.run(['systemctl', 'reboot'], check=False) if r == 'reboot' else None,
        ))
        dialog.present()


# ── Application entry point ────────────────────────────────────────────────────

class AboraInstaller(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id='org.aboraos.Installer',
            flags=Gio.ApplicationFlags.DEFAULT_FLAGS,
        )
        self.connect('startup',  self._on_startup)
        self.connect('activate', self._on_activate)

    def _on_startup(self, _app):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        display = Gdk.Display.get_default()
        if display:
            Gtk.StyleContext.add_provider_for_display(
                display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

    def _on_activate(self, app):
        AboraInstallerWindow(app).present()


def main():
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(f'[abora-installer-gui] starting pid={os.getpid()}\n')
    except Exception:
        pass
    sys.exit(AboraInstaller().run(sys.argv))


if __name__ == '__main__':
    main()
