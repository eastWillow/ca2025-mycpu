// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package examples

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec

class MiniFlushTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior.of("MiniFlush")

  it should "report invalid after flush, without rewriting the payload to NOP" in {
    test(new MiniFlush) { dut =>
      dut.io.stall.poke(false.B)
      dut.io.flush.poke(false.B)
      dut.io.instruction.poke(0x00a00513.U) // addi a0, x0, 10
      dut.clock.step()
      dut.io.out_valid.expect(true.B)
      dut.io.out_inst.expect(0x00a00513.U)

      dut.io.flush.poke(true.B)
      dut.clock.step()
      dut.io.flush.poke(false.B)

      dut.io.out_valid.expect(false.B)
      // Timing-aware kill: the 32-bit register is not sync-reset to NOP.
      dut.io.out_inst.expect(0x00a00513.U)
    }
  }
}

class MiniRedirectTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior.of("MiniRedirect")

  it should "update PC one cycle after jump, not in the compare cycle" in {
    test(new MiniRedirect) { dut =>
      dut.io.jump.poke(false.B)
      dut.io.target.poke(0.U)
      dut.clock.step()
      val before = dut.io.pc.peekInt()

      dut.io.jump.poke(true.B)
      dut.io.target.poke(0x40.U)
      dut.clock.step()
      // Registered redirect: still sequential after the compare cycle.
      dut.io.pc.expect((before + 4).U)

      dut.io.jump.poke(false.B)
      dut.clock.step()
      dut.io.pc.expect(0x40.U)
    }
  }
}

class MiniEventTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior.of("MiniEvent")

  it should "increment one cycle after the event, and still count once" in {
    test(new MiniEvent) { dut =>
      dut.io.sample.poke(0.U) // xorR = 0
      dut.clock.step()
      dut.io.count.expect(0.U)

      dut.io.sample.poke(1.U) // xorR = 1 for one cycle
      dut.clock.step()
      dut.io.count.expect(0.U) // sampled, not combinational

      dut.io.sample.poke(0.U)
      dut.clock.step()
      dut.io.count.expect(1.U)
    }
  }
}
