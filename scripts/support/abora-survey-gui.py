#!/usr/bin/env python3
"""Optional GTK4/libadwaita survey prompt for Abora OS."""

from __future__ import annotations

import json
import os
import platform
import subprocess
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, Gtk  # noqa: E402


APP_ID = "org.abora.Survey"
STATE_DIR = Path.home() / ".local" / "state" / "abora"
STATE_FILE = STATE_DIR / "survey.json"
SURVEY_URL = os.environ.get("ABORA_SURVEY_URL", "https://aboraos.org/survey")


def get_abora_version() -> str:
    """Return the installed Abora version when available."""
    try:
        result = subprocess.run(
            ["abora", "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.SubprocessError):
        pass
    return "Unknown"


def get_device_name() -> str:
    """Return a lightweight, local-only device description."""
    product_name = Path("/sys/devices/virtual/dmi/id/product_name")
    if product_name.exists():
        try:
            value = product_name.read_text(encoding="utf-8").strip()
            if value:
                return value
        except OSError:
            pass
    return platform.machine()


def read_state() -> dict[str, object]:
    """Read local survey state without failing if it is missing or malformed."""
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def write_state(**updates: object) -> None:
    """Persist survey choices locally; no information is uploaded here."""
    state = read_state()
    state.update(updates)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")


class SurveyWindow(Adw.ApplicationWindow):
    """Main window for Abora's optional user survey prompt."""

    def __init__(self, app: Adw.Application) -> None:
        """Build the survey interface."""
        super().__init__(application=app)
        self.set_title("Abora Survey")
        self.set_default_size(560, 520)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        header.set_title_widget(Adw.WindowTitle(title="Help Improve Abora", subtitle="Optional user survey"))
        toolbar.add_top_bar(header)

        page = Adw.PreferencesPage()

        intro = Adw.PreferencesGroup()
        intro.set_title("Would you like to help improve Abora?")
        intro.set_description(
            "This survey is completely optional. Nothing is sent unless you choose to open and submit the survey."
        )
        page.add(intro)

        info = Adw.PreferencesGroup()
        info.set_title("What we may ask")
        info.set_description("Basic information that helps us understand how people are using Abora.")
        page.add(info)

        self._add_info_row(info, "Device", get_device_name())
        self._add_info_row(info, "Abora version", get_abora_version())
        self._add_info_row(info, "Usage", "How long you have used Abora")
        self._add_info_row(info, "Experience", "Whether you like Abora and expect to keep using it")

        privacy = Adw.PreferencesGroup()
        privacy.set_title("Privacy")
        privacy.set_description(
            "The details shown above stay on your computer in this app. Opening the survey does not automatically upload them."
        )
        page.add(privacy)

        actions = Adw.PreferencesGroup()
        page.add(actions)

        yes_row = Adw.ActionRow(title="Fill out the survey")
        yes_row.set_subtitle("Open the Abora survey in your browser")
        yes_button = Gtk.Button(label="Open Survey")
        yes_button.add_css_class("suggested-action")
        yes_button.set_valign(Gtk.Align.CENTER)
        yes_button.connect("clicked", self._open_survey)
        yes_row.add_suffix(yes_button)
        yes_row.set_activatable_widget(yes_button)
        actions.add(yes_row)

        no_row = Adw.ActionRow(title="Not right now")
        no_row.set_subtitle("Close this prompt without sending anything")
        no_button = Gtk.Button(label="No Thanks")
        no_button.set_valign(Gtk.Align.CENTER)
        no_button.connect("clicked", self._decline)
        no_row.add_suffix(no_button)
        no_row.set_activatable_widget(no_button)
        actions.add(no_row)

        remind_row = Adw.ActionRow(title="Ask me later")
        remind_row.set_subtitle("Close this prompt without deciding permanently")
        remind_button = Gtk.Button(label="Later")
        remind_button.set_valign(Gtk.Align.CENTER)
        remind_button.connect("clicked", self._later)
        remind_row.add_suffix(remind_button)
        remind_row.set_activatable_widget(remind_button)
        actions.add(remind_row)

        toolbar.set_content(page)
        self.set_content(toolbar)

    @staticmethod
    def _add_info_row(group: Adw.PreferencesGroup, title: str, value: str) -> None:
        """Add a read-only informational row."""
        row = Adw.ActionRow(title=title, subtitle=value)
        group.add(row)

    def _open_survey(self, _button: Gtk.Button) -> None:
        """Record consent to open the survey, then launch it in the browser."""
        try:
            write_state(last_choice="accepted")
            Gio.AppInfo.launch_default_for_uri(SURVEY_URL, None)
            self.close()
        except Exception as exc:  # GTK callback: surface launch failures to user.
            dialog = Adw.MessageDialog(
                transient_for=self,
                heading="Could not open the survey",
                body=str(exc),
            )
            dialog.add_response("ok", "OK")
            dialog.present()

    def _decline(self, _button: Gtk.Button) -> None:
        """Record that the user declined and close the prompt."""
        write_state(last_choice="declined", do_not_prompt=True)
        self.close()

    def _later(self, _button: Gtk.Button) -> None:
        """Record a temporary dismissal and close the prompt."""
        write_state(last_choice="later")
        self.close()


class SurveyApplication(Adw.Application):
    """Application wrapper for the optional Abora survey prompt."""

    def __init__(self) -> None:
        """Initialize the application."""
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_activate(self) -> None:
        """Present the survey window."""
        window = self.props.active_window
        if window is None:
            window = SurveyWindow(self)
        window.present()


def main() -> int:
    """Run the survey application."""
    app = SurveyApplication()
    return app.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
