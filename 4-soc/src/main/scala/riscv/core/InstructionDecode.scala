// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package riscv.core

import chisel3._
import chisel3.util._
import riscv.Parameters

class InstructionDecode extends Module {
  val io = IO(new Bundle {
    val instruction               = Input(UInt(Parameters.InstructionWidth))
    val instruction_address       = Input(UInt(Parameters.AddrWidth)) // if2id.io.output_instruction_address
    val reg1_data                 = Input(UInt(Parameters.DataWidth)) // regs.io.read_data1
    val reg2_data                 = Input(UInt(Parameters.DataWidth)) // regs.io.read_data2
    val forward_from_mem          = Input(UInt(Parameters.DataWidth)) // mem.io.forward_data
    val forward_from_wb           = Input(UInt(Parameters.DataWidth)) // wb.io.regs_write_data
    val reg1_forward              = Input(UInt(2.W))                  // forwarding.io.reg1_forward_id
    val reg2_forward              = Input(UInt(2.W))                  // forwarding.io.reg2_forward_id
    val interrupt_assert          = Input(Bool())                     // clint.io.id_interrupt_assert
    val interrupt_handler_address = Input(UInt(Parameters.AddrWidth)) // clint.io.id_interrupt_handler_address
    // Suppress branch decision when there's a RAW hazard with EX stage
    // Without this, branch would use wrong forwarded value from MEM (stale instruction)
    val branch_hazard = Input(Bool()) // ctrl.io.branch_hazard

    val regs_reg1_read_address = Output(UInt(Parameters.PhysicalRegisterAddrWidth))
    val regs_reg2_read_address = Output(UInt(Parameters.PhysicalRegisterAddrWidth))
    val ex_immediate           = Output(UInt(Parameters.DataWidth))
    val ex_aluop1_source       = Output(UInt(1.W))
    val ex_aluop2_source       = Output(UInt(1.W))
    val ex_memory_read_enable  = Output(Bool())
    val ex_memory_write_enable = Output(Bool())
    val ex_reg_write_source    = Output(UInt(2.W))
    val ex_reg_write_enable    = Output(Bool())
    val ex_reg_write_address   = Output(UInt(Parameters.PhysicalRegisterAddrWidth))
    val ex_csr_address         = Output(UInt(Parameters.CSRRegisterAddrWidth))
    val ex_csr_write_enable    = Output(Bool())
    val ctrl_jump_instruction  = Output(Bool())                     // ctrl.io.jump_instruction_id
    val if_jump_flag           = Output(Bool())                     // ctrl.io.jump_flag , inst_fetch.io.jump_flag_id
    val if_jump_address        = Output(UInt(Parameters.AddrWidth)) // inst_fetch.io.jump_address_id
  })
  val opcode = io.instruction(6, 0)
  val funct3 = io.instruction(14, 12)
  val funct7 = io.instruction(31, 25)
  val rd     = io.instruction(11, 7)
  val rs1    = io.instruction(19, 15)
  val rs2    = io.instruction(24, 20)

  // Track which operands are actually used to avoid false hazards/stalls on
  // encodings that reuse rs1/rs2 bits for immediates (JAL, CSR immediate, etc.).
  val csr_uses_uimm = opcode === Instructions.csr && (
    funct3 === InstructionsTypeCSR.csrrwi ||
      funct3 === InstructionsTypeCSR.csrrci ||
      funct3 === InstructionsTypeCSR.csrrsi
  )
  val uses_rs1 = (opcode === InstructionTypes.RM) || (opcode === InstructionTypes.I) ||
    (opcode === InstructionTypes.L) || (opcode === InstructionTypes.S) || (opcode === InstructionTypes.B) ||
    (opcode === Instructions.jalr) || (opcode === Instructions.csr && !csr_uses_uimm)
  val uses_rs2 = (opcode === InstructionTypes.RM) || (opcode === InstructionTypes.S) || (opcode === InstructionTypes.B)

