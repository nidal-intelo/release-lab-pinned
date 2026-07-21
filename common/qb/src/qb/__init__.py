"""qb -- stand-in for query-builder."""

from importlib.metadata import version

ROUNDING = (
    "rounds HALF-EVEN (banker's rounding) + audit log + query cache + tweak again"
)

CART_NOTE = "empty carts handled correctly"

TRACE = "query trace marker: enabled"


def describe() -> str:
    return f"qb {version('qb')}: {ROUNDING} ({CART_NOTE})"
