#!/usr/bin/env python3
"""Abora OS Graphical Installer — DENALI Edition (GTK4 + libadwaita)"""

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw, GLib, Gdk
import subprocess, threading, os, sys, re, time
from pathlib import Path

# ── Desktop profiles ──────────────────────────────────────────────────────────

DESKTOP_PROFILES = [
    ("gnome",        "GNOME",          "Full-featured, modern",             "◉"),
    ("plasma",       "KDE Plasma",     "Powerful, customizable",            "◈"),
    ("cosmic",       "COSMIC",         "System76 desktop (Rust)",           "◎"),
    ("hyprland",     "Hyprland",       "Tiling Wayland compositor",         "◆"),
    ("sway",         "Sway",           "i3-compatible Wayland",             "◇"),
    ("mangowm",      "MangoWM",        "Abora's native WM",                 "◐"),
    ("cinnamon",     "Cinnamon",       "Traditional, polished",             "●"),
    ("xfce",         "XFCE",          "Lightweight, classic",              "○"),
    ("mate",         "MATE",           "Classic GNOME 2 experience",        "◑"),
    ("budgie",       "Budgie",         "Clean, Ubuntu-style",               "◒"),
    ("lxqt",         "LXQt",          "Very lightweight Qt",               "□"),
    ("pantheon",     "Pantheon",       "Elementary OS DE",                  "▣"),
    ("i3",           "i3wm",           "Manual tiling window manager",      "▦"),
    ("awesome",      "Awesome",        "Highly scriptable Lua WM",          "▧"),
    ("openbox",      "Openbox",        "Minimal stacking WM",               "▤"),
    ("niri",         "Niri",           "Scrollable Wayland tiles",          "▥"),
    ("river",        "River",          "Wayland WM with tags",              "▨"),
    ("qtile",        "Qtile",          "Python tiling WM",                  "▩"),
    ("bspwm",        "BSPWM",          "BSP tiling window manager",         "▪"),
    ("herbstluftwm", "HerbstluftWM",   "Manual tiling WM",                  "▫"),
    ("fluxbox",      "Fluxbox",        "Fast, minimal X11 WM",              "▬"),
    ("icewm",        "IceWM",          "Tiny, snappy WM",                   "▭"),
    ("none",         "No Desktop",     "CLI only — install later",          "▮"),
]

APP_BUNDLES = [
    ("favorites",  "Fan Favorites",  "Curated mix of popular apps"),
    ("essentials", "Essentials",     "Browsers, office, media, utilities"),
    ("social",     "Social",         "Chat, video calls, messaging apps"),
    ("creator",    "Creator",        "Design, audio, video, creative tools"),
    ("developer",  "Developer",      "IDEs, containers, terminal tools"),
    ("gaming",     "Gaming",         "Steam, Lutris, Wine, gaming helpers"),
    ("system",     "System Tools",   "Monitoring, backup, system management"),
    ("none",       "None",           "Start clean — add apps later"),
]

# ── CSS ───────────────────────────────────────────────────────────────────────

CSS = b"""
window { background-color: #0d1117; color: #e6edf3; }

.sidebar {
    background-color: #090d14;
    border-right: 1px solid #1a2236;
    min-width: 196px;
    padding: 0 0 16px 0;
}
.sidebar-brand {
    color: #3b82f6;
    font-weight: 900;
    font-size: 13px;
    letter-spacing: 3px;
    padding: 24px 20px 4px 20px;
}
.sidebar-version {
    color: #374151;
    font-size: 10px;
    padding: 0 20px 20px 20px;
}
.step-row {
    padding: 9px 16px;
    border-radius: 8px;
    margin: 1px 8px;
    background: transparent;
}
.step-row.active   { background: rgba(59,130,246,0.14); }
.step-badge {
    font-size: 10px; font-weight: 700;
    min-width: 20px; min-height: 20px;
    border-radius: 10px;
    border: 1px solid #1f2937;
    color: #4b5563;
}
.step-badge.active { background: #3b82f6; border-color: #3b82f6; color: #fff; }
.step-badge.done   { background: #059669; border-color: #059669; color: #fff; }
.step-lbl        { font-size: 12px; color: #4b5563; }
.step-lbl.active { color: #93c5fd; font-weight: 600; }
.step-lbl.done   { color: #34d399; }

.content-area { background: #0d1117; padding: 40px 48px; }
.page-eyebrow {
    color: #3b82f6; font-size: 10px; font-weight: 700;
    letter-spacing: 2px;
}
.page-title    { color: #e6edf3; font-size: 26px; font-weight: 700; }
.page-subtitle { color: #6b7280; font-size: 13px; }

.card {
    background: #161b22;
    border: 1px solid #21262d;
    border-radius: 10px;
    padding: 14px;
}
.card.selected {
    border-color: #3b82f6;
    background: rgba(59,130,246,0.08);
}
.card-title    { color: #e6edf3; font-weight: 600; font-size: 13px; }
.card-subtitle { color: #6b7280; font-size: 11px; }
.card-icon     { color: #3b82f6; font-size: 22px; }

.field-label {
    color: #6b7280; font-size: 11px; font-weight: 600;
    letter-spacing: 0.5px;
}
entry {
    background: #161b22; color: #e6edf3;
    border: 1px solid #30363d; border-radius: 6px;
    padding: 8px 12px; font-size: 13px;
    caret-color: #3b82f6;
}
entry:focus { border-color: #3b82f6; }

.check-ok   { color: #34d399; font-size: 12px; }
.check-fail { color: #f87171; font-size: 12px; }
.check-info { color: #6b7280; font-size: 12px; }

.log-view {
    background: #090d14; color: #8b949e;
    font-size: 11px; padding: 12px;
    border: 1px solid #1a2236; border-radius: 8px;
}

progressbar > trough { background: #1f2937; border-radius: 4px; min-height: 6px; }
progressbar > trough > progress { background: #3b82f6; border-radius: 4px; }

.bottom-bar {
    background: #090d14;
    border-top: 1px solid #1a2236;
    padding: 14px 24px;
}
button.nav-back {
    background: #1f2937; color: #9ca3af;
    border: 1px solid #374151; border-radius: 6px;
    padding: 7px 18px; font-size: 13px;
}
button.nav-back:hover { background: #272f3d; }
button.nav-next {
    background: #3b82f6; color: #fff;
    border: none; border-radius: 6px;
    padding: 7px 22px; font-size: 13px; font-weight: 600;
}
button.nav-next:hover { background: #2563eb; }
button.nav-next.danger { background: #dc2626; }
button.nav-next.danger:hover { background: #b91c1c; }
button.nav-next.success { background: #059669; }

.warn-box {
    background: rgba(220,38,38,0.08);
    border: 1px solid rgba(220,38,38,0.25);
    border-radius: 8px; padding: 12px 16px;
    color: #fca5a5; font-size: 12px;
}
.info-box {
    background: rgba(59,130,246,0.07);
    border: 1px solid rgba(59,130,246,0.2);
    border-radius: 8px; padding: 10px 14px;
    color: #93c5fd; font-size: 12px;
}
.summary-key { color: #6b7280; font-size: 13px; min-width: 150px; }
.summary-val { color: #e6edf3; font-size: 13px; font-weight: 500; }
.status-ok   { color: #34d399; font-weight: 600; font-size: 13px; }
.status-fail { color: #f87171; font-weight: 600; font-size: 13px; }

.welcome-mark { color: #3b82f6; font-size: 56px; font-weight: 900; }
.welcome-title { color: #e6edf3; font-size: 38px; font-weight: 800; }
.welcome-sub   { color: #6b7280; font-size: 15px; }
.done-title    { color: #34d399; font-size: 30px; font-weight: 700; }
"""

