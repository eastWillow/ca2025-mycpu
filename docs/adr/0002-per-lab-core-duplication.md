# Per-lab core duplication instead of a shared core module

Each lab directory (0-minimal … 4-soc) compiles its own copy of the processor core instead of `common/` holding one parameterized core that all labs configure. `common/` carries only what labs genuinely share today (Parameters, RegisterFile, ALU of the single-cycle family); the Pipeline core does not depend on it at all because its register file needs pipeline write-forwarding and its Parameters differ.

The duplication is deliberate: a lab's code must stay readable and modifiable in isolation for coursework, and a shared core with an option surface big enough for all four labs would hide the architectural differences the labs exist to teach (e.g., MMIO-Trap's CLINT priority, Pipeline's hazard logic). The cost — a fixed concept in one lab must be re-applied in the later copies — is accepted.

**Consequences**: code review must check every affected copy, not one module; `common/` is not the place to "consolidate" cores.
