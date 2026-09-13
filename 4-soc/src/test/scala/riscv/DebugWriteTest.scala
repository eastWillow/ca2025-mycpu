// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec

// Debug test using built-in uart.asmbin from resources
class DebugWriteTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior.of("Debug Write Test")

  it should "execute uart test and verify memory writes" in {
    // Use uart.asmbin which is already in src/main/resources/
    test(new TestTopModule("uart.asmbin")).withAnnotations(TestAnnotations.annos) { dut =>
      dut.clock.setTimeout(0)

      // Run uart test - needs time to execute
      dut.clock.step(50000)

      // The loader writes the image at the CPU's reset entry.  Do not use the
      // former 0x1000 educational-platform offset: LiteX resets this CPU at 0.
      // uart.asmbin begins with little-endian bytes 97 11 00 00.
      dut.io.mem_debug_read_address.poke(Parameters.EntryAddress)
      dut.clock.step(2) // SyncReadMem debug port has one-cycle read latency.
      val inst0 = dut.io.mem_debug_read_data.peekInt()
      assert(inst0 == BigInt("00001197", 16),
        f"Loader wrote 0x$inst0%08x at the reset entry, expected uart.asmbin word 0x00001197")
    }
  }
}
