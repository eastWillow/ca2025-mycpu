# Mini examples: modify, then re-run

These examples compile **even while** `5-litex-soc` still has `?` in the CPU.
Each starts from a naive implementation that matches a real 100 MHz failure.
Change the marked block until the test turns green.

Lecture: [`../docs/04-vs-05-wns-fpga.md`](../docs/04-vs-05-wns-fpga.md).

## Run

From `5-litex-soc/`:

```bash
make examples
```

Or from the MyCPU root:

```bash
sbt "project litexExamples" test
python3 5-litex-soc/examples/scripts/uart_oracle.py \
  5-litex-soc/examples/fixtures/gate_banner.txt
```

Given code **fails** those tests on purpose. That is the exercise.

## Mini-Flush — wide NOP reset vs valid bit

- File: `src/main/scala/examples/MiniFlush.scala`
- Models: Gate 1 IF/ID instruction SR fanout (path B in the lecture)
- Naive: `flush` writes `0x00000013` into the 32-bit register
- Your change: only clear `valid`; leave `inst` alone
- Check: `MiniFlushTest` expects `out_valid=0` and `out_inst` still the old instruction

Try also: print or peek `out_inst` before/after flush. The naive version hides the old instruction; the timing-aware version does not need to.

## Mini-Redirect — combinational jump vs registered PC

- File: `src/main/scala/examples/MiniRedirect.scala`
- Models: Gate 4 instruction → compare → `pc.D` (path C)
- Naive: `pc := Mux(io.jump, io.target, pc+4)` in the compare cycle
- Your change: `RegNext(jump)` / `RegNext(target)` then mux
- Check: after the compare cycle PC is still sequential; the target appears one cycle later

This is **not** moving branch resolution to EX. The jump is still decided by `io.jump`; only the PC flop is later.

## Mini-Event — combinational counter enable vs sample

- File: `src/main/scala/examples/MiniEvent.scala`
- Models: Gate 1 CSR `mhpmcounter` enable (path A)
- Naive: `when(event) { count := count + 1 }`
- Your change: `when(RegNext(event)) { ... }`
- Check: a one-cycle event increments on the **following** cycle, still exactly once

`event` is `xorR` of a 32-bit sample, a stand-in for a late pipeline net.

## Mini-UART — CSI prompt

- File: `scripts/uart_oracle.py`
- Fixture: `fixtures/gate_banner.txt` (coloured `litex>` like the Arty BIOS)
- Naive: regex never matches CSI, so `litex>` is not found in the raw text
- Your change: strip `\x1b[[0-9;]*m` before counting prompts
- Check: exit code 0 and `BIOS_PROOF True`

Do not “fix” this by searching for `mlitex`. Real transcripts also have other CSI sequences.

## Timing-report drill (no tools)

Open `fixtures/sample_timing_path.txt` and answer the five questions in the comments.
Numbers are simplified from the first Gate 1 report (WNS −2.604 ns, 15 logic levels, fanout 5654).

## What these minis are not

- Not a substitute for Exercise 22–30 on the real CPU
- Not a Vivado project; they will not print WNS
- Not permission to redesign the five-stage pipeline
