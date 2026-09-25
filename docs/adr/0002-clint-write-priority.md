# CLINT CSR writes take priority over CPU CSR writes

When the CLINT asserts `direct_write_enable` (trap entry) in the same cycle the CPU issues a CSR write, the CLINT's values win for `mstatus`, `mepc`, and `mcause`. A trap entry must update these three CSRs atomically: mepc = current PC, mcause = interrupt/exception code, and mstatus = (MPIE ← MIE, MIE ← 0). If a concurrent `CSRRW mstatus` could win, the handler would run with stale mepc/mcause or re-enabled interrupts, breaking the save/restore invariant MRET relies on.

**Considered options**: round-robin or CPU-priority arbitration would keep CSR instructions deterministic but make trap entry non-atomic; delaying CPU CSR writes while a trap is in flight adds a stall the single-cycle design cannot express. Priority arbitration is a one-line `when/elsewhen` and preserves both properties.

**Consequences**: a CPU CSR write coinciding with trap entry is silently discarded (the write is lost, not retried); MIE/MTVEC/MSCRATCH are CPU-only and never affected by the priority.
