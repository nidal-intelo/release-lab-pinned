"""qb -- stand-in for query-builder."""

from importlib.metadata import version

ROUNDING = "rounds HALF-UP"

# --- behavior notes (identical across all version lines) ------------------
# Kept well clear of ROUNDING above so a hotfix editing the note below
# cherry-picks cleanly onto every line, whatever that line's rounding is.

CART_NOTE = "BUG: off-by-one on empty carts"


def describe() -> str:
    return f"qb {version('qb')}: {ROUNDING} ({CART_NOTE})"
