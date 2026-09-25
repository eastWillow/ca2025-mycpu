# MyCPU RISC-V Labs (ca2025)

Progressive RISC-V processor labs in Chisel, one lab directory per architectural step, all sharing one verification infrastructure. The repo is a teaching artifact: students complete the numbered lab exercises and prove each gate green.

## Language

### Projects

**Minimal** (0-minimal):
A 5-instruction CPU (AUIPC, ADDI, LW, SW, JALR) demonstrating JIT self-modifying code; no ECALL, register state only visible via debug read ports.
_Avoid_: "demo CPU", "jit project"

**Single-Cycle** (1-single-cycle):
The full RV32I single-cycle core with Harvard memory; the reference architecture all later labs extend.
_Avoid_: "baseline", "first lab"

**MMIO-Trap** (2-mmio-trap):
Single-Cycle plus Zicsr, machine-mode traps, CLINT timer/software interrupts, and machine-mode MMIO devices (UART, VGA).
_Avoid_: "trap lab", "interrupt project"

**Pipeline** (3-pipeline):
The four pipelined variants of the core: ThreeStage, FiveStageStall, FiveStageForward, FiveStageFinal (the default).
_Avoid_: "pipelined core" (ambiguous which variant)

**SoC** (4-soc):
The complete System-on-Chip: AXI4-Lite bus, VGA/UART/CLINT peripherals, advanced branch prediction, interactive shell.
_Avoid_: "top", "final project"

**Common** (common/):
The only shared sbt module (Parameters, RegisterFile, ALU of the single-cycle family); Pipeline intentionally does not depend on it.
_Avoid_: "library", "shared code" (per-lab core copies are not shared)

### Exercises and Gates

**Exercise** (CA25: Exercise N):
A numbered, intentionally incomplete code region marked by a banner comment and `?` tokens; completed when every `?` is replaced with working code while the banner stays.
_Avoid_: "TODOs" (some TODO lines remain as hints), "bugs" (holes are assignments, not defects)

**Gate**:
The per-project proof that a lab is done: `make test` (that lab's ChiselTest suite) fully green. Gating is strict: labs proceed 0 → 4 in order, next lab starts only after the current gate is green.
_Avoid_: "build", "verification" (verification also includes compliance and simulation)

**Compliance**:
RISCOF architectural verification against the rv32emu reference model: 41 tests for Single-Cycle, 119 (RV32I + Zicsr + PMP) for MMIO-Trap and Pipeline; requires the RISC-V GNU toolchain (`$RISCV`).
_Avoid_: "specs", "arch tests"

### Pipelining Variants (3-pipeline)

**ThreeStage**:
The IF-EX-WB baseline that stalls on every hazard; the learning variant.

**FiveStageStall**:
IF-ID-EX-MEM-WB with stall-only hazard resolution; no forwarding.

**FiveStageForward**:
FiveStageStall plus EX/MEM → EX forwarding.

**FiveStageFinal**:
FiveStageForward plus ID-stage comparison and early branch resolution; the default variant of the Pipeline project.

### Traps (2-mmio-trap)

**Trap**:
Entry to the trap handler via `mtvec` with `mepc`/`mcause`/`mstatus` updated atomically; MRET is the only return path.
_Avoid_: "interrupt" alone (an interrupt is one cause of a trap; the mechanism is the trap)
