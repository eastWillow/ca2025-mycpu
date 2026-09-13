#!/usr/bin/env python3

import re
import unittest

from pathlib import Path


SOC_DIR = Path(__file__).resolve().parents[1]
RTL_FILE = SOC_DIR / "build" / "litex" / "Ca2025Mycpu.v"

EXPECTED_PORTS = {
    "clock": ("input", 1),
    "reset": ("input", 1),
    "io_interrupt": ("input", 32),
    "io_ibus_ar_valid": ("output", 1),
    "io_ibus_ar_ready": ("input", 1),
    "io_ibus_ar_addr": ("output", 32),
    "io_ibus_ar_prot": ("output", 3),
    "io_ibus_r_valid": ("input", 1),
    "io_ibus_r_ready": ("output", 1),
    "io_ibus_r_data": ("input", 32),
    "io_ibus_r_resp": ("input", 2),
    "io_dbus_aw_valid": ("output", 1),
    "io_dbus_aw_ready": ("input", 1),
    "io_dbus_aw_addr": ("output", 32),
    "io_dbus_aw_prot": ("output", 3),
    "io_dbus_w_valid": ("output", 1),
    "io_dbus_w_ready": ("input", 1),
    "io_dbus_w_data": ("output", 32),
    "io_dbus_w_strb": ("output", 4),
    "io_dbus_b_valid": ("input", 1),
    "io_dbus_b_ready": ("output", 1),
    "io_dbus_b_resp": ("input", 2),
    "io_dbus_ar_valid": ("output", 1),
    "io_dbus_ar_ready": ("input", 1),
    "io_dbus_ar_addr": ("output", 32),
    "io_dbus_ar_prot": ("output", 3),
    "io_dbus_r_valid": ("input", 1),
    "io_dbus_r_ready": ("output", 1),
    "io_dbus_r_data": ("input", 32),
    "io_dbus_r_resp": ("input", 2),
}


def parse_ansi_ports(verilog):
    match = re.search(r"\bmodule\s+Ca2025Mycpu\s*\((.*?)\n\);", verilog, re.DOTALL)
    if match is None:
        return None

    ports = {}
    declaration = re.compile(
        r"\b(input|output)\s+(?:\[(\d+):(\d+)\]\s+)?([A-Za-z_][A-Za-z0-9_]*)"
    )
    for direction, high, low, name in declaration.findall(match.group(1)):
        width = int(high) - int(low) + 1 if high else 1
        ports[name] = (direction, width)
    return ports


class TestLiteXTopContract(unittest.TestCase):
    def test_generated_top_exposes_only_the_litex_contract(self):
        self.assertTrue(RTL_FILE.is_file(), f"missing generated RTL: {RTL_FILE}")
        ports = parse_ansi_ports(RTL_FILE.read_text(encoding="utf-8"))
        self.assertIsNotNone(ports, "missing Verilog module Ca2025Mycpu")
        self.assertEqual(ports, EXPECTED_PORTS)


if __name__ == "__main__":
    unittest.main()

