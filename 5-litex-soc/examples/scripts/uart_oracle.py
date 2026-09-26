#!/usr/bin/env python3
"""[CA25: Mini-UART] Strip CSI and decide whether a transcript is BIOS proof.

Naive matchers search for the literal bytes `litex>` and fail on the real
Arty banner, which is ESC[92;1mlitexESC[0m>. Fix `stripped()` and run:

    python3 scripts/uart_oracle.py fixtures/gate_banner.txt
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# ============================================================
# [CA25: Mini-UART] CSI must be stripped before matching litex>
# ============================================================
# Naive (given): no ANSI strip. The fixture contains colour codes, so
# "litex>" is not a contiguous substring of the raw bytes.
#
# Change ANSI to r"\x1b\[[0-9;]*m" and strip before counting prompts.
ANSI = re.compile(r"never-matches")


def stripped(text: str) -> str:
    return ANSI.sub("", text)


def is_bios_proof(raw: str) -> bool:
    text = stripped(raw)
    if text.count("litex>") < 2:
        return False
    if "help" not in text:
        return False
    if "LiteX BIOS, available commands:" not in text:
        return False
    first = text.find("litex>")
    help_at = text.find("LiteX BIOS, available commands:")
    second = text.find("litex>", help_at)
    return first != -1 and help_at != -1 and second != -1 and first < help_at < second


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: uart_oracle.py <transcript.txt>", file=sys.stderr)
        return 2
    raw = Path(argv[1]).read_text(encoding="utf-8")
    ok = is_bios_proof(raw)
    print("STRIPPED_PROMPTS", stripped(raw).count("litex>"))
    print("HAS_HELP_HEADER", "LiteX BIOS, available commands:" in stripped(raw))
    print("BIOS_PROOF", ok)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
