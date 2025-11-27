// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv.singlecycle


import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec
import riscv.core._
import riscv.core.MemoryAccess
import riscv.TestAnnotations
import riscv.Parameters

class MemoryAccessTest extends AnyFlatSpec with ChiselScalatestTester {
    behavior.of("MemoryAccess")
    it should "correctly load memory value into register" in {
        test(new MemoryAccess).withAnnotations(TestAnnotations.annos) { c =>
            c.io.funct3.poke(InstructionsTypeL.lw)
            c.io.alu_result.poke(0)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(0)
            c.io.wb_memory_read_data.expect(0x1234F678L.U(32.W))

            c.io.funct3.poke(InstructionsTypeL.lhu)
            c.io.alu_result.poke(0)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(0)
            c.io.wb_memory_read_data.expect(0xF678.U(32.W))

            // not supported yet
            // c.io.funct3.poke(InstructionsTypeL.lhu)
            // c.io.alu_result.poke(1)
            // c.io.memory_read_enable.poke(1)
            // c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            // c.clock.step()
            // c.io.memory_bundle.write_enable.expect(false.B)
            // c.io.memory_bundle.write_data.expect(0.U)
            // c.io.memory_bundle.address.expect(1)
            // c.io.wb_memory_read_data.expect(0x34F6.U(32.W))

            c.io.funct3.poke(InstructionsTypeL.lhu)
            c.io.alu_result.poke(2)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(2)
            c.io.wb_memory_read_data.expect(0x1234.U(32.W))

            // not supported yet
            // c.io.funct3.poke(InstructionsTypeL.lhu)
            // c.io.alu_result.poke(3)
            // c.io.memory_read_enable.poke(1)
            // c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            // c.clock.step()
            // c.io.memory_bundle.write_enable.expect(false.B)
            // c.io.memory_bundle.write_data.expect(0.U)
            // c.io.memory_bundle.address.expect(3)
            // c.io.wb_memory_read_data.expect(0x34F6.U(32.W))

            c.io.funct3.poke(InstructionsTypeL.lbu)
            c.io.alu_result.poke(0)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(0)
            c.io.wb_memory_read_data.expect(0x78.U(32.W))

            c.io.funct3.poke(InstructionsTypeL.lbu)
            c.io.alu_result.poke(1)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(1)
            c.io.wb_memory_read_data.expect(0xF6.U(32.W))

            c.io.funct3.poke(InstructionsTypeL.lbu)
            c.io.alu_result.poke(2)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(2)
            c.io.wb_memory_read_data.expect(0x34.U(32.W))

            c.io.funct3.poke(InstructionsTypeL.lbu)
            c.io.alu_result.poke(3)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(3)
            c.io.wb_memory_read_data.expect(0x12.U(32.W))

            c.io.funct3.poke(InstructionsTypeL.lb)
            c.io.alu_result.poke(0)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(0)
            c.io.wb_memory_read_data.expect(0x78.U(32.W))

            c.io.funct3.poke(InstructionsTypeL.lb)
            c.io.alu_result.poke(1)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(1)
            c.io.wb_memory_read_data.expect(0xFFFFFFF6L.U(32.W))

            c.io.funct3.poke(InstructionsTypeL.lb)
            c.io.alu_result.poke(2)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x1234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(2)
            c.io.wb_memory_read_data.expect(0x34.U(32.W))

            c.io.funct3.poke(InstructionsTypeL.lb)
            c.io.alu_result.poke(3)
            c.io.memory_read_enable.poke(1)
            c.io.memory_bundle.read_data.poke(0x9234F678L.U(32.W))
            c.clock.step()
            c.io.memory_bundle.write_enable.expect(false.B)
            c.io.memory_bundle.write_data.expect(0.U)
            c.io.memory_bundle.address.expect(3)
            c.io.wb_memory_read_data.expect(0xFFFFFF92L.U(32.W))
        }
    }

    it should "correctly save register value into memory" in {
        test(new MemoryAccess).withAnnotations(TestAnnotations.annos) { c =>
            c.io.alu_result.poke(1)
            c.io.reg2_data.poke(1)
            c.clock.step()
        }
    }
}