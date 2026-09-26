// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package examples

import chisel3._

/**
 * Tiny IF/ID stand-in. Students change how `flush` kills a fetch.
 *
 * Naive version (given): write NOP into the 32-bit instruction register.
 * That is the fanout that became Gate 1's IF/ID SR-pin path.
 *
 * Timing-aware version: keep the payload, clear a 1-bit valid. Decode
 * treats valid=0 as NOP. See 5-litex-soc Exercise 27.
 */
class MiniFlush extends Module {
  val io = IO(new Bundle {
    val stall       = Input(Bool())
    val flush       = Input(Bool())
    val instruction = Input(UInt(32.W))
    val out_valid   = Output(Bool())
    val out_inst    = Output(UInt(32.W))
  })

  val nop = 0x00000013.U(32.W)

  val valid = RegInit(false.B)
  val inst  = RegInit(nop)

  when(!io.stall) {
    valid := true.B
    inst  := io.instruction
  }

  // ============================================================
  // [CA25: Mini-Flush] Kill a fetch without a 32-bit sync reset
  // ============================================================
  // Naive (given): flush writes NOP into `inst`. This compiles and the
  // pipeline sees a NOP, but it models the wide IF/ID SR fanout.
  //
  // Change to:
  //   when(io.flush) { valid := false.B }
  //   // do not assign inst on flush
  // Then MiniFlushTest should pass.
  when(io.flush) {
    inst  := nop // TODO: stop writing the payload
    valid := false.B
  }

  io.out_valid := valid
  io.out_inst  := inst
}
