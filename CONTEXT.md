# CA2025 MyCPU Learning Path

This context names the five numbered RISC-V processor projects in the CA2025 learning path and the verification language used across them.

## Language

**Lab project**:
One of the numbered processor projects, from `0-minimal` through `4-soc`, in the CA2025 learning path. _Avoid_: stage (which can also mean a processor pipeline stage).

**Per-project test pass**:
A lab project's `make test` command completes successfully.

**Exercise hole**:
A `CA25: Exercise` marker in lab source code with `?` placeholders where a student implements the missing logic. _Avoid_: TODO, stub.

**False stall**:
A pipeline stall that the hazard detector must _not_ issue — a control-flow scenario that looks like a hazard but has no true register dependency (e.g. a load whose base register was prepared well before use).
