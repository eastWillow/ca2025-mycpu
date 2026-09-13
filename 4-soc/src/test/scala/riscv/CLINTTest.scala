// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec
import riscv.core.CLINT
import riscv.core.InstructionsEnv
import riscv.core.InstructionsRet

class CLINTTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior.of("Core Local Interrupt Controller")

  private def initialize(
      dut: CLINT,
      interrupt: BigInt = 0,
      instruction: BigInt = 0,
      instructionAddress: BigInt = 0x1000,
      mie: BigInt = 0,
      mstatus: BigInt = 0x8,
      stall: Boolean = false,
  ): Unit = {
    dut.io.interrupt_flag.poke(interrupt.U)
    dut.io.instruction_id.poke(instruction.U)
    dut.io.instruction_address_id.poke(instructionAddress.U)
    dut.io.stall_flag.poke(stall.B)
    dut.io.csr_bundle.mstatus.poke(mstatus.U)
    dut.io.csr_bundle.mie.poke(mie.U)
    dut.io.csr_bundle.mtvec.poke(0x100.U)
    dut.io.csr_bundle.mepc.poke(0x200.U)
    dut.io.csr_bundle.mcause.poke(0.U)
  }

  it should "remain idle when no trap is pending" in {
    test(new CLINT).withAnnotations(TestAnnotations.annos) { dut =>
      initialize(dut)
      dut.io.id_interrupt_assert.expect(false.B)
      dut.io.csr_bundle.direct_write_enable.expect(false.B)
      dut.io.csr_bundle.mip.expect(0.U)
    }
  }

  it should "expose and take an enabled LiteX interrupt-vector bit" in {
    test(new CLINT).withAnnotations(TestAnnotations.annos) { dut =>
      val irq = BigInt(1) << 3
      initialize(dut, interrupt = irq, mie = irq)
      dut.io.csr_bundle.mip.expect(irq.U)
      dut.io.id_interrupt_assert.expect(true.B)
      dut.io.id_interrupt_handler_address.expect(0x100.U)
      dut.io.csr_bundle.direct_write_enable.expect(true.B)
      dut.io.csr_bundle.mcause_write_data.expect(0x8000000bL.U)
      dut.io.csr_bundle.mepc_write_data.expect(0x1000.U)
    }
  }

  it should "leave a pending LiteX interrupt masked when its vector bit is disabled" in {
    test(new CLINT).withAnnotations(TestAnnotations.annos) { dut =>
      initialize(dut, interrupt = 1, mie = 0)
      dut.io.csr_bundle.mip.expect(1.U)
      dut.io.id_interrupt_assert.expect(false.B)
      dut.io.csr_bundle.direct_write_enable.expect(false.B)
    }
  }

  it should "not take an interrupt while global MIE is clear" in {
    test(new CLINT).withAnnotations(TestAnnotations.annos) { dut =>
      initialize(dut, interrupt = 1, mie = 1, mstatus = 0)
      dut.io.id_interrupt_assert.expect(false.B)
    }
  }

  it should "record the ECALL instruction address in mepc" in {
    test(new CLINT).withAnnotations(TestAnnotations.annos) { dut =>
      initialize(dut, instruction = InstructionsEnv.ecall.litValue, instructionAddress = 0x1234)
      dut.io.id_interrupt_assert.expect(true.B)
      dut.io.id_interrupt_handler_address.expect(0x100.U)
      dut.io.csr_bundle.mcause_write_data.expect(11.U)
      dut.io.csr_bundle.mepc_write_data.expect(0x1234.U)
    }
  }

  it should "record the EBREAK instruction address in mepc" in {
    test(new CLINT).withAnnotations(TestAnnotations.annos) { dut =>
      initialize(dut, instruction = InstructionsEnv.ebreak.litValue, instructionAddress = 0x2348)
      dut.io.id_interrupt_assert.expect(true.B)
      dut.io.csr_bundle.mcause_write_data.expect(3.U)
      dut.io.csr_bundle.mepc_write_data.expect(0x2348.U)
    }
  }

  it should "return to mepc on MRET" in {
    test(new CLINT).withAnnotations(TestAnnotations.annos) { dut =>
      initialize(dut, instruction = InstructionsRet.mret.litValue)
      dut.io.csr_bundle.mepc.poke(0x3000.U)
      dut.io.id_interrupt_assert.expect(true.B)
      dut.io.id_interrupt_handler_address.expect(0x3000.U)
      dut.io.csr_bundle.direct_write_enable.expect(true.B)
    }
  }

  it should "defer synchronous and asynchronous traps while stalled" in {
    test(new CLINT).withAnnotations(TestAnnotations.annos) { dut =>
      initialize(dut, instruction = InstructionsEnv.ecall.litValue, stall = true)
      dut.io.id_interrupt_assert.expect(false.B)
      dut.io.csr_bundle.direct_write_enable.expect(false.B)

      initialize(dut, interrupt = 1, mie = 1, stall = true)
      dut.io.id_interrupt_assert.expect(false.B)
      dut.io.csr_bundle.direct_write_enable.expect(false.B)
    }
  }

  it should "move MIE to MPIE when taking an interrupt" in {
    test(new CLINT).withAnnotations(TestAnnotations.annos) { dut =>
      initialize(dut, interrupt = 1, mie = 1, mstatus = 0x8)
      val nextMstatus = dut.io.csr_bundle.mstatus_write_data.peekInt()
      assert((nextMstatus & 0x8) == 0, f"MIE should clear: 0x$nextMstatus%x")
      assert((nextMstatus & 0x80) != 0, f"MPIE should capture MIE: 0x$nextMstatus%x")
    }
  }

  it should "prioritize a synchronous exception over a pending interrupt" in {
    test(new CLINT).withAnnotations(TestAnnotations.annos) { dut =>
      initialize(dut, interrupt = 1, instruction = InstructionsEnv.ecall.litValue, mie = 1)
      dut.io.csr_bundle.mcause_write_data.expect(11.U)
    }
  }
}
