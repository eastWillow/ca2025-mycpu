// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv.core

import chisel3._
import riscv.core.PipelineRegister
import riscv.Parameters

/**
 * IF/ID Pipeline Register: Instruction Fetch to Instruction Decode boundary.
 *
 * Captures and buffers the fetched instruction along with its address and all
 * branch prediction metadata (BTB, RAS, IndirectBTB). This register is the
 * first pipeline boundary and controls instruction flow into the decode stage.
 *
 * Stall behavior: When stalled, holds current instruction for re-execution.
 * Flush behavior: On flush (branch misprediction), outputs NOP to cancel
 *                 the wrong-path instruction.
 *
 * Branch prediction signals flow alongside the instruction so the ID stage
 * can compare predicted vs actual branch outcomes and trigger corrections.
 */
class IF2ID extends Module {
  val io = IO(new Bundle {
    val stall                 = Input(Bool())
    val flush                 = Input(Bool())
    val instruction           = Input(UInt(Parameters.InstructionWidth))
    val instruction_address   = Input(UInt(Parameters.AddrWidth))
    val interrupt_flag        = Input(UInt(Parameters.InterruptFlagWidth))
    val btb_predicted_taken   = Input(Bool())                     // BTB prediction from IF stage
    val btb_predicted_target  = Input(UInt(Parameters.AddrWidth)) // BTB predicted target
    val ras_predicted_valid   = Input(Bool())                     // RAS prediction valid from IF stage
    val ras_predicted_target  = Input(UInt(Parameters.AddrWidth)) // RAS predicted return address
    val ibtb_predicted_valid  = Input(Bool())                     // IndirectBTB prediction valid from IF
    val ibtb_predicted_target = Input(UInt(Parameters.AddrWidth)) // IndirectBTB predicted target

    val output_valid                 = Output(Bool())
    val output_instruction           = Output(UInt(Parameters.DataWidth))
    val output_instruction_address   = Output(UInt(Parameters.AddrWidth))
    val output_interrupt_flag        = Output(UInt(Parameters.InterruptFlagWidth))
    val output_btb_predicted_taken   = Output(Bool())                     // BTB prediction to ID stage
    val output_btb_predicted_target  = Output(UInt(Parameters.AddrWidth)) // BTB target to ID stage
    val output_ras_predicted_valid   = Output(Bool())                     // RAS prediction to ID stage
    val output_ras_predicted_target  = Output(UInt(Parameters.AddrWidth)) // RAS target to ID stage
    val output_ibtb_predicted_valid  = Output(Bool())                     // IndirectBTB prediction to ID
    val output_ibtb_predicted_target = Output(UInt(Parameters.AddrWidth)) // IndirectBTB target to ID
  })

  // Flush only this valid bit. Resetting the 32-bit instruction and prediction
  // payloads through their synchronous R/S pins is the 100 MHz critical path:
  // ID branch compare fans out to every IF/ID flip-flop. A killed fetch is a
  // bubble because ID sees a NOP while valid is low; the held payloads are
  // ignored and overwritten on the next capture.
  val valid = Module(new PipelineRegister(width = 1, defaultValue = 0.U))
  valid.io.in     := 1.U
  valid.io.stall  := io.stall
  valid.io.flush  := io.flush
  io.output_valid := valid.io.out(0)

  // Hold payloads only on a true stall. Including flush here put the ID
  // branch decision on every IF/ID clock-enable. A flushed fetch is ignored
  // because valid is cleared; the next capture overwrites the payload.
  val payload_stall = io.stall

  val instruction = Module(new PipelineRegister(defaultValue = InstructionsNop.nop))
  instruction.io.in     := io.instruction
  instruction.io.stall  := payload_stall
  instruction.io.flush  := false.B
  io.output_instruction := instruction.io.out

  val instruction_address = Module(new PipelineRegister(defaultValue = Parameters.EntryAddress))
  instruction_address.io.in     := io.instruction_address
  instruction_address.io.stall  := payload_stall
  instruction_address.io.flush  := false.B
  io.output_instruction_address := instruction_address.io.out

  val interrupt_flag = Module(new PipelineRegister(Parameters.InterruptFlagBits))
  interrupt_flag.io.in     := io.interrupt_flag
  interrupt_flag.io.stall  := payload_stall
  interrupt_flag.io.flush  := false.B
  io.output_interrupt_flag := interrupt_flag.io.out

  val btb_predicted_taken = Module(new PipelineRegister(1))
  btb_predicted_taken.io.in     := io.btb_predicted_taken
  btb_predicted_taken.io.stall  := payload_stall
  btb_predicted_taken.io.flush  := false.B
  io.output_btb_predicted_taken := btb_predicted_taken.io.out.asBool

  val btb_predicted_target = Module(new PipelineRegister(Parameters.AddrBits))
  btb_predicted_target.io.in     := io.btb_predicted_target
  btb_predicted_target.io.stall  := payload_stall
  btb_predicted_target.io.flush  := false.B
  io.output_btb_predicted_target := btb_predicted_target.io.out

  val ras_predicted_valid = Module(new PipelineRegister(1))
  ras_predicted_valid.io.in     := io.ras_predicted_valid
  ras_predicted_valid.io.stall  := payload_stall
  ras_predicted_valid.io.flush  := false.B
  io.output_ras_predicted_valid := ras_predicted_valid.io.out.asBool

  val ras_predicted_target = Module(new PipelineRegister(Parameters.AddrBits))
  ras_predicted_target.io.in     := io.ras_predicted_target
  ras_predicted_target.io.stall  := payload_stall
  ras_predicted_target.io.flush  := false.B
  io.output_ras_predicted_target := ras_predicted_target.io.out

  val ibtb_predicted_valid = Module(new PipelineRegister(1))
  ibtb_predicted_valid.io.in     := io.ibtb_predicted_valid
  ibtb_predicted_valid.io.stall  := payload_stall
  ibtb_predicted_valid.io.flush  := false.B
  io.output_ibtb_predicted_valid := ibtb_predicted_valid.io.out.asBool

  val ibtb_predicted_target = Module(new PipelineRegister(Parameters.AddrBits))
  ibtb_predicted_target.io.in     := io.ibtb_predicted_target
  ibtb_predicted_target.io.stall  := payload_stall
  ibtb_predicted_target.io.flush  := false.B
  io.output_ibtb_predicted_target := ibtb_predicted_target.io.out
}
