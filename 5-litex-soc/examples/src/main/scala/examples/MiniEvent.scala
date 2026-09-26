// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

package examples

import chisel3._

/**
 * Tiny performance counter. Students sample the event before the adder.
 *
 * Naive version (given): a wide XOR-reduction (stand-in for "deep pipeline
 * event") enables the counter combinationally. That is Gate 1's path into
 * mhpmcounter enable (WNS -2.604 ns).
 *
 * Timing-aware version: `RegNext(event)` then increment. Totals stay
 * one-for-one, visibility is one cycle late. Exercise 30a.
 */
class MiniEvent extends Module {
  val io = IO(new Bundle {
    val sample = Input(UInt(32.W))
    val count  = Output(UInt(8.W))
  })

  val count = RegInit(0.U(8.W))

  // Stand-in for a late pipeline event: parity of a 32-bit word.
  val event = io.sample.xorR

  // ============================================================
  // [CA25: Mini-Event] Sample before the counter enable network
  // ============================================================
  // Naive (given): increment in the same cycle the event is computed.
  //
  // Change to:
  //   val sampled = RegNext(event, false.B)
  //   when(sampled) { count := count + 1.U }
  // Then MiniEventTest should pass.
  when(event) {
    count := count + 1.U
  }

  io.count := count
}
