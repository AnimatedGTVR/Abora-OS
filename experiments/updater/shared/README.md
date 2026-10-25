# Updater Downgrade Guard

All implementations must compare Abora version tags consistently, reject malformed or overflowing numeric components, and decide whether a requested update is actually a downgrade.

The command accepts current and candidate versions, prints `allow` or `block`, and returns a stable exit status. Every implementation must run the shared data-driven vectors in this directory and report unsupported cases as skipped rather than passed.
