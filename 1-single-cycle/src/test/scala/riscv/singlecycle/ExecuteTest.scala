// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv.singlecycle

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec
import riscv.core.ALUOp1Source
import riscv.core.ALUOp2Source
import riscv.core.Execute
import riscv.core.InstructionTypes
import riscv.TestAnnotations

class ExecuteTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior.of("Execute")
  it should "execute ALU operations and branch logic correctly" in {
    test(new Execute).withAnnotations(TestAnnotations.annos) { c =>
      // add test
      c.io.instruction.poke(0x001101b3L.U) // x3 =  x2 + x1
      // c.io.immediate.poke(0.U)
      // c.io.aluop1_source.poke(0.U)
      // c.io.aluop2_source.poke(0.U)

      var x = 0
      for (x <- 0 to 100) {
        val op1    = scala.util.Random.nextInt(429496729)
        val op2    = scala.util.Random.nextInt(429496729)
        val result = op1 + op2
        val addr   = scala.util.Random.nextInt(32)

        c.io.reg1_data.poke(op1.U)
        c.io.reg2_data.poke(op2.U)

        c.clock.step()
        c.io.mem_alu_result.expect(result.U)
        c.io.if_jump_flag.expect(0.U)
      }

      // beq test
      c.io.instruction.poke(0x00208163L.U) // pc + 2 if x1 === x2
      c.io.instruction_address.poke(2.U)
      c.io.immediate.poke(2.U)
      c.io.aluop1_source.poke(1.U)
      c.io.aluop2_source.poke(1.U)
      c.clock.step()

      // equ
      c.io.reg1_data.poke(9.U)
      c.io.reg2_data.poke(9.U)
      c.clock.step() // add
      c.io.if_jump_flag.expect(1.U)
      c.io.if_jump_address.expect(4.U)

      // not equ
      c.io.reg1_data.poke(9.U)
      c.io.reg2_data.poke(19.U)
      c.clock.step()
      c.io.if_jump_flag.expect(0.U)
      c.io.if_jump_address.expect(4.U)

      // addi test
      c.io.instruction.poke(0xfe010113L.U) // addi    sp(x2),sp(x2),-32
      //c.io.instruction_address.poke(2.U)
      c.io.reg1_data.poke(0.U)
      // c.io.reg2_data.poke(2.U)
      c.io.immediate.poke(0xFFFFFFE0L.U(32.W))
      c.io.aluop1_source.poke(ALUOp1Source.Register)
      c.io.aluop2_source.poke(ALUOp2Source.Immediate)
      c.clock.step()

      c.io.mem_alu_result.expect(0xFFFFFFE0L.U(32.W))
      c.io.if_jump_flag.expect(0.U)
      // c.io.if_jump_address.expect(0.U)

      // bgeu test
      c.io.instruction.poke(0x0062f863L.U) // bgeu x5, x6, 16
      c.io.instruction_address.poke(2.U)
      c.io.immediate.poke(16.U)
      c.io.aluop1_source.poke(ALUOp1Source.InstructionAddress)
      c.io.aluop2_source.poke(ALUOp2Source.Immediate)
      c.clock.step()

      // rs1 > rs2
      c.io.reg1_data.poke(10.U)
      c.io.reg2_data.poke(9.U)
      c.clock.step() // add
      c.io.if_jump_flag.expect(1.U)
      c.io.if_jump_address.expect(18.U)

      // rs1 === rs2
      c.io.reg1_data.poke(9.U)
      c.io.reg2_data.poke(9.U)
      c.clock.step() // add
      c.io.if_jump_flag.expect(1.U)
      c.io.if_jump_address.expect(18.U)

      // rs1 < rs2
      c.io.reg1_data.poke(9.U)
      c.io.reg2_data.poke(10.U)
      c.clock.step() // add
      c.io.if_jump_flag.expect(0.U)
      c.io.if_jump_address.expect(18.U)

      // bne test
      c.io.instruction.poke(0x00f71663L.U) // bne x14, x15, 12
      c.io.instruction_address.poke(2.U)
      c.io.immediate.poke(18.U)
      c.io.aluop1_source.poke(ALUOp1Source.InstructionAddress)
      c.io.aluop2_source.poke(ALUOp2Source.Immediate)
      c.clock.step()

      // rs1 === rs2
      c.io.reg1_data.poke(9.U)
      c.io.reg2_data.poke(9.U)
      c.clock.step() // add
      c.io.if_jump_flag.expect(0.U)
      c.io.if_jump_address.expect(20.U)

      // rs1 =/= rs2
      c.io.reg1_data.poke(8.U)
      c.io.reg2_data.poke(9.U)
      c.clock.step() // add
      c.io.if_jump_flag.expect(1.U)
      c.io.if_jump_address.expect(20.U)
    }
  }
}
