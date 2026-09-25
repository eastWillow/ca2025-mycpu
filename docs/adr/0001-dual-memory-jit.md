# Dual Harvard memories with mirrored writes for JIT self-modifying code

`0-minimal` must run `jit.asmbin`, a program that writes new code and then executes it. We decided to implement memory as two separate block RAMs — `imem` for instruction fetch and `dmem` for loads/stores — sharing one address space, where every store writes **both** memories in the same cycle.

**Considered options**: a single unified memory (one BRAM, simplest) cannot serve fetch and load/store concurrently and makes self-modifying code awkward; a unified memory with a fetch-port bypass is tool-dependent. Mirroring writes is the simplest design that supports JIT on a Harvard split, at the cost of 2× BRAM.

**Consequences**: self-modifying code must not fetch the same word in the cycle it is written (read-during-write semantics are tool-dependent for `SyncReadMem`); all stores — even to data — pay the extra write port.
