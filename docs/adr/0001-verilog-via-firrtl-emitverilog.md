# Verilog via ChiselStage.emitVerilog (Chisel 3.6 + FIRRTL 1.6), not CIRCT/firtool

All labs emit Verilog through the legacy FIRRTL compiler (`ChiselStage.emitVerilog()`) with Chisel 3.6.1 / FIRRTL 1.6.0 rather than the modern CIRCT `firtool` path. The trade-off is accepted (pinned legacy toolchain, deprecation warnings suppressed in build.sbt) in exchange for a small, self-contained dependency set that runs identically on Linux, Intel macOS, and ARM macOS — any environment the students have — without building or locating a CIRCT release.

**Consequences**: upgrading Chisel is a project-scale migration, not a version bump; new Chisel features that require firtool are out of reach. The legacy `chisel3`/`firrtl` artifacts are intentionally pinned in every project section of `build.sbt`.
