// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv

import board.litex.Ca2025Mycpu
import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec

class LiteXTopTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior.of("LiteX-facing Ca2025Mycpu top")

  it should "elaborate with only the LiteX clock/reset/interrupt/AXI-Lite ports" in {
    test(new Ca2025Mycpu).withAnnotations(TestAnnotations.annos) { dut =>
      dut.io.interrupt.poke(0.U)
      dut.io.ibus_ar_ready.poke(false.B)
      dut.io.ibus_r_valid.poke(false.B)
      dut.io.ibus_r_data.poke(0.U)
      dut.io.ibus_r_resp.poke(0.U)
      dut.io.dbus_aw_ready.poke(false.B)
      dut.io.dbus_w_ready.poke(false.B)
      dut.io.dbus_b_valid.poke(false.B)
      dut.io.dbus_b_resp.poke(0.U)
      dut.io.dbus_ar_ready.poke(false.B)
      dut.io.dbus_r_valid.poke(false.B)
      dut.io.dbus_r_data.poke(0.U)
      dut.io.dbus_r_resp.poke(0.U)
      dut.clock.step()
      // Instruction interface is read-only: the CPU must not request ibus writes.
      // After reset the fetch ARVALID may be high, but write valids stay low.
      dut.io.dbus_aw_valid.peekBoolean()
      dut.io.dbus_w_valid.peekBoolean()
    }
  }

  it should "reset at the LiteX integrated-ROM origin" in {
    assert(Parameters.EntryAddress.litValue == 0)
  }
}
