# Task 3 Report: Strip Down Top.scala

## What was implemented
- Stripped down `Top.scala` in `board/verilator` to remove unused peripherals (`vga`, `uart`, `dummy`, `bus_switch`, `bus_arbiter`).
- Instantiated `DualMasterAXIArbiter` and connected it to `cpu.io.inst_axi` and `cpu.io.data_axi` correctly.
- Discovered an interface sharing issue caused by the previous task: `CPU` wrapper and `PipelinedCPU` shared `CPUBundle`, but `PipelinedCPU` still needed `instruction_address` to function correctly. Separated `PipelinedCPUBundle` for the internal core while keeping `CPUBundle` updated for the `CPU` wrapper.
- Updated `TestTopModule.scala` to use the new dual AXI memory hierarchy with `DualMasterAXIArbiter` so it accurately reflects the new `Top` behavior and tests pass.

## Test Results
- `sbt "project soc" compile` completed successfully.
- `sbt "project soc" test` passed all 94 tests.

**Test summary:**
```
[info] Total number of tests run: 94
[info] Suites: completed 12, aborted 0
[info] Tests: succeeded 94, failed 0, canceled 0, ignored 0, pending 0
[info] All tests passed.
```

## Files Changed
- `4-soc/src/main/scala/board/verilator/Top.scala`
- `4-soc/src/main/scala/riscv/core/verilator/CPUBundle.scala`
- `4-soc/src/main/scala/riscv/core/verilator/PipelinedCPU.scala`
- `4-soc/src/test/scala/riscv/TestTopModule.scala`

## Self-Review Findings
- The changes accurately implement the requirement to strip `Top.scala` and wire up the `DualMasterAXIArbiter`.
- The tests accurately verify the SoC's functionality under the new structure.
- Resolved compile errors by isolating `CPUBundle` between the wrapper and internal core.

## Concerns
- None.

## Task 3 Review Fixes
- Extracted common fields between `PipelinedCPUBundle` and `CPUBundle` into a shared `CPUCommonBundle` trait in `CPUBundle.scala` to resolve the verbatim duplication issue.

### Test Results after Fixes
Command run: `sbt "project soc" test`

**Test summary:**
```text
[info] Total number of tests run: 94
[info] Suites: completed 12, aborted 0
[info] Tests: succeeded 94, failed 0, canceled 0, ignored 0, pending 0
[info] All tests passed.
```
