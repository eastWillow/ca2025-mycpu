# 5-litex-soc: LiteX CPU Boundary for MyCPU

Adapt the five-stage RV32I + Zicsr core so LiteX can instantiate it as
`ca2025_mycpu`. This lab does not rebuild VGA, UART MMIO, or the educational
SoC top. Those belong to [4-soc](../4-soc/). Here the public surface is only
clock, reset, a 32-bit interrupt vector, and instruction/data AXI-Lite.

> Code fragments marked `CA25: Exercise` are intentionally incomplete.
> Fill every `?` so `make test` and `make contract` pass. The complete
> reference lives in `4-soc/` (not a student answer key during the lab).
>
> Start with the lecture and minis if `4-soc` vs LiteX / WNS is unclear:
> [docs/04-vs-05-wns-fpga.md](docs/04-vs-05-wns-fpga.md),
> [examples/README.md](examples/README.md). `make examples` does not need
> the CPU holes filled.

## Features

- CPU: five-stage MyCPU with ID-stage branch resolution (do not redesign)
- Reset: LiteX integrated ROM at `0x00000000`
- Interrupts: flat 32-bit LiteX vector (`mip`/`mie` bit-for-bit)
- Bus: instruction AXI-Lite is read-only; data AXI-Lite is read/write
- Timing-aware control: valid-bit IF/ID flush, registered PC redirect,
  sampled CSR events — still a five-stage pipeline

## Architecture

```
LiteX SoC
  clk / reset / interrupt[31:0]
  ibus AXI-Lite (read-only fetch)
  dbus AXI-Lite (loads, stores, MMIO)
        │
        ▼
Ca2025Mycpu (this lab's top)
  └─ verilator.CPU
       ├─ InstructionFetch  (trap mux + registered ID jump)
       ├─ IF2ID             (flush valid bit only)
       ├─ InstructionDecode (branch/JALR flag, no trap OR)
       ├─ CLINT             (LiteX vector, ID-stage mepc)
       └─ CSR               (sampled HPM event enables)
```

## Build & Test

From `5-litex-soc/`:

```bash
make examples    # Mini flush/redirect/event + UART oracle (starts red)
make test        # ChiselTest: CLINT, JAL link, load-to-branch, LiteX top
make litex-rtl   # Generate 5-litex-soc/build/litex/Ca2025Mycpu.v
make contract    # Verilog port contract (clock/reset/irq/AXI-Lite only)
```

From the repository root:

```bash
sbt "project litexSoc" test
```

Java 8 is the documented Scala/Chisel runtime for this tree.

## CA25: Lab Exercises

Eight exercises marked with `CA25: Exercise` comments. They continue the
numbering from `3-pipeline` (Exercise 21). Each is one LiteX seam, not a
pipeline redesign.

### Exercise 22: Hide Educational Ports (`board/litex/Ca2025Mycpu.scala`)

- Task: Tie off debug register/CSR addresses and unused `memory_bundle` inputs
- Difficulty: Beginner
- Key Concepts: LiteX-facing top, FIRRTL undriven inputs
- Validation: `LiteXTopTest`, `make contract`
- Rule: Do not add debug IO to `Ca2025MycpuIO`

### Exercise 23: Instruction AXI-Lite (`board/litex/Ca2025Mycpu.scala`)

- Task: Wire `ibus` read channels; reject instruction-side writes
- Difficulty: Beginner to Intermediate
- Key Concepts: AXI-Lite handshake direction, read-only fetch
- Validation: `LiteXTopTest`, `make contract`
- Write-side ties: `AWREADY=0`, `WREADY=0`, `BVALID=0`

### Exercise 24: Data AXI-Lite (`board/litex/Ca2025Mycpu.scala`)

- Task: Wire `dbus` write and read channels for BIOS MMIO and DRAM
- Difficulty: Intermediate
- Key Concepts: AW/W/B and AR/R channel pairing
- Validation: `LiteXTopTest`, `JalLinkStoreTest`, `LoadBranchExitTest`

### Exercise 25: LiteX Interrupt Vector (`CLINT.scala`)

- Task: Expose `interrupt_flag` as `mip`; pending = `(flag & mie) != 0`
- Difficulty: Intermediate
- Key Concepts: LiteX UART/timer bits, `mstatus.MIE`
- Validation: `CLINTTest`
- Do not decode the old 8-bit `InterruptStatus.Timer0` classroom encoding

### Exercise 26: `mepc` at the ID Instruction (`CLINT.scala`)

- Task: Write `mepc` from `instruction_address_id` on trap/interrupt
- Difficulty: Beginner
- Key Concepts: RISC-V `mepc` is the interrupted instruction, not IF+4
- Validation: `CLINTTest` ECALL/EBREAK/interrupt cases

### Exercise 27: Valid-Bit IF/ID Flush (`IF2ID.scala`)

- Task: Flush only the 1-bit valid register; payload `flush` stays false
- Difficulty: Intermediate
- Key Concepts: 100 MHz fanout, NOP via `valid=0` rather than sync-reset of 32-bit instruction
- Validation: `LoadBranchExitTest`, `JalLinkStoreTest`
- Out of scope: moving branch resolution out of ID

### Exercise 28: Registered PC Redirect (`verilator/InstructionFetch.scala`)

- Task: Take the ID jump from `prev_jump_flag` / `prev_jump_addr`, not the combinational compare
- Difficulty: Intermediate
- Key Concepts: cut instruction → RF → compare → `pc.D`; keep IF trap mux combinatorial
- Validation: `LoadBranchExitTest`, `JalLinkStoreTest`
- Trap entry still uses `io.interrupt_assert` in the same `MuxCase`

### Exercise 29: ID Jump Flag Without Trap OR (`InstructionDecode.scala`)

- Task: `if_jump_flag` is `branch_taken` only; do not OR `interrupt_assert`
- Difficulty: Beginner
- Key Concepts: trap redirect already has a dedicated IF mux; duplicating it lengthens the IRQ path
- Validation: `CLINTTest` plus pipeline tests still boot branches

### Exercise 30: Sample CSR Events (`CSR.scala`) and Two-Cycle IF Flush (`PipelinedCPU.scala`)

- Task: `RegNext` every HPM event before the counter enable; hold IF/ID flush one extra cycle
- Difficulty: Intermediate
- Key Concepts: instrumentation must not sit on the control-critical path; delayed PC redirect needs a matching bubble
- Validation: `LoadBranchExitTest`, `JalLinkStoreTest`
- Sampling may delay the counter by one cycle; totals stay one-for-one

## What This Lab Is Not

- Not a VGA/UART educational SoC (see `4-soc`)
- Not a five-stage redesign (for example moving all branch resolution to EX)
- Not LiteX Python packaging (`pythondata-cpu-ca2025-mycpu` is a later integration step)
- Not Arty `--flash` (hardware proof is a system gate, not a Chisel fill-in)

## Learning Path

```
4-soc          → AXI4-Lite educational SoC, VGA, UART, predictors
5-litex-soc    → Same core, LiteX-facing top and interrupt/timing seams
  ├─ Ca2025Mycpu IO        → What LiteX is allowed to see
  ├─ CLINT vector / mepc   → What the BIOS interrupt model requires
  └─ IF/ID + PC redirect   → What 100 MHz DDR3 on Arty requires
```
