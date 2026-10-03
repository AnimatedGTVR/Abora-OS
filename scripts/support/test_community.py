"""Run with python3 -m unittest discover -s scripts/support -p test_community.py."""
import csv
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("community", Path(__file__).with_name("abora-community.py"))
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class CommunityTests(unittest.TestCase):
    def test_reminder_choices(self):
        self.assertTrue(app.reminder_due({}, 100))
        for key in ("do_not_prompt", "exported", "submitted"):
            self.assertFalse(app.reminder_due({key: True}, 100))
        self.assertFalse(app.reminder_due({"next_prompt": 101}, 100))
        self.assertTrue(app.reminder_due({"next_prompt": 100}, 100))
        self.assertTrue(app.reminder_due({"next_prompt": "bad"}, 100))
        self.assertTrue(app.reminder_due({"next_prompt": float("nan")}, 100))

    def test_csv(self):
        feedback = 'A comma, a "quote"\nand a newline'
        rows = list(csv.reader(io.StringIO(app.survey_csv("today", 5, feedback))))
        self.assertEqual(rows[1], ["1", "today", "5", feedback])
        self.assertEqual(len(rows[0]), 4)
        for value in ("=1+1", " +SUM(1)", "-1", "@cmd", "\ttext"):
            rows = list(csv.reader(io.StringIO(app.survey_csv("today", 3, value))))
            self.assertTrue(rows[1][3].startswith("'"))

    def test_reminder_reenable(self):
        for key in ("do_not_prompt", "exported", "submitted"):
            state = {key: True}
            self.assertFalse(app.reminders_enabled(state))
            state.update(app.reminder_preference(True, 100))
            self.assertTrue(app.reminders_enabled(state))
            self.assertFalse(app.reminder_due(state, 100))
            self.assertTrue(app.reminder_due(state, 100 + 7 * 86400))
            state.update(app.reminder_preference(False, 100))
            self.assertFalse(app.reminder_due(state, 100 + 14 * 86400))

    def test_state(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, XDG_STATE_HOME=directory):
            self.assertEqual(app.read_state("survey"), {})
            app.write_state("survey", do_not_prompt=True)
            app.write_state("survey", next_prompt=123)
            self.assertEqual(app.read_state("survey"), {"do_not_prompt": True, "next_prompt": 123})
            path = app.state_path("survey")
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            for invalid in ("[]", "null", "broken"):
                path.write_text(invalid)
                self.assertEqual(app.read_state("survey"), {})

    def test_urls(self):
        for value in ("", "javascript:alert(1)", "http://example.com", "https://user@example.com", "https://["):
            with patch.dict(os.environ, ABORA_SURVEY_URL=value):
                self.assertEqual(app.survey_url(), "")
        with patch.dict(os.environ, ABORA_SURVEY_URL="https://forms.gle/example"):
            self.assertEqual(app.survey_url(), "https://forms.gle/example")

    def test_progress(self):
        self.assertEqual(app.completed_lessons({"completed": [0, 0, 1, -1, 999, True, "2"]}), {0, 1})
        self.assertEqual(app.completed_lessons({"completed": None}), set())
        for _, _, _, choices, answer, _ in app.LESSONS:
            self.assertIn(answer, range(len(choices)))

    def test_resume(self):
        self.assertEqual(app.resume_lesson({}), 0)
        self.assertEqual(app.resume_lesson({"completed": [0, 1]}), 2)
        self.assertEqual(app.resume_lesson({"completed": [0, 2]}), 1)
        self.assertEqual(app.resume_lesson({"completed": list(range(len(app.LESSONS)))}), len(app.LESSONS) - 1)

    def test_notification_suppression_and_retry(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, XDG_STATE_HOME=directory):
            with patch.object(app.subprocess, "run") as send:
                send.return_value.returncode = 1
                self.assertEqual(app.notify(), 1)
                self.assertEqual(app.read_state("survey"), {})
                send.return_value.returncode = 0
                self.assertEqual(app.notify(), 0)
                self.assertEqual(send.call_count, 2)
                self.assertEqual(app.notify(), 0)
                self.assertEqual(send.call_count, 2)
                app.write_state("survey", next_prompt=0, do_not_prompt=True)
                self.assertEqual(app.notify(), 0)
                self.assertEqual(send.call_count, 2)


if __name__ == "__main__":
    unittest.main()
