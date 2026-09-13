// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv.core

import chisel3._
import chisel3.util.MuxLookup
import riscv.Parameters

object InterruptStatus {
  val None   = 0x0.U(8.W)
  val Timer0 = 0x1.U(8.W)
  val Ret    = 0xff.U(8.W)
}

// Core Local Interrupt Controller
// CSRDirectAccessBundle is defined in CSR.scala
//
// LiteX interrupt model: interrupt_flag is a flat 32-bit vector where each
// bit corresponds to a peripheral (e.g. bit 0 = UART). The BIOS enables
// individual interrupts by setting the matching bit in the mie CSR, and
// reads pending interrupts from the mip CSR. This CLINT takes an interrupt
// whenever (interrupt_flag & mie) != 0 and the global MIE bit in mstatus
// is set.
class CLINT extends Module {
  val io = IO(new Bundle {
    val interrupt_flag = Input(UInt(Parameters.InterruptFlagWidth))

    val instruction_id         = Input(UInt(Parameters.InstructionWidth))
    val instruction_address_id = Input(UInt(Parameters.AddrWidth))

    val stall_flag             = Input(Bool())

    val id_interrupt_handler_address = Output(UInt(Parameters.AddrWidth))
    val id_interrupt_assert          = Output(Bool())

    val csr_bundle = new CSRDirectAccessBundle
  })
  val interrupt_enable_global = io.csr_bundle.mstatus(3) // MIE bit (global enable)

  // Expose interrupt_flag as mip so software can read pending interrupts
  io.csr_bundle.mip := io.interrupt_flag

  // Check if any enabled interrupt source is pending.
  // LiteX uses matching bit positions in interrupt_flag and mie.
  val effective_interrupts = io.interrupt_flag & io.csr_bundle.mie
  val any_interrupt_pending = effective_interrupts =/= 0.U

  // RISC-V requires mepc to identify the interrupted instruction or the
  // instruction that raised the exception. The pipeline therefore supplies
  // the PC paired with instruction_id at the ID boundary, never a newer fetch PC.
  val instruction_address = io.instruction_address_id
  // Trap entry: MIE (bit 3) -> MPIE (bit 7), then clear MIE
  val mstatus_disable_interrupt =
    io.csr_bundle.mstatus(31, 8) ## io.csr_bundle.mstatus(3) ## io.csr_bundle.mstatus(6, 4) ## 0.U(1.W) ## io.csr_bundle
      .mstatus(2, 0)
  // mret: MPIE (bit 7) -> MIE (bit 3), then set MPIE to 1
  val mstatus_recover_interrupt =
    io.csr_bundle.mstatus(31, 8) ## 1.U(1.W) ## io.csr_bundle.mstatus(6, 4) ## io.csr_bundle.mstatus(7) ## io.csr_bundle
      .mstatus(2, 0)

  when(!io.stall_flag && (io.instruction_id === InstructionsEnv.ecall || io.instruction_id === InstructionsEnv.ebreak)) {
    io.csr_bundle.mstatus_write_data := mstatus_disable_interrupt
    io.csr_bundle.mepc_write_data    := instruction_address
    io.csr_bundle.mcause_write_data := MuxLookup(
      io.instruction_id,
      10.U
    )(
      IndexedSeq(
        InstructionsEnv.ecall  -> 11.U,
        InstructionsEnv.ebreak -> 3.U,
      )
    )
    io.csr_bundle.direct_write_enable := true.B
    io.id_interrupt_assert            := true.B
    io.id_interrupt_handler_address   := io.csr_bundle.mtvec
  }.elsewhen(!io.stall_flag && any_interrupt_pending && interrupt_enable_global) {
    io.csr_bundle.mstatus_write_data  := mstatus_disable_interrupt
    io.csr_bundle.mepc_write_data     := instruction_address
    // Report as machine external interrupt (mcause = 0x8000000b)
    io.csr_bundle.mcause_write_data   := 0x8000000bL.U
    io.csr_bundle.direct_write_enable := true.B
    io.id_interrupt_assert            := true.B
    io.id_interrupt_handler_address   := io.csr_bundle.mtvec
  }.elsewhen(!io.stall_flag && io.instruction_id === InstructionsRet.mret) {
    io.csr_bundle.mstatus_write_data  := mstatus_recover_interrupt
    io.csr_bundle.mepc_write_data     := io.csr_bundle.mepc
    io.csr_bundle.mcause_write_data   := io.csr_bundle.mcause
    io.csr_bundle.direct_write_enable := true.B
    io.id_interrupt_assert            := true.B
    io.id_interrupt_handler_address   := io.csr_bundle.mepc
  }.otherwise {
    io.csr_bundle.mstatus_write_data  := io.csr_bundle.mstatus
    io.csr_bundle.mepc_write_data     := io.csr_bundle.mepc
    io.csr_bundle.mcause_write_data   := io.csr_bundle.mcause
    io.csr_bundle.direct_write_enable := false.B
    io.id_interrupt_assert            := false.B
    io.id_interrupt_handler_address   := 0.U
  }
}
