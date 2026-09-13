// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec

class JalLinkStoreTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior.of("PipelinedCPU JAL link writeback")

  it should "store PC+4 from jal ra, not the jump target, through a later sw ra" in {
    test(new TestTopModule("jal_link_store.asmbin")).withAnnotations(TestAnnotations.annos) { dut =>
      dut.clock.setTimeout(0)
      dut.io.regs_debug_read_address.poke(0.U)
      dut.io.csr_debug_read_address.poke(0.U)
      dut.io.interrupt_flag.poke(0.U)
      dut.clock.step(20000)

      dut.io.mem_debug_read_address.poke(0x100.U)
      dut.clock.step(2)
      val stored = dut.io.mem_debug_read_data.peekInt()
      // jal at 0x0 with target 0x10 must write ra=0x4. If MEM forwarded the ALU
      // jump target instead of waiting for WB PC+4, the store would be 0x10.
      assert(stored == 4, f"sw ra stored 0x$stored%08x, expected link 0x00000004")
    }
  }
}