# ── Settings ──────────────────────────────────────────────────────────────────

class Settings:
    hostname = "abora"
    username = "abora"
    timezone = "UTC"
    keyboard = "us"
    xkb_layout = "us"
    password_hash = ""
    root_password_hash = ""
    root_password_mode = "same"
    desktop_profile = "gnome"
    desktop_label = "GNOME"
    starter_apps_bundle = "favorites"
    starter_apps_label = "Fan Favorites"
    install_apps_during_setup = False
    anix_enabled = True
    disk = ""
    disk_label = ""

# ── Helpers ───────────────────────────────────────────────────────────────────

def run(cmd, input_text=None, timeout=10):
    try:
        r = subprocess.run(cmd, input=input_text, capture_output=True,
                           text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def hash_password(pw):
    try:
        r = subprocess.run(["openssl", "passwd", "-6", "-stdin"],
                           input=pw, capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def get_disks():
    rc, out, _ = run(["lsblk", "-dn", "-e", "7,11", "-o", "NAME,SIZE,MODEL,TYPE"], timeout=5)
    disks = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 2 or parts[-1] != "disk":
            continue
        name = parts[0]
        if re.match(r'^(fd|loop|ram|sr|zram)', name):
            continue
        size = parts[1]
        model = " ".join(parts[2:-1]) or "Unknown"
        disks.append((f"/dev/{name}", f"{size}  {model}"))
    return disks


def net_ok():
    rc, _, _ = run(["ping", "-c", "1", "-W", "3", "1.1.1.1"], timeout=6)
    return rc == 0


def find_installer():
    candidates = [
        "/etc/abora/installer.sh",
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "abora-installer.sh"),
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return None

# ── Base page ─────────────────────────────────────────────────────────────────

class Page(Gtk.Box):
    def __init__(self, s):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.s = s
        self.add_css_class("content-area")

    # helpers
    def head(self, eyebrow, title, subtitle=""):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_bottom(28)
        if eyebrow:
            e = Gtk.Label(label=eyebrow)
            e.add_css_class("page-eyebrow")
            e.set_halign(Gtk.Align.START)
            box.append(e)
        t = Gtk.Label(label=title)
        t.add_css_class("page-title")
        t.set_halign(Gtk.Align.START)
        t.set_wrap(True)
        box.append(t)
        if subtitle:
            sub = Gtk.Label(label=subtitle)
            sub.add_css_class("page-subtitle")
            sub.set_halign(Gtk.Align.START)
            sub.set_wrap(True)
            box.append(sub)
        self.append(box)

    def lbl(self, text, css=None, halign=Gtk.Align.START):
        l = Gtk.Label(label=text)
        if css:
            l.add_css_class(css)
        l.set_halign(halign)
        l.set_wrap(True)
        return l

    def gap(self, h=16):
        s = Gtk.Box(); s.set_size_request(-1, h); self.append(s)

    def validate(self):
        return True, ""

    def on_enter(self):
        pass

    def on_leave(self):
        pass

# ── Page 0: Welcome ───────────────────────────────────────────────────────────

class WelcomePage(Page):
    def __init__(self, s):
        super().__init__(s)
        self.set_halign(Gtk.Align.CENTER)
        self.set_valign(Gtk.Align.CENTER)
        self.set_hexpand(True)
        self.set_vexpand(True)
        self.set_spacing(12)

        mark = Gtk.Label(label="◈")
        mark.add_css_class("welcome-mark")
        mark.set_halign(Gtk.Align.CENTER)
        self.append(mark)

        title = Gtk.Label(label="Abora OS")
        title.add_css_class("welcome-title")
        title.set_halign(Gtk.Align.CENTER)
        self.append(title)

        sub = Gtk.Label(label="DENALI 3.14  ·  A calm, guided install")
        sub.add_css_class("welcome-sub")
        sub.set_halign(Gtk.Align.CENTER)
        self.append(sub)

        self.gap(24)

        pills = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        pills.set_halign(Gtk.Align.CENTER)
        for text in ["NixOS base", "ANIX layer", "22 desktops", "7 app bundles"]:
            p = Gtk.Label(label=text)
            p.add_css_class("card")
            p.set_margin_top(2); p.set_margin_bottom(2)
            p.set_margin_start(2); p.set_margin_end(2)
            pills.append(p)
        self.append(pills)

# ── Page 1: Network ───────────────────────────────────────────────────────────

class NetworkPage(Page):
    def __init__(self, s):
        super().__init__(s)
        self.head("Step 1", "Network",
                  "A working internet connection is required to download packages.")

        self.status = self.lbl("Checking…")
        self.append(self.status)
        self.gap(16)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        b1 = Gtk.Button(label="Recheck")
        b1.connect("clicked", lambda _: self._check())
        row.append(b1)
        b2 = Gtk.Button(label="Open Network Manager")
        b2.connect("clicked", lambda _: subprocess.Popen(
            ["bash", "-c", "nmtui || true"]))
        row.append(b2)
        self.append(row)

    def on_enter(self):
        self._check()

    def _check(self):
        self.status.set_text("Checking…")
        self.status.set_css_classes([])
        threading.Thread(target=self._do_check, daemon=True).start()

    def _do_check(self):
        ok = net_ok()
        GLib.idle_add(self._update, ok)

    def _update(self, ok):
        if ok:
            self.status.set_text("✓  Connected — internet available")
            self.status.set_css_classes(["status-ok"])
        else:
            self.status.set_text("✕  No internet connection detected")
            self.status.set_css_classes(["status-fail"])

# ── Page 2: Identity ─────────────────────────────────────────────────────────

class IdentityPage(Page):
    def __init__(self, s):
        super().__init__(s)
        self.head("Step 2", "Identity & Locale",
                  "Set your hostname, username, timezone, keyboard, and password.")

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)

        form = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        form.set_margin_end(8)

        def field(lbl_text, placeholder, initial):
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            l = Gtk.Label(label=lbl_text)
            l.add_css_class("field-label")
            l.set_halign(Gtk.Align.START)
            box.append(l)
            e = Gtk.Entry()
            e.set_placeholder_text(placeholder)
            e.set_text(initial)
            e.set_hexpand(True)
            box.append(e)
            form.append(box)
            return e

        def pw_field(lbl_text):
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            l = Gtk.Label(label=lbl_text)
            l.add_css_class("field-label")
            l.set_halign(Gtk.Align.START)
            box.append(l)
            e = Gtk.PasswordEntry()
            e.set_show_peek_icon(True)
            e.set_hexpand(True)
            box.append(e)
            form.append(box)
            return e

        self.hostname = field("HOSTNAME", "abora", s.hostname)
        self.username = field("USERNAME", "abora", s.username)
        self.timezone = field("TIMEZONE", "UTC", s.timezone)
        self.keyboard = field("CONSOLE KEYMAP", "us", s.keyboard)
        self.xkb     = field("XKB LAYOUT", "us", s.xkb_layout)

        sep = Gtk.Separator()
        sep.set_margin_top(8); sep.set_margin_bottom(8)
        form.append(sep)

        self.pw1 = pw_field("PASSWORD")
        self.pw2 = pw_field("CONFIRM PASSWORD")

        sep2 = Gtk.Separator()
        sep2.set_margin_top(8); sep2.set_margin_bottom(8)
        form.append(sep2)

        rl = Gtk.Label(label="ROOT ACCOUNT")
        rl.add_css_class("field-label")
        rl.set_halign(Gtk.Align.START)
        form.append(rl)

        self.root_dd = Gtk.DropDown.new_from_strings([
            "Same password as user",
            "Lock root (sudo only)",
            "Set separate root password",
        ])
        self.root_dd.set_hexpand(True)
        self.root_dd.connect("notify::selected", self._root_toggle)
        form.append(self.root_dd)

        self.rpw1 = pw_field("ROOT PASSWORD")
        self.rpw2 = pw_field("CONFIRM ROOT PASSWORD")
        self.rpw1.set_visible(False)
        self.rpw2.set_visible(False)

        self.err = self.lbl("", "status-fail")
        self.err.set_visible(False)
        form.append(self.err)

        scroll.set_child(form)
        self.append(scroll)

    def _root_toggle(self, dd, _):
        show = dd.get_selected() == 2
        self.rpw1.set_visible(show)
        self.rpw2.set_visible(show)

    def validate(self):
        hn = self.hostname.get_text().strip()
        un = self.username.get_text().strip()
        tz = self.timezone.get_text().strip()
        kb = self.keyboard.get_text().strip()
        p1 = self.pw1.get_text()
        p2 = self.pw2.get_text()

        if not re.match(r'^[A-Za-z0-9][A-Za-z0-9\-]{0,62}$', hn):
            return False, "Hostname: letters/numbers/hyphens only, start with letter or digit."
        if not re.match(r'^[a-z_][a-z0-9_\-]*$', un):
            return False, "Username: lowercase, numbers, hyphens — start with a letter."
        if not tz:
            return False, "Timezone cannot be empty (e.g. America/New_York or UTC)."
        if not kb:
            return False, "Console keymap cannot be empty."
        if not p1:
            return False, "Password cannot be empty."
        if p1 != p2:
            return False, "Passwords do not match."
        if self.root_dd.get_selected() == 2:
            r1 = self.rpw1.get_text()
            r2 = self.rpw2.get_text()
            if not r1:
                return False, "Root password cannot be empty."
            if r1 != r2:
                return False, "Root passwords do not match."
        return True, ""

    def on_leave(self):
        s = self.s
        s.hostname   = self.hostname.get_text().strip()
        s.username   = self.username.get_text().strip()
        s.timezone   = self.timezone.get_text().strip()
        s.keyboard   = self.keyboard.get_text().strip()
        s.xkb_layout = self.xkb.get_text().strip()
        pw = self.pw1.get_text()
        s.password_hash = hash_password(pw)
        idx = self.root_dd.get_selected()
        if idx == 0:
            s.root_password_mode = "same"
            s.root_password_hash = s.password_hash
        elif idx == 1:
            s.root_password_mode = "locked"
            s.root_password_hash = ""
        else:
            s.root_password_mode = "custom"
            s.root_password_hash = hash_password(self.rpw1.get_text())

# ── Page 3: Desktop ───────────────────────────────────────────────────────────

class DesktopPage(Page):
    def __init__(self, s):
        super().__init__(s)
        self.head("Step 3", "Desktop Environment",
                  "Choose how your desktop looks and behaves. You can change it later with ANIX.")
        self._selected = s.desktop_profile
        self._children = {}

        flow = Gtk.FlowBox()
        flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        flow.set_homogeneous(True)
        flow.set_max_children_per_line(3)
        flow.set_min_children_per_line(2)
        flow.set_column_spacing(10)
        flow.set_row_spacing(10)
        flow.connect("child-activated", self._selected_cb)
        self._flow = flow

        for profile, name, desc, icon in DESKTOP_PROFILES:
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            card.add_css_class("card")
            card.set_margin_top(3); card.set_margin_bottom(3)
            card.set_margin_start(3); card.set_margin_end(3)
            card.set_size_request(160, 80)
            card._profile = profile

            hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            ic = Gtk.Label(label=icon)
            ic.add_css_class("card-icon")
            hdr.append(ic)
            nl = Gtk.Label(label=name)
            nl.add_css_class("card-title")
            nl.set_halign(Gtk.Align.START)
            hdr.append(nl)
            card.append(hdr)

            dl = Gtk.Label(label=desc)
            dl.add_css_class("card-subtitle")
            dl.set_halign(Gtk.Align.START)
            dl.set_wrap(True)
            card.append(dl)

            child = Gtk.FlowBoxChild()
            child.set_child(card)
            child._profile = profile
            flow.append(child)
            self._children[profile] = child

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)
        scroll.set_child(flow)
        self.append(scroll)
        self._pre_select()

    def _pre_select(self):
        ch = self._children.get(self._selected)
        if ch:
            self._flow.select_child(ch)
            ch.get_child().add_css_class("selected")

    def _selected_cb(self, flow, child):
        for c in self._children.values():
            c.get_child().remove_css_class("selected")
        child.get_child().add_css_class("selected")
        self._selected = child._profile

    def on_leave(self):
        for profile, name, _, _ in DESKTOP_PROFILES:
            if profile == self._selected:
                self.s.desktop_profile = profile
                self.s.desktop_label = name
                break

