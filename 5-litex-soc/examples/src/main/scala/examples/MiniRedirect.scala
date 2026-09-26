// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package examples

import chisel3._

/**
 * Tiny PC with an ID-stage jump. Students delay the redirect.
 *
 * Naive version (given): `pc` muxes the combinational jump in the same
 * cycle as the compare. That is Gate 4's instruction → RF → CARRY4 → pc.D.
 *
 * Timing-aware version: take `RegNext(jump)` / `RegNext(target)`. Branch
 * still resolves in "ID"; PC updates one cycle later. Exercise 28.
 */
class MiniRedirect extends Module {
  val io = IO(new Bundle {
    val jump   = Input(Bool())
    val target = Input(UInt(32.W))
    val pc     = Output(UInt(32.W))
  })

  val pc = RegInit(0.U(32.W))

  // ============================================================
  // [CA25: Mini-Redirect] Do not feed the compare into pc.D
  // ============================================================
  // Naive (given): same-cycle redirect.
  //
  // Change to:
  //   val prev_jump   = RegNext(io.jump, false.B)
  //   val prev_target = RegNext(io.target, 0.U)
  //   pc := Mux(prev_jump, prev_target, pc + 4.U)
  // Then MiniRedirectTest should pass.
  pc := Mux(io.jump, io.target, pc + 4.U)

  io.pc := pc
}
