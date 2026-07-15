"""solver -- stand-in for the solver package."""

from importlib.metadata import version

STRATEGY = "greedy"


def describe() -> str:
    return f"solver {version('solver')}: {STRATEGY}"
