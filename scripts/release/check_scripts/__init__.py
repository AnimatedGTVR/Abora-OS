"""Abora's repository check suite, run by scripts/check-scripts.py (`make check`).

Groups, in run order:
  setup           builds the C# tools the suites need, MINT's Go checks, syntax,
                  executable bits, required files, git tracking, flake evaluation
  static_checks   content checks over the repo (generated data: real grep argv)
  static_manual   content checks that need more than a grep chain
  gui             tests of the Python GUIs
  release         tests of the Python release tooling
  suites          the Bash behaviour-test suites in scripts/*/tests/*.test.sh
"""