  io.regs_reg1_read_address := Mux(uses_rs1, rs1, 0.U(Parameters.PhysicalRegisterAddrWidth))
  io.regs_reg2_read_address := Mux(uses_rs2, rs2, 0.U(Parameters.PhysicalRegisterAddrWidth))
  io.ex_immediate := MuxLookup(
    opcode,
    Cat(Fill(20, io.instruction(31)), io.instruction(31, 20))
  )(
    IndexedSeq(
      InstructionTypes.I -> Cat(Fill(21, io.instruction(31)), io.instruction(30, 20)),
      InstructionTypes.L -> Cat(Fill(21, io.instruction(31)), io.instruction(30, 20)),
      Instructions.jalr  -> Cat(Fill(21, io.instruction(31)), io.instruction(30, 20)),
      InstructionTypes.S -> Cat(Fill(21, io.instruction(31)), io.instruction(30, 25), io.instruction(11, 7)),
      InstructionTypes.B -> Cat(
        Fill(20, io.instruction(31)),
        io.instruction(7),
        io.instruction(30, 25),
        io.instruction(11, 8),
        0.U(1.W)
      ),
      Instructions.lui   -> Cat(io.instruction(31, 12), 0.U(12.W)),
      Instructions.auipc -> Cat(io.instruction(31, 12), 0.U(12.W)),
      Instructions.jal -> Cat(
        Fill(12, io.instruction(31)),
        io.instruction(19, 12),
        io.instruction(20),
        io.instruction(30, 21),
        0.U(1.W)
      )
    )
  )
  io.ex_aluop1_source := Mux(
    opcode === Instructions.auipc || opcode === InstructionTypes.B || opcode === Instructions.jal,
    ALUOp1Source.InstructionAddress,
    ALUOp1Source.Register
  )
  io.ex_aluop2_source := Mux(
    opcode === InstructionTypes.RM,
    ALUOp2Source.Register,
    ALUOp2Source.Immediate
  )
  io.ex_memory_read_enable  := opcode === InstructionTypes.L
  io.ex_memory_write_enable := opcode === InstructionTypes.S
  io.ex_reg_write_source := MuxLookup(
    opcode,
    RegWriteSource.ALUResult
  )(
    IndexedSeq(
      InstructionTypes.L -> RegWriteSource.Memory,
      Instructions.csr   -> RegWriteSource.CSR,
      Instructions.jal   -> RegWriteSource.NextInstructionAddress,
      Instructions.jalr  -> RegWriteSource.NextInstructionAddress
    )
  )
  io.ex_reg_write_enable := (opcode === InstructionTypes.RM) || (opcode === InstructionTypes.I) ||
    (opcode === InstructionTypes.L) || (opcode === Instructions.auipc) || (opcode === Instructions.lui) ||
    (opcode === Instructions.jal) || (opcode === Instructions.jalr) || (opcode === Instructions.csr)
  io.ex_reg_write_address := io.instruction(11, 7)
  io.ex_csr_address       := io.instruction(31, 20)
  io.ex_csr_write_enable := (opcode === Instructions.csr) && (
    funct3 === InstructionsTypeCSR.csrrw || funct3 === InstructionsTypeCSR.csrrwi ||
      funct3 === InstructionsTypeCSR.csrrs || funct3 === InstructionsTypeCSR.csrrsi ||
      funct3 === InstructionsTypeCSR.csrrc || funct3 === InstructionsTypeCSR.csrrci
  )

//  io.clint_jump_flag := io.interrupt_assert
//  io.clint_jump_address := io.interrupt_handler_address
  val reg1_data_forwarded = MuxLookup(io.reg1_forward, 0.U)(
    IndexedSeq(
      ForwardingType.NoForward      -> io.reg1_data,
      ForwardingType.ForwardFromWB  -> io.forward_from_wb,
      ForwardingType.ForwardFromMEM -> io.forward_from_mem
    )
  )
  val reg2_data_forwarded = MuxLookup(io.reg2_forward, 0.U)(
    IndexedSeq(
      ForwardingType.NoForward      -> io.reg2_data,
      ForwardingType.ForwardFromWB  -> io.forward_from_wb,
      ForwardingType.ForwardFromMEM -> io.forward_from_mem
    )
  )
  val is_jal  = opcode === Instructions.jal
  val is_jalr = opcode === Instructions.jalr
  val is_b    = opcode === InstructionTypes.B
  io.ctrl_jump_instruction := is_jal || is_jalr || is_b

  // Compare the forwarded operands directly. Operand-use masking stays on the
  // register-address outputs used by hazard detection and EX, so opcode decode
  // is not in series with the ID branch-compare → IF/ID flush loop.
  val compare_taken = MuxLookup(
    funct3,
    false.B
  )(
    IndexedSeq(
      InstructionsTypeB.beq  -> (reg1_data_forwarded === reg2_data_forwarded),
      InstructionsTypeB.bne  -> (reg1_data_forwarded =/= reg2_data_forwarded),
      InstructionsTypeB.blt  -> (reg1_data_forwarded.asSInt < reg2_data_forwarded.asSInt),
      InstructionsTypeB.bge  -> (reg1_data_forwarded.asSInt >= reg2_data_forwarded.asSInt),
      InstructionsTypeB.bltu -> (reg1_data_forwarded.asUInt < reg2_data_forwarded.asUInt),
      InstructionsTypeB.bgeu -> (reg1_data_forwarded.asUInt >= reg2_data_forwarded.asUInt)
    )
  )

  // Suppress branch/jump decision when there's a RAW hazard with EX stage
  // The branch_hazard signal indicates that the value needed for comparison is still
  // being computed in EX stage. Forwarding would get the wrong value from MEM stage
  // (which has a different instruction's result). We must NOT take the branch this cycle.
  // The pipeline will stall and re-evaluate next cycle when correct value is available.
  val branch_taken = !io.branch_hazard && (is_jal || is_jalr || (is_b && compare_taken))

  // Trap redirect is handled in InstructionFetch from CLINT, not through
  // these outputs. ORing interrupt_assert here put the handler mux on the
  // ID branch-compare → PC path of the interrupt-enabled variant.
  io.if_jump_flag := branch_taken

  val jalr_target = Cat((reg1_data_forwarded + io.ex_immediate)(Parameters.AddrBits - 1, 1), 0.U(1.W))

  io.if_jump_address := MuxLookup(opcode, 0.U)(
    IndexedSeq(
      InstructionTypes.B -> (io.instruction_address + io.ex_immediate),
      Instructions.jal   -> (io.instruction_address + io.ex_immediate),
      Instructions.jalr  -> jalr_target
    )
  )
}
