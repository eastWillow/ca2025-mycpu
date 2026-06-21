# Minimal SoC with Dual AXI-Lite Masters Design Specification

## Overview
This document outlines the design for creating a minimal RISC-V SoC. The architecture strips out complex peripherals (VGA, UART) and refactors the CPU to expose separate Instruction and Data memory interfaces exclusively over the AXI4-Lite bus protocol. These two masters will be arbitrated into a single AXI-Lite memory.

## Architecture & Data Flow

### 1. CPU IP Modification (`CPU.scala`)
- **Current State:** The CPU exposes an AXI4-Lite master for data (`axi4_channels`) and a dedicated SRAM-style interface for instructions (`instruction_address`, `instruction`, `instruction_valid`).
- **New State:** The SRAM-style instruction interface will be removed from the top-level IO. Instead, `CPU.scala` will expose two AXI4-Lite master interfaces:
  - `io.inst_axi`: Handles instruction fetching.
  - `io.data_axi`: Handles data reads/writes.
- **Implementation:** A second `AXI4LiteMaster` wrapper will be instantiated inside `CPU.scala` to convert the `PipelinedCPU`'s instruction fetch requests into standard AXI4-Lite transactions. The write channels for `inst_axi` will be permanently tied low.

### 2. Arbiter (`DualMasterAXIArbiter.scala`)
- A new module will be created to multiplex the two AXI-Lite master interfaces into a single AXI-Lite slave interface.
- **Priority Logic:** Data accesses (`data_axi`) are given strict priority over Instruction accesses (`inst_axi`). If a data Load/Store and an instruction fetch request the bus in the exact same cycle, the Data access wins the arbitration. The instruction fetch will stall until the bus is free.

### 3. Top-Level SoC (`Top.scala`)
- The top-level design will be heavily simplified.
- **Removals:** The VGA peripheral, UART peripheral, original `BusArbiter`, `DummySlave`, and `BusSwitch` will be deleted.
- **Data Path:** 
  `CPU (inst_axi, data_axi)` -> `DualMasterAXIArbiter` -> `mem_slave` (Main Memory).

## Verification Plan

### 1. Unit Testing (ChiselTest)
- **Arbiter Test:** Verify the priority logic of `DualMasterAXIArbiter` to ensure `data_axi` correctly preempts `inst_axi` when simultaneous requests occur.
- **Top-Level Mock Test:** Inject a mock instruction (`SW` or `LW`) using a simulated AXI memory slave. Verify that the AXI handshake sequence completes successfully: Instruction Fetch `AR` -> `R` followed by Data `AW/W` -> `B` (or `AR` -> `R`).

### 2. Integration Testing (Verilator Simulation)
- Write/Compile a lightweight RISC-V assembly test (`axi_test.S`) that initializes registers and performs memory operations.
- Run `make sim BINARY=csrc/axi_test.asmbin` to ensure the CPU can fetch and execute instructions over the AXI bus and write results back to memory without deadlocking.

### 3. RISCOF Compliance
- Run the full `make compliance` suite. Passing all RV32I tests will prove the new AXI-Lite pipeline timing for instruction fetching does not introduce regressions in forwarding, branch prediction, or standard execution.
