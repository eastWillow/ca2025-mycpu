// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package board.verilator

import bus.AXI4LiteSlave
import bus.AXI4LiteSlaveBundle
import chisel3._
import chisel3.stage.ChiselStage
import riscv.core.verilator.CPU
import riscv.Parameters

class Top extends Module {
  val io = IO(new Bundle {
    val signal_interrupt = Input(Bool())

    val mem_slave = new AXI4LiteSlaveBundle(Parameters.AddrBits, Parameters.DataBits)

    val cpu_debug_read_address     = Input(UInt(Parameters.PhysicalRegisterAddrWidth))
    val cpu_debug_read_data        = Output(UInt(Parameters.DataWidth))
    val cpu_csr_debug_read_address = Input(UInt(Parameters.CSRRegisterAddrWidth))
    val cpu_csr_debug_read_data    = Output(UInt(Parameters.DataWidth))
  })

  val cpu = Module(new CPU)
  val mem_slave = Module(new AXI4LiteSlave(Parameters.AddrBits, Parameters.DataBits))
  io.mem_slave <> mem_slave.io.bundle

  val arbiter = Module(new bus.DualMasterAXIArbiter(Parameters.AddrBits, Parameters.DataBits))
  
  arbiter.io.inst_master <> cpu.io.inst_axi
  arbiter.io.data_master <> cpu.io.data_axi
  arbiter.io.slave <> mem_slave.io.channels

  // Terminate unused memory_bundle inputs with explicit values
  cpu.io.memory_bundle.read_data           := 0.U
  cpu.io.memory_bundle.read_valid          := false.B
  cpu.io.memory_bundle.write_valid         := false.B
  cpu.io.memory_bundle.write_data_accepted := false.B
  cpu.io.memory_bundle.busy                := false.B
  cpu.io.memory_bundle.granted             := false.B

  // Interrupts
  cpu.io.interrupt_flag := io.signal_interrupt

  // Debug
  cpu.io.debug_read_address := io.cpu_debug_read_address
  io.cpu_debug_read_data := cpu.io.debug_read_data
  cpu.io.csr_debug_read_address := io.cpu_csr_debug_read_address
  io.cpu_csr_debug_read_data := cpu.io.csr_debug_read_data
}

object VerilogGenerator extends App {
  (new ChiselStage).emitVerilog(
    new Top(),
    Array("--target-dir", "4-soc/verilog/verilator")
  )
}