# ── Page 4: Apps ─────────────────────────────────────────────────────────────

class AppsPage(Page):
    def __init__(self, s):
        super().__init__(s)
        self.head("Step 4", "Starter App Bundle",
                  "Choose a set of apps to install. You can add more any time with ANIX.")
        self._selected = s.starter_apps_bundle
        self._cards = {}

        grid = Gtk.Grid()
        grid.set_row_spacing(10)
        grid.set_column_spacing(10)

        for i, (bid, bname, bdesc) in enumerate(APP_BUNDLES):
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            card.add_css_class("card")
            card.set_margin_top(2); card.set_margin_bottom(2)
            card.set_margin_start(2); card.set_margin_end(2)
            card.set_size_request(180, 70)
            card._bid = bid

            tl = Gtk.Label(label=bname)
            tl.add_css_class("card-title")
            tl.set_halign(Gtk.Align.START)
            card.append(tl)

            dl = Gtk.Label(label=bdesc)
            dl.add_css_class("card-subtitle")
            dl.set_halign(Gtk.Align.START)
            dl.set_wrap(True)
            card.append(dl)

            gesture = Gtk.GestureClick()
            gesture.connect("released", self._card_clicked, bid, card)
            card.add_controller(gesture)

            grid.attach(card, i % 2, i // 2, 1, 1)
            self._cards[bid] = card

        self.append(grid)
        self.gap(20)

        # Timing option
        timing_lbl = self.lbl("WHEN TO INSTALL APPS", "field-label")
        self.append(timing_lbl)
        self.gap(6)

        self.timing_dd = Gtk.DropDown.new_from_strings([
            "After first boot (recommended — fast install)",
            "During setup (slow, may time out on large bundles)",
        ])
        self.timing_dd.set_hexpand(True)
        self.append(self.timing_dd)

        self._refresh_cards()

    def _card_clicked(self, gesture, n_press, x, y, bid, card):
        self._selected = bid
        self._refresh_cards()

    def _refresh_cards(self):
        for bid, card in self._cards.items():
            if bid == self._selected:
                card.add_css_class("selected")
            else:
                card.remove_css_class("selected")

    def on_leave(self):
        s = self.s
        s.starter_apps_bundle = self._selected
        for bid, bname, _ in APP_BUNDLES:
            if bid == self._selected:
                s.starter_apps_label = bname
                break
        s.install_apps_during_setup = (self.timing_dd.get_selected() == 1)

# ── Page 5: Options ───────────────────────────────────────────────────────────

class OptionsPage(Page):
    def __init__(self, s):
        super().__init__(s)
        self.head("Step 5", "Options",
                  "Configure optional system features.")

        # ANIX
        anix_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        anix_box.add_css_class("card")
        anix_box.set_margin_bottom(12)
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        left.set_hexpand(True)
        tl = self.lbl("ANIX Helper Layer", "card-title")
        left.append(tl)
        dl = self.lbl("Friendly NixOS commands: anix status, anix rollback, anix switch. Recommended.", "card-subtitle")
        left.append(dl)
        anix_box.append(left)
        self.anix_sw = Gtk.Switch()
        self.anix_sw.set_active(s.anix_enabled)
        self.anix_sw.set_valign(Gtk.Align.CENTER)
        anix_box.append(self.anix_sw)
        self.append(anix_box)

        self.gap(8)
        info = self.lbl("GitHub CLI (optional) — Sign in after first boot with: gh auth login", "info-box")
        self.append(info)

    def on_leave(self):
        self.s.anix_enabled = self.anix_sw.get_active()

# ── Page 6: Preflight ─────────────────────────────────────────────────────────

class PreflightPage(Page):
    def __init__(self, s):
        super().__init__(s)
        self.head("Step 6", "Preflight Checks",
                  "Verify that all required tools and assets are present before touching any disk.")

        self.check_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.check_list.set_vexpand(True)
        self.append(self.check_list)

        self.gap(12)
        self.run_btn = Gtk.Button(label="Run Checks")
        self.run_btn.set_halign(Gtk.Align.START)
        self.run_btn.connect("clicked", lambda _: self._run())
        self.append(self.run_btn)

        self._ok = False

    def on_enter(self):
        self._run()

    def _run(self):
        # Clear list
        while True:
            child = self.check_list.get_first_child()
            if child is None:
                break
            self.check_list.remove(child)

        self.run_btn.set_sensitive(False)
        self._ok = False
        threading.Thread(target=self._do_checks, daemon=True).start()

    def _do_checks(self):
        results = []
        cmds = ["wipefs", "parted", "mkfs.vfat", "mkfs.ext4",
                "nixos-generate-config", "nixos-install", "openssl", "lsblk"]
        for cmd in cmds:
            rc, _, _ = run(["which", cmd], timeout=3)
            results.append((cmd, rc == 0, "command"))

        rc, _, _ = run(["ping", "-c", "1", "-W", "2", "cache.nixos.org"], timeout=5)
        results.append(("Nix cache reachable", rc == 0, "network"))

        dev_tty = os.path.exists("/dev/tty")
        results.append(("/dev/tty present", dev_tty, "env"))

        installer = find_installer()
        results.append(("Installer script found", installer is not None, "asset"))

        GLib.idle_add(self._show_results, results)

    def _show_results(self, results):
        all_ok = all(ok for _, ok, _ in results)
        self._ok = all_ok

        for name, ok, kind in results:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            icon = "✓" if ok else "✕"
            css  = "check-ok" if ok else "check-fail"
            row.append(self.lbl(f"{icon}  {name}", css))
            self.check_list.append(row)

        self.run_btn.set_sensitive(True)

    def validate(self):
        if not self._ok:
            return False, "Some preflight checks failed. Fix the issues and run checks again."
        return True, ""

# ── Page 7: Disk ─────────────────────────────────────────────────────────────

class DiskPage(Page):
    def __init__(self, s):
        super().__init__(s)
        self.head("Step 7", "Installation Disk",
                  "Select the disk to install Abora OS on. ALL data on it will be erased.")

        self.warn = Gtk.Label(label="⚠  All data on the selected disk will be permanently erased!")
        self.warn.add_css_class("warn-box")
        self.warn.set_halign(Gtk.Align.FILL)
        self.warn.set_wrap(True)
        self.append(self.warn)
        self.gap(16)

        self._disk_var = None
        self.disk_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.append(self.disk_box)

        self.gap(8)
        refresh = Gtk.Button(label="Refresh Disk List")
        refresh.set_halign(Gtk.Align.START)
        refresh.connect("clicked", lambda _: self._load())
        self.append(refresh)

        self.gap(8)
        self.sel_label = self.lbl("", "check-info")
        self.append(self.sel_label)

    def on_enter(self):
        self._load()

    def _load(self):
        while True:
            child = self.disk_box.get_first_child()
            if child is None:
                break
            self.disk_box.remove(child)

        disks = get_disks()
        if not disks:
            self.disk_box.append(self.lbl("No installable disks found.", "check-fail"))
            return

        self._radios = []
        first = None
        for dev, label in disks:
            rb = Gtk.CheckButton(label=f"{dev}  —  {label}")
            rb.add_css_class("card")
            if first is None:
                first = rb
                rb.set_active(True)
                self.s.disk = dev
                self.s.disk_label = label
                self.sel_label.set_text(f"Selected: {dev}")
            else:
                rb.set_group(first)
            rb._dev = dev
            rb._dlabel = label
            rb.connect("toggled", self._toggled)
            self.disk_box.append(rb)
            self._radios.append(rb)

    def _toggled(self, rb):
        if rb.get_active():
            self.s.disk = rb._dev
            self.s.disk_label = rb._dlabel
            self.sel_label.set_text(f"Selected: {rb._dev}  —  {rb._dlabel}")

    def validate(self):
        if not self.s.disk:
            return False, "Please select an installation disk."
        return True, ""

# ── Page 8: Confirm ───────────────────────────────────────────────────────────

class ConfirmPage(Page):
    def __init__(self, s):
        super().__init__(s)
        self.head("Step 8", "Confirm Installation",
                  "Review your choices before the installer erases the disk and begins.")

        self.grid = Gtk.Grid()
        self.grid.set_row_spacing(10)
        self.grid.set_column_spacing(24)
        self.append(self.grid)

        self.gap(24)
        danger = Gtk.Label(label=(
            "⚠  Clicking Install Now will PERMANENTLY ERASE the selected disk "
            "and install Abora OS. This cannot be undone."
        ))
        danger.add_css_class("warn-box")
        danger.set_halign(Gtk.Align.FILL)
        danger.set_wrap(True)
        self.append(danger)

    def on_enter(self):
        # Rebuild summary grid
        while True:
            child = self.grid.get_first_child()
            if child is None:
                break
            self.grid.remove(child)

        s = self.s
        rows = [
            ("Disk",     f"{s.disk}  ← will be erased"),
            ("Hostname",  s.hostname),
            ("Username",  s.username),
            ("Timezone",  s.timezone),
            ("Keyboard",  f"{s.keyboard} / {s.xkb_layout}"),
            ("Desktop",   f"{s.desktop_label} ({s.desktop_profile})"),
            ("Apps",      f"{s.starter_apps_label} ({'during setup' if s.install_apps_during_setup else 'after first boot'})"),
            ("ANIX",      "enabled" if s.anix_enabled else "disabled"),
            ("Root",      s.root_password_mode),
        ]
        for i, (k, v) in enumerate(rows):
            kl = Gtk.Label(label=k)
            kl.add_css_class("summary-key")
            kl.set_halign(Gtk.Align.START)
            vl = Gtk.Label(label=v)
            vl.add_css_class("summary-val")
            vl.set_halign(Gtk.Align.START)
            vl.set_wrap(True)
            self.grid.attach(kl, 0, i, 1, 1)
            self.grid.attach(vl, 1, i, 1, 1)

# ── Page 9: Install ───────────────────────────────────────────────────────────

class InstallPage(Page):
    def __init__(self, s):
        super().__init__(s)
        self._started = False
        self._done = False
        self._success = False
        self._on_done_cb = None

        self.head("Installing", "Installing Abora OS…",
                  "This takes 10–30 minutes. Do not power off your computer.")

        self.progress = Gtk.ProgressBar()
        self.progress.set_fraction(0)
        self.progress.set_show_text(True)
        self.progress.set_text("Starting…")
        self.append(self.progress)

        self.gap(8)
        self.status = self.lbl("Preparing…", "check-info")
        self.append(self.status)

        self.gap(8)

        self.log_buf = Gtk.TextBuffer()
        log_view = Gtk.TextView(buffer=self.log_buf)
        log_view.set_editable(False)
        log_view.set_cursor_visible(False)
        log_view.set_monospace(True)
        log_view.add_css_class("log-view")

        self._scroll = Gtk.ScrolledWindow()
        self._scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        self._scroll.set_vexpand(True)
        self._scroll.set_child(log_view)
        self.append(self._scroll)

    def on_enter(self):
        if not self._started:
            self._started = True
            self._begin()

    def _begin(self):
        s = self.s

        # Write params file
        params = f"""\
disk="{s.disk}"
hostname_value="{s.hostname}"
username_value="{s.username}"
timezone_value="{s.timezone}"
keyboard_value="{s.keyboard}"
xkb_layout_value="{s.xkb_layout}"
desktop_profile="{s.desktop_profile}"
desktop_label="{s.desktop_label}"
desktop_variant_id="{s.desktop_profile}"
starter_apps_bundle="{s.starter_apps_bundle}"
starter_apps_label="{s.starter_apps_label}"
install_apps_during_setup="{'yes' if s.install_apps_during_setup else 'no'}"
anix_enabled="{'yes' if s.anix_enabled else 'no'}"
user_password_hash='{s.password_hash}'
root_password_hash='{s.root_password_hash}'
root_password_mode="{s.root_password_mode}"
wallpaper_name="Daytime-MNT.jpg"
"""
        params_file = "/tmp/abora-install-params.sh"
        with open(params_file, "w") as f:
            f.write(params)

        installer = find_installer()
        if not installer:
            self._log("ERROR: installer script not found at /etc/abora/installer.sh\n")
            self._finish(False)
            return

        env = os.environ.copy()
        env["ABORA_DESKTOP_PROFILES_LIB"] = "/etc/abora/desktop-profiles.sh"
        env["ABORA_APP_CATALOG_LIB"]      = "/etc/abora/app-catalog.sh"
        env["TERM"] = "dumb"

        proc = subprocess.Popen(
            ["bash", installer, "--batch", params_file],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, env=env, bufsize=1,
        )
        threading.Thread(target=self._reader, args=(proc,), daemon=True).start()

    def _reader(self, proc):
        for line in proc.stdout:
            GLib.idle_add(self._log, line)
        rc = proc.wait()
        GLib.idle_add(self._finish, rc == 0)

    def _log(self, line):
        # Strip ANSI
        clean = re.sub(r'\033\[[0-9;]*[mABCDEFGHJKLMSTfnsu]', '', line)
        self.log_buf.insert(self.log_buf.get_end_iter(), clean)
        # Auto-scroll
        adj = self._scroll.get_vadjustment()
        adj.set_value(adj.get_upper() - adj.get_page_size())
        self._track_progress(clean)

    STAGES = [
        (0.05,  "Starting",              "Preparing…"),
        (0.15,  "partition_disk: start", "Partitioning disk…"),
        (0.25,  "format complete",       "Disk formatted"),
        (0.32,  "mount_target",          "Mounting filesystems…"),
        (0.40,  "nixos-generate-config", "Generating NixOS config…"),
        (0.50,  "validat",               "Validating configuration…"),
        (0.58,  "nixos-install",         "Running nixos-install…"),
        (0.68,  "copying path",          "Downloading packages…"),
        (0.85,  "installing the boot",   "Installing bootloader…"),
        (0.93,  "repaired limine",       "Finalizing…"),
        (1.00,  "done!",                 "Complete!"),
    ]

    def _track_progress(self, line):
        ll = line.lower()
        for frac, keyword, label in self.STAGES:
            if keyword in ll:
                cur = self.progress.get_fraction()
                if frac > cur:
                    self.progress.set_fraction(frac)
                    self.progress.set_text(label)
                    self.status.set_text(label)
                break
        # Smooth bump while downloading
        if "copying" in ll or "fetching" in ll or "downloading" in ll:
            cur = self.progress.get_fraction()
            if 0.58 <= cur < 0.84:
                self.progress.set_fraction(min(cur + 0.003, 0.84))

    def _finish(self, ok):
        self._done = True
        self._success = ok
        if ok:
            self.progress.set_fraction(1.0)
            self.progress.set_text("Installation complete!")
            self.status.set_text("✓  Abora OS installed successfully!")
            self.status.set_css_classes(["status-ok"])
        else:
            self.status.set_text("✕  Installation failed — see log above.")
            self.status.set_css_classes(["status-fail"])
        if self._on_done_cb:
            self._on_done_cb(ok)

# ── Page 10: Done ─────────────────────────────────────────────────────────────

class DonePage(Page):
    def __init__(self, s):
        super().__init__(s)
        self._win_ref = None

        self.set_halign(Gtk.Align.CENTER)
        self.set_valign(Gtk.Align.CENTER)
        self.set_hexpand(True)
        self.set_vexpand(True)
        self.set_spacing(16)

        self.title = Gtk.Label(label="✓  Installation Complete!")
        self.title.add_css_class("done-title")
        self.title.set_halign(Gtk.Align.CENTER)
        self.append(self.title)

        sub = self.lbl(
            "Abora OS is installed. Remove the ISO or detach it before rebooting,\n"
            "otherwise the system will boot back into the live installer.",
            "page-subtitle"
        )
        sub.set_halign(Gtk.Align.CENTER)
        self.append(sub)

        self.gap(8)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        row.set_halign(Gtk.Align.CENTER)

        b1 = Gtk.Button(label="Power Off")
        b1.add_css_class("nav-next")
        b1.connect("clicked", lambda _: self._poweroff())
        row.append(b1)

        b2 = Gtk.Button(label="Reboot into Abora OS")
        b2.add_css_class("nav-next")
        b2.connect("clicked", lambda _: self._reboot())
        row.append(b2)

        b3 = Gtk.Button(label="Stay in Live Shell")
        b3.add_css_class("nav-back")
        b3.connect("clicked", lambda _: self._stay())
        row.append(b3)

        self.append(row)

        self.gap(8)
        self.log_info = self.lbl(
            "Logs: /tmp/abora-install.log   Config: /tmp/abora-config.log",
            "check-info"
        )
        self.log_info.set_halign(Gtk.Align.CENTER)
        self.append(self.log_info)

    def _poweroff(self):
        subprocess.run(["sync"], check=False)
        subprocess.Popen(["systemctl", "poweroff", "--no-wall"])

    def _reboot(self):
        subprocess.run(["sync"], check=False)
        subprocess.Popen(["systemctl", "reboot", "--no-wall"])

    def _stay(self):
        if self._win_ref:
            self._win_ref.close()

# ── Installer Window ──────────────────────────────────────────────────────────

STEP_NAMES = [
    "Welcome", "Network", "Identity", "Desktop", "Apps",
    "Options", "Preflight", "Disk", "Confirm", "Install", "Done"
]

PAGE_CLASSES = [
    WelcomePage, NetworkPage, IdentityPage, DesktopPage, AppsPage,
    OptionsPage, PreflightPage, DiskPage, ConfirmPage, InstallPage, DonePage
]


class InstallerWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.s = Settings()
        self.step = 0
        self._pages = []

        self.set_title("Abora OS Installer")
        self.set_default_size(1060, 700)
        self.add_css_class("main-window")

        self._build()

    def _build(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_content(outer)

        main = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        main.set_vexpand(True)
        outer.append(main)

        main.append(self._sidebar())

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.stack.set_transition_duration(180)
        self.stack.set_hexpand(True)
        self.stack.set_vexpand(True)
        main.append(self.stack)

        for i, Cls in enumerate(PAGE_CLASSES):
            page = Cls(self.s)
            page.set_hexpand(True)
            page.set_vexpand(True)
            self.stack.add_named(page, STEP_NAMES[i])
            self._pages.append(page)

        # Wire done page window ref
        self._pages[-1]._win_ref = self

        # Wire install page done callback
        install_page = self._pages[STEP_NAMES.index("Install")]
        install_page._on_done_cb = self._install_done

        outer.append(self._bottom_bar())

        self._update_sidebar()
        self._update_buttons()
        self._pages[0].on_enter()

    def _sidebar(self):
        sb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        sb.add_css_class("sidebar")

        brand = Gtk.Label(label="ABORA OS")
        brand.add_css_class("sidebar-brand")
        brand.set_halign(Gtk.Align.START)
        sb.append(brand)

        ver = Gtk.Label(label="DENALI 3.14 Installer")
        ver.add_css_class("sidebar-version")
        ver.set_halign(Gtk.Align.START)
        sb.append(ver)

        self._step_rows = []
        for i, name in enumerate(STEP_NAMES):
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            row.add_css_class("step-row")

            badge = Gtk.Label(label=str(i + 1))
            badge.add_css_class("step-badge")
            badge.set_halign(Gtk.Align.CENTER)
            badge.set_valign(Gtk.Align.CENTER)
            badge.set_size_request(22, 22)
            row.append(badge)

            lbl = Gtk.Label(label=name)
            lbl.add_css_class("step-lbl")
            lbl.set_halign(Gtk.Align.START)
            row.append(lbl)

            row._badge = badge
            row._lbl = lbl
            sb.append(row)
            self._step_rows.append(row)

        spacer = Gtk.Box()
        spacer.set_vexpand(True)
        sb.append(spacer)
        return sb

    def _bottom_bar(self):
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        bar.add_css_class("bottom-bar")

        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        bar.append(spacer)

        self.back_btn = Gtk.Button(label="← Back")
        self.back_btn.add_css_class("nav-back")
        self.back_btn.connect("clicked", lambda _: self._go_back())
        bar.append(self.back_btn)

        self.next_btn = Gtk.Button(label="Next →")
        self.next_btn.add_css_class("nav-next")
        self.next_btn.connect("clicked", lambda _: self._go_next())
        bar.append(self.next_btn)

        return bar

    def _update_sidebar(self):
        for i, row in enumerate(self._step_rows):
            if i < self.step:
                row._badge.set_label("✓")
                row._badge.set_css_classes(["step-badge", "done"])
                row._lbl.set_css_classes(["step-lbl", "done"])
                row.remove_css_class("active")
            elif i == self.step:
                row._badge.set_label(str(i + 1))
                row._badge.set_css_classes(["step-badge", "active"])
                row._lbl.set_css_classes(["step-lbl", "active"])
                row.add_css_class("active")
            else:
                row._badge.set_label(str(i + 1))
                row._badge.set_css_classes(["step-badge"])
                row._lbl.set_css_classes(["step-lbl"])
                row.remove_css_class("active")

    def _update_buttons(self):
        last = len(STEP_NAMES) - 1
        n = self.step

        # Back: visible on steps 1..8 (not Welcome, not Install, not Done)
        self.back_btn.set_visible(0 < n <= 8)

        if n >= last - 1:  # Install (9) or Done (10)
            self.next_btn.set_visible(False)
        elif n == last - 2:  # Confirm (8)
            self.next_btn.set_visible(True)
            self.next_btn.set_label("Install Now")
            self.next_btn.set_css_classes(["nav-next", "danger"])
        else:
            self.next_btn.set_visible(True)
            self.next_btn.set_label("Next →")
            self.next_btn.set_css_classes(["nav-next"])

    def _go_next(self):
        page = self._pages[self.step]
        ok, msg = page.validate()
        if not ok:
            self._show_error(msg)
            return
        page.on_leave()
        self._navigate(self.step + 1)

    def _go_back(self):
        if self.step > 0:
            self._navigate(self.step - 1)

    def _navigate(self, n):
        self.step = n
        self.stack.set_visible_child_name(STEP_NAMES[n])
        self._pages[n].on_enter()
        self._update_sidebar()
        self._update_buttons()

    def _install_done(self, ok):
        if ok:
            self._navigate(STEP_NAMES.index("Done"))

    def _show_error(self, msg):
        dialog = Adw.MessageDialog(
            transient_for=self,
            heading="Please correct this",
            body=msg,
        )
        dialog.add_response("ok", "OK")
        dialog.set_default_response("ok")
        dialog.present()

# ── Application ───────────────────────────────────────────────────────────────

class AboraInstaller(Adw.Application):
    def __init__(self):
        super().__init__(application_id="org.abora.installer",
                         flags=Gio.ApplicationFlags.FLAGS_NONE
                         if hasattr(Gio, "ApplicationFlags")
                         else 0)
        self.connect("activate", self._activate)

    def _activate(self, app):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        Adw.StyleManager.get_default().set_color_scheme(
            Adw.ColorScheme.FORCE_DARK
        )

        win = InstallerWindow(application=app)
        win.present()


def main():
    if os.geteuid() != 0:
        print("abora-installer-gui: must run as root.", file=sys.stderr)
        print("Re-run with: sudo abora-install-gui", file=sys.stderr)
        sys.exit(1)

    from gi.repository import Gio
    app = AboraInstaller()
    sys.exit(app.run(sys.argv))


if __name__ == "__main__":
    main()
