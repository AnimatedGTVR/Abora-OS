#!/usr/bin/env python3
"""Local survey, learning progress, and optional desktop reminder."""

import argparse
import csv
import io
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time
from urllib.parse import urlparse


LANGUAGE_URL = "https://nix.dev/tutorials/nix-language"
MANUAL_URL = "https://nixos.org/manual/nixos/stable/"
LESSONS = [
    ("Nix and NixOS", "Nix manages packages; NixOS uses it to describe a whole system. "
     "Abora adds its own modules and tools on top. You can learn Nix without removing Abora.",
     "Which is the operating system?", ["NixOS", "The Nix language", "A package"], 0, MANUAL_URL),
    ("Read a Nix value", "An attribute set groups named values. Assignments end with semicolons.\n\n"
     '{ greeting = "hello"; enabled = true; }\n\nLists use brackets: [ "one" "two" ].',
     "Which value is a boolean?", ['"hello"', "true", '[ "one" ]'], 1, LANGUAGE_URL),
    ("Functions and packages", "A module can request pkgs as a function argument.\n\n"
     "{ pkgs, ... }: {\n  environment.systemPackages = [ pkgs.hello ];\n}\n\n"
     "This declares a system package. Reading this example changes nothing.",
     "Where does pkgs come from here?", ["A password", "The wallpaper", "A module argument"], 2, LANGUAGE_URL),
    ("Your configuration", "Modules combine options such as services and packages. "
     "Keep your hardware configuration and filesystem definitions. Abora-specific options "
     "need Abora modules; deleting those imports is not a native-NixOS conversion.",
     "What must a migration preserve?", ["Only the theme", "Hardware and filesystem configuration", "Nothing"], 1, MANUAL_URL),
    ("Build before activation", "For a reviewed flake configuration, nixos-rebuild build builds "
     "without activating it. nixos-rebuild test activates temporarily without making it the boot default. "
     "switch activates and sets the boot default. Testing can still interrupt services.",
     "Which action builds without activation?", ["switch", "test", "build"], 2, MANUAL_URL),
    ("Recovery and independence", "Keep backups and a known-good boot generation. A system rollback "
     "does not restore personal files or application databases. Native NixOS still needs declarations "
     "for your users, desktop, apps, networking and bootloader.",
     "Does a system rollback restore deleted documents?", ["Yes", "No"], 1, MANUAL_URL),
]
MIGRATION_GUIDE = """Native NixOS migration review

This is a checklist, not a generated configuration or an automatic migration.
No system files have been changed. Keeping Abora is equally valid.

1. Back up personal files and /etc/nixos, including untracked files. Keep
   password hashes and other secrets private; do not publish the backup.
2. Work in a separate configuration copy. Inventory all imported Abora and
   ANIX modules, users, desktops, packages, services and custom overlays.
3. Translate Abora/ANIX options to native NixOS declarations BEFORE removing
   their imports. Preserve hardware-configuration.nix, filesystems, bootloader,
   users, authentication, networking, desktop and system.stateVersion.
4. Keep the existing pinned inputs initially. Review the configuration against
   the NixOS manual. Do not use Abora's live-ISO flake as your installed system.
5. Build the reviewed configuration with nixos-rebuild build --flake
   /path/to/reviewed-config#YOUR_HOST. Replace both placeholders appropriately.
6. Test first in a VM or spare disk. Back up again before activating on your
   machine. nixos-rebuild test can interrupt services; it is not a sandbox.
7. Keep the known-good generation and recovery media. Only switch after review
   and testing; verify a reboot before removing old generations or Abora tools.

System generations do not back up personal files or application databases.
Reference: https://nixos.org/manual/nixos/stable/
"""


def state_path(name):
    base = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    return base / "abora" / (name + ".json")


