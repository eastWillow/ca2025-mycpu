// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package board.litex

import chisel3._
import chisel3.stage.ChiselStage
import chisel3.util._
import riscv.Parameters
import riscv.core.verilator.CPU

class Ca2025MycpuIO extends Bundle {
  val interrupt = Input(UInt(Parameters.InterruptFlagWidth))

  // Read-only instruction AXI-Lite interface.
  val ibus_ar_valid = Output(Bool())
  val ibus_ar_ready = Input(Bool())
  val ibus_ar_addr  = Output(UInt(Parameters.AddrWidth))
  val ibus_ar_prot  = Output(UInt(3.W))
  val ibus_r_valid  = Input(Bool())
  val ibus_r_ready  = Output(Bool())
  val ibus_r_data   = Input(UInt(Parameters.DataWidth))
  val ibus_r_resp   = Input(UInt(2.W))

  // Read/write data AXI-Lite interface.
  val dbus_aw_valid = Output(Bool())
  val dbus_aw_ready = Input(Bool())
  val dbus_aw_addr  = Output(UInt(Parameters.AddrWidth))
  val dbus_aw_prot  = Output(UInt(3.W))
  val dbus_w_valid  = Output(Bool())
  val dbus_w_ready  = Input(Bool())
  val dbus_w_data   = Output(UInt(Parameters.DataWidth))
  val dbus_w_strb   = Output(UInt(Parameters.WordSize.W))
  val dbus_b_valid  = Input(Bool())
  val dbus_b_ready  = Output(Bool())
  val dbus_b_resp   = Input(UInt(2.W))
  val dbus_ar_valid = Output(Bool())
  val dbus_ar_ready = Input(Bool())
  val dbus_ar_addr  = Output(UInt(Parameters.AddrWidth))
  val dbus_ar_prot  = Output(UInt(3.W))
  val dbus_r_valid  = Input(Bool())
  val dbus_r_ready  = Output(Bool())
  val dbus_r_data   = Input(UInt(Parameters.DataWidth))
  val dbus_r_resp   = Input(UInt(2.W))
}

class Ca2025Mycpu extends Module {
  val io = IO(new Ca2025MycpuIO)

  val cpu = Module(new CPU)

  cpu.io.interrupt_flag := io.interrupt

  // ============================================================
  // [CA25: Exercise 22] Hide Educational Debug and Memory-Bundle Ports
  // ============================================================
  // Hint: The LiteX-facing top must not expose MyCPU's classroom debug
  // ports or the internal BusBundle. Tie unused CPU inputs to constants
  // so FIRRTL does not leave them undriven.
  //
  // Rules:
  // 1. debug_read_address and csr_debug_read_address := 0
  // 2. memory_bundle handshake inputs are unused (memory goes through AXI)
  //    Drive read_valid/write_valid/write_data_accepted/busy := false
  //    Drive granted := false, read_data := 0
  //
  // Do not add extra IO for these signals. LiteX only sees Ca2025MycpuIO.
  cpu.io.debug_read_address     := ?
  cpu.io.csr_debug_read_address := ?
  cpu.io.memory_bundle.read_data           := ?
  cpu.io.memory_bundle.read_valid          := ?
  cpu.io.memory_bundle.write_valid         := ?
  cpu.io.memory_bundle.write_data_accepted := ?
  cpu.io.memory_bundle.busy                := ?
  cpu.io.memory_bundle.granted             := ?

  // ============================================================
  // [CA25: Exercise 23] Instruction AXI-Lite (Read-Only)
  // ============================================================
  // Hint: Connect the CPU instruction AXI master to io.ibus_*. Fetch is
  // read-only: never accept writes on the instruction channel.
  //
  // Read address:  ARVALID/ARADDR/ARPROT are CPU outputs, ARREADY is a LiteX input
  // Read data:     RVALID/RDATA/RRESP are LiteX inputs, RREADY is a CPU output
  // Write channels: tie AWREADY, WREADY := false and BVALID := false, BRESP := 0
  //
  // Example: a fetch of the reset vector presents ARADDR = 0x00000000.
  io.ibus_ar_valid := ?
  cpu.io.inst_axi.read_address_channel.ARREADY := ?
  io.ibus_ar_addr := ?
  io.ibus_ar_prot := ?
  cpu.io.inst_axi.read_data_channel.RVALID := ?
  io.ibus_r_ready := ?
  cpu.io.inst_axi.read_data_channel.RDATA := ?
  cpu.io.inst_axi.read_data_channel.RRESP := ?

  cpu.io.inst_axi.write_address_channel.AWREADY := ?
  cpu.io.inst_axi.write_data_channel.WREADY     := ?
  cpu.io.inst_axi.write_response_channel.BVALID := ?
  cpu.io.inst_axi.write_response_channel.BRESP  := ?

  // ============================================================
  // [CA25: Exercise 24] Data AXI-Lite (Read and Write)
  // ============================================================
  // Hint: Connect the CPU data AXI master to io.dbus_*. BIOS UART, CSR
  // MMIO, and DRAM all travel on this bus.
  //
  // Write address/data/response and read address/data must all be wired.
  // Direction reminder: VALID/ADDR/DATA/STRB from CPU are outputs of this
  // top; READY/RESP/RDATA from LiteX are inputs.
  io.dbus_aw_valid := ?
  cpu.io.data_axi.write_address_channel.AWREADY := ?
  io.dbus_aw_addr := ?
  io.dbus_aw_prot := ?
  io.dbus_w_valid := ?
  cpu.io.data_axi.write_data_channel.WREADY := ?
  io.dbus_w_data := ?
  io.dbus_w_strb := ?
  cpu.io.data_axi.write_response_channel.BVALID := ?
  io.dbus_b_ready := ?
  cpu.io.data_axi.write_response_channel.BRESP := ?

  io.dbus_ar_valid := ?
  cpu.io.data_axi.read_address_channel.ARREADY := ?
  io.dbus_ar_addr := ?
  io.dbus_ar_prot := ?
  cpu.io.data_axi.read_data_channel.RVALID := ?
  io.dbus_r_ready := ?
  cpu.io.data_axi.read_data_channel.RDATA := ?
  cpu.io.data_axi.read_data_channel.RRESP := ?

  // Keep response bits in the public interface even if the CPU currently
  // treats them as completion-only.
  dontTouch(io.ibus_r_resp)
  dontTouch(io.dbus_b_resp)
  dontTouch(io.dbus_r_resp)
}

object GenerateCa2025Mycpu extends App {
  (new ChiselStage).emitVerilog(
    new Ca2025Mycpu(),
    Array("--target-dir", "5-litex-soc/build/litex")
  )
}
