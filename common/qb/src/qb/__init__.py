"""qb -- stand-in for query-builder."""

from importlib.metadata import version

ROUNDING = "rounds HALF-EVEN (banker's rounding) [dry-run]"

CART_NOTE = "BUG: off-by-one on empty carts"


def describe() -> str:
    return f"qb {version('qb')}: {ROUNDING} ({CART_NOTE})"
