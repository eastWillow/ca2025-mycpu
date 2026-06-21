// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package board.fpga

import bus.AXI4LiteSlave
import bus.AXI4LiteSlaveBundle
import chisel3._
import chisel3.stage.ChiselStage
import riscv.core.fpga.CPU
import riscv.Parameters

class Top extends Module {
  val io = IO(new Bundle {
    val signal_interrupt = Input(Bool())

    // Instruction interface (external ROM in testbench)
    val instruction_req     = Output(UInt(Parameters.AddrWidth))
    val instruction_address = Input(UInt(Parameters.AddrWidth))
    val instruction         = Input(UInt(Parameters.InstructionWidth))
    val instruction_valid   = Input(Bool())

    val mem_slave = new AXI4LiteSlaveBundle(Parameters.AddrBits, Parameters.DataBits)

    val cpu_debug_read_address     = Input(UInt(Parameters.PhysicalRegisterAddrWidth))
    val cpu_debug_read_data        = Output(UInt(Parameters.DataWidth))
    val cpu_csr_debug_read_address = Input(UInt(Parameters.CSRRegisterAddrWidth))
    val cpu_csr_debug_read_data    = Output(UInt(Parameters.DataWidth))
  })

  // AXI4-Lite memory model provided by Verilator C++ harness (sim.cpp)
  val mem_slave = Module(new AXI4LiteSlave(Parameters.AddrBits, Parameters.DataBits))
  io.mem_slave <> mem_slave.io.bundle

  val cpu = Module(new CPU)

  // Instruction fetch (external ROM in testbench)
  io.instruction_req         := cpu.io.instruction_req
  cpu.io.instruction_address := io.instruction_address
  cpu.io.instruction         := io.instruction
  cpu.io.instruction_valid   := io.instruction_valid

  // Terminate unused memory_bundle inputs with explicit values
  cpu.io.memory_bundle.read_data           := 0.U
  cpu.io.memory_bundle.read_valid          := false.B
  cpu.io.memory_bundle.write_valid         := false.B
  cpu.io.memory_bundle.write_data_accepted := false.B
  cpu.io.memory_bundle.busy                := false.B
  cpu.io.memory_bundle.granted             := false.B

  // Connect CPU data bus directly to mem_slave
  mem_slave.io.channels <> cpu.io.axi4_channels

  // Interrupt
  cpu.io.interrupt_flag := io.signal_interrupt

  // Debug interfaces
  cpu.io.debug_read_address     := io.cpu_debug_read_address
  io.cpu_debug_read_data        := cpu.io.debug_read_data
  cpu.io.csr_debug_read_address := io.cpu_csr_debug_read_address
  io.cpu_csr_debug_read_data    := cpu.io.csr_debug_read_data
}

object VerilogGenerator extends App {
  (new ChiselStage).emitVerilog(
    new Top(),
    Array("--target-dir", "4-soc/verilog/fpga")
  )
}