def read_state(name):
    try:
        value = json.loads(state_path(name).read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def write_state(name, **updates):
    path = state_path(name)
    state = read_state(name)
    state.update(updates)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".community-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def reminders_enabled(state):
    return not any(state.get(key) for key in ("do_not_prompt", "exported", "submitted"))


def reminder_preference(enabled, now):
    if not enabled:
        return {"do_not_prompt": True}
    return {"do_not_prompt": False, "exported": False, "submitted": False,
            "next_prompt": now + 7 * 86400}


def reminder_due(state, now):
    if not reminders_enabled(state):
        return False
    stamp = state.get("next_prompt", 0)
    if not isinstance(stamp, (int, float)) or not math.isfinite(stamp):
        stamp = 0
    return now >= stamp


def survey_url():
    value = os.environ.get("ABORA_SURVEY_URL", "").strip()
    try:
        parsed = urlparse(value)
    except ValueError:
        return ""
    return value if parsed.scheme == "https" and parsed.hostname and not parsed.username else ""


def survey_csv(usage, rating, feedback):
    # CSV quoting alone does not stop spreadsheet formula interpretation.
    def cell(value):
        return "'" + value if value.lstrip().startswith(("=", "+", "-", "@")) or value.startswith(("\t", "\r", "\n")) else value
    out = io.StringIO(newline="")
    writer = csv.writer(out)
    writer.writerow(["schema_version", "usage", "rating", "feedback"])
    writer.writerow(["1", cell(usage), str(rating), cell(feedback)])
    return out.getvalue()


def completed_lessons(state):
    values = state.get("completed", [])
    if not isinstance(values, list):
        return set()
    return {i for i in values if type(i) is int and 0 <= i < len(LESSONS)}


def resume_lesson(state):
    done = completed_lessons(state)
    return next((i for i in range(len(LESSONS)) if i not in done), len(LESSONS) - 1)


def run_gui(mode):
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, Gio, GLib, Gtk

    class Application(Adw.Application):
        def __init__(self):
            super().__init__(application_id="org.abora.LearnNix" if mode == "learn" else "org.abora.Survey")
            self.lesson = resume_lesson(read_state("learn-nix")) if mode == "learn" else 0

        def do_activate(self):
            if self.props.active_window:
                self.props.active_window.present()
                return
            self.window = Adw.ApplicationWindow(application=self, title="Learn Nix / NixOS" if mode == "learn" else "Abora Survey")
            self.window.set_default_size(620, 650)
            toolbar = Adw.ToolbarView()
            toolbar.add_top_bar(Adw.HeaderBar())
            self.page = Adw.PreferencesPage()
            toolbar.set_content(self.page)
            self.window.set_content(toolbar)
            if mode == "learn":
                self.show_lesson()
            else:
                self.show_survey()
            self.window.present()

        def message(self, title, body):
            dialog = Adw.MessageDialog(transient_for=self.window, heading=title, body=body)
            dialog.add_response("ok", "OK")
            dialog.present()

        def persist(self, name, **updates):
            try:
                write_state(name, **updates)
                return True
            except OSError as exc:
                self.message("Could not save", str(exc))
                return False

        def group(self, title, description=None):
            group = Adw.PreferencesGroup(title=title)
            if description:
                group.set_description(description)
            self.page.add(group)
            return group

        def button(self, group, label, callback):
            button = Gtk.Button(label=label, margin_top=8, margin_bottom=8)
            button.connect("clicked", callback)
            group.add(button)
            return button

        def save_file(self, name, content, after=None):
            chooser = Gtk.FileChooserNative(title="Export", transient_for=self.window,
                                            action=Gtk.FileChooserAction.SAVE,
                                            accept_label="Export", cancel_label="Cancel")
            chooser.set_current_name(name)
            def response(dialog, result):
                if result == Gtk.ResponseType.ACCEPT:
                    try:
                        target = dialog.get_file()
                        if not target or not target.is_native():
                            raise OSError("Choose a local file for this export.")
                        target.replace_contents(content.encode("utf-8"), None, False,
                                                Gio.FileCreateFlags.PRIVATE, None)
                        if after:
                            after()
                        self.message("Exported", target.get_path())
                    except GLib.Error as exc:
                        self.message("Export failed", str(exc))
                    except OSError as exc:
                        self.message("Export failed", str(exc))
                dialog.destroy()
            chooser.connect("response", response)
            chooser.show()

        def show_survey(self):
            group = self.group("Your experience", "Optional. Only the answers below are exported. No device details, logs or identifiers are collected. Nothing is uploaded.")
            usage = Adw.ComboRow(title="Time using Abora", model=Gtk.StringList.new(["Trying it today", "Less than a month", "One month or longer"]))
            group.add(usage)
            rating = Adw.ComboRow(title="Overall experience", model=Gtk.StringList.new(["1 - Poor", "2", "3 - Okay", "4", "5 - Great"]))
            rating.set_selected(2)
            group.add(rating)
            feedback = Adw.EntryRow(title="Feedback (optional)")
            group.add(feedback)
            consent = Gtk.CheckButton(label="I reviewed my answers and want to export them", margin_top=12)
            group.add(consent)
            export = self.button(group, "Export CSV", lambda _b: self.save_file(
                "abora-survey.csv", survey_csv(usage.get_selected_item().get_string(), rating.get_selected() + 1, feedback.get_text()),
                self.survey_exported))
            export.set_sensitive(False)
            consent.connect("toggled", lambda widget: export.set_sensitive(widget.get_active()))
            for field, signal in ((usage, "notify::selected"), (rating, "notify::selected"), (feedback, "changed")):
                field.connect(signal, lambda *_args: consent.set_active(False))
            url = survey_url()
            if url:
                online = self.group("Online survey", "The browser opens the form provider. No local answers are attached; its privacy policy applies.")
                online.add(Gtk.LinkButton(uri=url, label="Open Survey"))
                self.button(online, "I submitted the form", lambda _b: self.finish_survey(submitted=True))
            reminders = self.group("Reminders")
            enabled = Gtk.Switch(valign=Gtk.Align.CENTER, active=reminders_enabled(read_state("survey")))
            self.reminder_switch = enabled
            row = Adw.ActionRow(title="Survey reminders")
            row.add_suffix(enabled)
            reminders.add(row)
            self.reminder_handler = enabled.connect("notify::active", self.change_reminders)
            self.button(reminders, "Remind me in a week", lambda _b: self.finish_survey(**reminder_preference(True, time.time())))

        def sync_reminders(self):
            widget = self.reminder_switch
            widget.handler_block(self.reminder_handler)
            try:
                widget.set_active(reminders_enabled(read_state("survey")))
            finally:
                widget.handler_unblock(self.reminder_handler)

        def change_reminders(self, widget, _property):
            self.persist("survey", **reminder_preference(widget.get_active(), time.time()))
            # A failed write must not leave the switch displaying an unsaved choice.
            self.sync_reminders()

        def survey_exported(self):
            self.persist("survey", exported=True)
            self.sync_reminders()

        def finish_survey(self, **updates):
            if self.persist("survey", **updates):
                self.window.close()

        def show_lesson(self):
            if hasattr(self, "lesson_group"):
                self.page.remove(self.lesson_group)
            title, body, question, choices, answer, source = LESSONS[self.lesson]
            done = completed_lessons(read_state("learn-nix"))
            group = self.group(f"{self.lesson + 1}. {title}", f"{len(done)} of {len(LESSONS)} lessons completed")
            self.lesson_group = group
            group.add(Gtk.Label(label=body, wrap=True, xalign=0, selectable=True, margin_top=12, margin_bottom=12))
            group.add(Gtk.LinkButton(uri=source, label="Reference"))
            quiz = Adw.ComboRow(title=question, model=Gtk.StringList.new(["Choose an answer"] + choices))
            group.add(quiz)
            def check(_button):
                if quiz.get_selected() != answer + 1:
                    self.message("Try again", "Review the lesson, then choose another answer.")
                    return
                done.add(self.lesson)
                if self.persist("learn-nix", completed=sorted(done)):
                    if len(done) == len(LESSONS):
                        self.offer_migration()
                    else:
                        self.message("Correct", "Lesson completed. Your progress is saved.")
                    self.show_lesson()
            self.button(group, "Check answer", check)
            previous = self.button(group, "Previous lesson", lambda _b: self.navigate(-1))
            previous.set_sensitive(self.lesson > 0)
            following = self.button(group, "Next lesson", lambda _b: self.navigate(1))
            following.set_sensitive(self.lesson < len(LESSONS) - 1)
            if len(done) == len(LESSONS):
                self.button(group, "Native NixOS migration review", lambda _b: self.offer_migration())

        def navigate(self, delta):
            self.lesson += delta
            self.show_lesson()

        def offer_migration(self):
            dialog = Adw.MessageDialog(transient_for=self.window, heading="Course complete",
                body="Would you like to plan a switch to native NixOS without ANIX? This exports a review checklist, not an automatic conversion. Your system stays unchanged.")
            dialog.add_response("keep", "Keep Abora")
            dialog.add_response("review", "Export migration checklist")
            dialog.set_default_response("keep")
            dialog.set_close_response("keep")
            dialog.connect("response", lambda _d, response: self.save_file("nixos-migration-review.txt", MIGRATION_GUIDE) if response == "review" else None)
            dialog.present()

    return Application().run([])


def notify():
    # One nudge per week, never a popup window or a background data upload.
    state = read_state("survey")
    now = time.time()
    if not reminder_due(state, now):
        return 0
    result = subprocess.run(["notify-send", "--app-name=Abora Survey", "--icon=dialog-question",
                             "How is Abora working for you?", "Open Abora Survey from your applications to share optional feedback or disable reminders."], check=False, timeout=15)
    if result.returncode == 0:
        write_state("survey", next_prompt=now + 7 * 86400)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["survey", "learn", "notify"], nargs="?", default="survey")
    mode = parser.parse_args().mode
    try:
        return notify() if mode == "notify" else run_gui(mode)
    except (OSError, subprocess.TimeoutExpired) as exc:
        parser.exit(1, f"Abora: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
