// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv.core

import chisel3._
import chisel3.util._
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

  // ============================================================
  // [CA25: Exercise 25] LiteX Interrupt Vector → mip / pending
  // ============================================================
  // Hint: LiteX interrupt_flag is a flat 32-bit vector (bit 0 = UART, bit 1 =
  // timer0, ...). Software enables sources in mie and reads pending bits from
  // mip. Matching bit positions: pending = interrupt_flag & mie.
  //
  // Do not map the old classroom encoding InterruptStatus.Timer0 (0x1 as a
  // code, not a bit vector).
  //
  // Example: UART pending and enabled → interrupt_flag=1, mie=1, take trap
  // when mstatus.MIE=1.
  io.csr_bundle.mip := ?
  val effective_interrupts  = ?
  val any_interrupt_pending = effective_interrupts =/= 0.U

  // ============================================================
  // [CA25: Exercise 26] mepc Is the ID-Stage Instruction Address
  // ============================================================
  // Hint: RISC-V mepc identifies the interrupted instruction or the
  // instruction that raised the exception. Use instruction_address_id from
  // IF/ID, never a newer fetch PC and never PC+4.
  //
  // Example: ECALL at 0x1234 → mepc_write_data = 0x1234, mcause = 11.
  val instruction_address = ?
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
