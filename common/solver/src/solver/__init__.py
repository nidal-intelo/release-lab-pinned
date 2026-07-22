"""solver -- stand-in for the solver package."""

from importlib.metadata import version

STRATEGY = "greedy + tie-break"


def describe() -> str:
    return f"solver {version('solver')}: {STRATEGY}"
