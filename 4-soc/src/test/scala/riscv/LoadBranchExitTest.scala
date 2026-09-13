// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec

class LoadBranchExitTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior.of("PipelinedCPU load-to-branch loop exit")

  private def bodyIterations(program: String): BigInt = {
    var result = BigInt(-1)
    test(new TestTopModule(program)).withAnnotations(TestAnnotations.annos) { dut =>
      dut.clock.setTimeout(0)
      dut.io.regs_debug_read_address.poke(0.U)
      dut.io.csr_debug_read_address.poke(0.U)
      dut.io.interrupt_flag.poke(0.U)

      // The ROM loader fills 8192 words before the CPU starts. The program then
      // performs a SyncReadMem-backed LW immediately before its BGEU exit test.
      dut.clock.step(50000)

      dut.io.mem_debug_read_address.poke(0x100.U)
      dut.clock.step(2)
      result = dut.io.mem_debug_read_data.peekInt()
    }
    result
  }

  it should "execute exactly five body iterations with no gap after each counter load" in {
    assert(bodyIterations("load_branch_exit.asmbin") == 5)
  }

  it should "execute exactly five body iterations with one independent instruction before BGEU" in {
    assert(bodyIterations("load_branch_exit_1nop.asmbin") == 5)
  }

  it should "execute exactly five body iterations with two independent instructions before BGEU" in {
    assert(bodyIterations("load_branch_exit_2nop.asmbin") == 5)
  }
}
