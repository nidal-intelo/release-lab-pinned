"""worker -- consumer that depends on qb only."""

import qb


def main() -> str:
    return qb.describe()
