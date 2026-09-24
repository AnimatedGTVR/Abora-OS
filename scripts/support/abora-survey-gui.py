#!/usr/bin/env python3
"""Compatibility entry point for the survey application."""
from pathlib import Path
import runpy

if __name__ == "__main__":
    directory = Path(__file__).resolve().parent
    source = directory / "abora-community.py"
    if not source.exists():
        source = directory / "community.py"
    runpy.run_path(str(source), run_name="__main__")
