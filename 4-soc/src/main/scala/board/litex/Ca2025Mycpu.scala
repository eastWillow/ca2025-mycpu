// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package board.litex

import chisel3._
import chisel3.stage.ChiselStage
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

  // The LiteX boundary intentionally hides educational debug/bypass ports.
  cpu.io.debug_read_address     := 0.U
  cpu.io.csr_debug_read_address := 0.U
  cpu.io.memory_bundle.read_data           := 0.U
  cpu.io.memory_bundle.read_valid          := false.B
  cpu.io.memory_bundle.write_valid         := false.B
  cpu.io.memory_bundle.write_data_accepted := false.B
  cpu.io.memory_bundle.busy                := false.B
  cpu.io.memory_bundle.granted             := false.B

  // Instruction AXI-Lite read channels.
  io.ibus_ar_valid := cpu.io.inst_axi.read_address_channel.ARVALID
  cpu.io.inst_axi.read_address_channel.ARREADY := io.ibus_ar_ready
  io.ibus_ar_addr := cpu.io.inst_axi.read_address_channel.ARADDR
  io.ibus_ar_prot := cpu.io.inst_axi.read_address_channel.ARPROT
  cpu.io.inst_axi.read_data_channel.RVALID := io.ibus_r_valid
  io.ibus_r_ready := cpu.io.inst_axi.read_data_channel.RREADY
  cpu.io.inst_axi.read_data_channel.RDATA := io.ibus_r_data
  cpu.io.inst_axi.read_data_channel.RRESP := io.ibus_r_resp

  // The instruction interface is read-only.
  cpu.io.inst_axi.write_address_channel.AWREADY := false.B
  cpu.io.inst_axi.write_data_channel.WREADY     := false.B
  cpu.io.inst_axi.write_response_channel.BVALID := false.B
  cpu.io.inst_axi.write_response_channel.BRESP  := 0.U

  // Data AXI-Lite write channels.
  io.dbus_aw_valid := cpu.io.data_axi.write_address_channel.AWVALID
  cpu.io.data_axi.write_address_channel.AWREADY := io.dbus_aw_ready
  io.dbus_aw_addr := cpu.io.data_axi.write_address_channel.AWADDR
  io.dbus_aw_prot := cpu.io.data_axi.write_address_channel.AWPROT
  io.dbus_w_valid := cpu.io.data_axi.write_data_channel.WVALID
  cpu.io.data_axi.write_data_channel.WREADY := io.dbus_w_ready
  io.dbus_w_data := cpu.io.data_axi.write_data_channel.WDATA
  io.dbus_w_strb := cpu.io.data_axi.write_data_channel.WSTRB
  cpu.io.data_axi.write_response_channel.BVALID := io.dbus_b_valid
  io.dbus_b_ready := cpu.io.data_axi.write_response_channel.BREADY
  cpu.io.data_axi.write_response_channel.BRESP := io.dbus_b_resp

  // Data AXI-Lite read channels.
  io.dbus_ar_valid := cpu.io.data_axi.read_address_channel.ARVALID
  cpu.io.data_axi.read_address_channel.ARREADY := io.dbus_ar_ready
  io.dbus_ar_addr := cpu.io.data_axi.read_address_channel.ARADDR
  io.dbus_ar_prot := cpu.io.data_axi.read_address_channel.ARPROT
  cpu.io.data_axi.read_data_channel.RVALID := io.dbus_r_valid
  io.dbus_r_ready := cpu.io.data_axi.read_data_channel.RREADY
  cpu.io.data_axi.read_data_channel.RDATA := io.dbus_r_data
  cpu.io.data_axi.read_data_channel.RRESP := io.dbus_r_resp

  // The current CPU treats AXI-Lite responses as completion-only. Keep the
  // response inputs in the stable public interface for protocol compatibility.
  dontTouch(io.ibus_r_resp)
  dontTouch(io.dbus_b_resp)
  dontTouch(io.dbus_r_resp)
}

object GenerateCa2025Mycpu extends App {
  (new ChiselStage).emitVerilog(
    new Ca2025Mycpu(),
    Array("--target-dir", "4-soc/build/litex")
  )
}

