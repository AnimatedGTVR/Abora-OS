# Survey and Learn Nix

Launch **Abora Survey** or **Learn Nix / NixOS** from the applications menu.
Their commands are `abora-survey` and `abora-learn`.

The survey exports a local CSV containing only usage duration, rating and
optional feedback, with a schema version. Import it into LibreOffice Calc,
Excel or Google Sheets. Export does not upload or submit anything. No device
inventory, usernames, logs or identifiers are collected. Review free-text
answers for personal information before sharing the exported file.

The default online survey is https://forms.gle/V6aoBimEZYRt2nUb7.
To replace it with another HTTPS survey, configure:

```nix
abora.community.surveyUrl = "https://forms.gle/YOUR_FORM";
```

Set this option to an empty string to hide the online survey link.

The online link opens in the browser without attaching local answers.
Opening a link is not treated as a submission. Users can confirm submission
in the app to stop reminders.

Installed systems schedule a notification after 30 minutes in a graphical
session, then check daily. Notifications are limited to once a week per user.
The survey offers a reminder switch and a one-week snooze; successful CSV
export also stops reminders. Live media does not schedule reminders.
Turning reminders back on, or choosing "Remind me in a week", explicitly
re-enables them even after an export or confirmed submission. The next reminder
is delayed by a week, not sent immediately.
Administrators can set `abora.community.reminders = false;`.

State is private to the user in `$XDG_STATE_HOME/abora`, defaulting to
`~/.local/state/abora`. The course has six lessons with questions, saved
completion and links to the [Nix language tutorial](https://nix.dev/tutorials/nix-language)
and [NixOS manual](https://nixos.org/manual/nixos/stable/).

Course completion offers a native-NixOS migration review checklist. It does
not remove ANIX, generate a replacement configuration, activate a system or
claim migration is safe without reviewing the machine's existing configuration.
