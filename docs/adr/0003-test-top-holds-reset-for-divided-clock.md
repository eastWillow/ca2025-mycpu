# Test tops hold reset until the divided CPU clock ticks

`TestTopModule` in `1-single-cycle`, `2-mmio-trap`, and `3-pipeline` runs the CPU on a 4×-divided clock (`CPU_tick`). The tests now use `withClockAndReset(CPU_tick.asClock, (reset.asBool || !cpuStarted).asAsyncReset)` — holding reset until the divided clock has sampled at least one low phase — instead of plain `withClock`.

**Considered options**: with plain `withClock`, chiseltest drives the divided clock's first edge at the same time reset deasserts; the CPU's `RegInit` PC then fails to latch its entry address on some backends and the first instruction never executes (ByteAccessTest reads all-zero registers). Alternatives — stepping the outer clock a few cycles before poking, or adding a reset deassertion delay in the DUT — all leak testbench assumptions into the design or into every test.

**Consequences**: the DUT under test sees a slightly longer reset than in real use (a few extra reset cycles at time 0); the wrapper is test-only, so silicon is unaffected. Reverting to `withClock` breaks `ByteAccessTest` and the other program-integration tests.
