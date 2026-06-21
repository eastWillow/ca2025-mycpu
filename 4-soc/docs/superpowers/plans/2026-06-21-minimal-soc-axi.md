# Minimal SoC Dual AXI-Lite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the CPU to use dual AXI-Lite interfaces (Instruction and Data) and arbitrate them into a single memory slave, removing all other peripherals.

**Architecture:** We will create a `DualMasterAXIArbiter` that multiplexes two master `AXI4LiteChannels` interfaces into one slave interface, giving strict priority to the data master. Then, we will update the `CPUBundle` and `CPU` to expose two AXI interfaces, removing the dedicated instruction fetch pins. Finally, we will strip down `Top` to just the CPU, Arbiter, and Memory.

**Tech Stack:** Chisel3, Scala, ChiselTest

## Global Constraints

- Use Chisel 3 syntax (e.g., `.B`, `.U`, `WireInit`, `RegInit`).
- The Data AXI Master must have strict priority over the Instruction AXI Master.

---

### Task 1: Create DualMasterAXIArbiter

**Files:**
- Create: `src/main/scala/bus/DualMasterAXIArbiter.scala`
- Create: `src/test/scala/bus/DualMasterAXIArbiterTest.scala`

**Interfaces:**
- Produces: `class DualMasterAXIArbiter(addrWidth: Int, dataWidth: Int)` with IO containing `inst_master`, `data_master` (Flipped AXI4LiteChannels) and `slave` (AXI4LiteChannels).

- [ ] **Step 1: Write the failing test**

```scala
package bus

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec

class DualMasterAXIArbiterTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior of "DualMasterAXIArbiter"

  it should "grant data master priority when both request simultaneously" in {
    test(new DualMasterAXIArbiter(32, 32)) { dut =>
      dut.io.inst_master.read_address_channel.ARVALID.poke(true.B)
      dut.io.data_master.read_address_channel.ARVALID.poke(true.B)
      dut.io.slave.read_address_channel.ARREADY.poke(true.B)
      
      dut.clock.step(1)
      
      // Data should be granted, Inst should wait
      dut.io.data_master.read_address_channel.ARREADY.expect(true.B)
      dut.io.inst_master.read_address_channel.ARREADY.expect(false.B)
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sbt "testOnly bus.DualMasterAXIArbiterTest"`
Expected: FAIL (file not found / compilation error)

- [ ] **Step 3: Write minimal implementation**

```scala
package bus

import chisel3._
import riscv.Parameters

class DualMasterAXIArbiter(addrWidth: Int, dataWidth: Int) extends Module {
  val io = IO(new Bundle {
    val inst_master = Flipped(new AXI4LiteChannels(addrWidth, dataWidth))
    val data_master = Flipped(new AXI4LiteChannels(addrWidth, dataWidth))
    val slave       = new AXI4LiteChannels(addrWidth, dataWidth)
  })

  // Priority: data_master > inst_master
  val data_req_read = io.data_master.read_address_channel.ARVALID
  val data_req_write = io.data_master.write_address_channel.AWVALID
  val data_active = data_req_read || data_req_write

  // AR Channel
  io.slave.read_address_channel.ARVALID := Mux(data_active, io.data_master.read_address_channel.ARVALID, io.inst_master.read_address_channel.ARVALID)
  io.slave.read_address_channel.ARADDR  := Mux(data_active, io.data_master.read_address_channel.ARADDR, io.inst_master.read_address_channel.ARADDR)
  io.slave.read_address_channel.ARPROT  := Mux(data_active, io.data_master.read_address_channel.ARPROT, io.inst_master.read_address_channel.ARPROT)

  io.data_master.read_address_channel.ARREADY := io.slave.read_address_channel.ARREADY && data_active
  io.inst_master.read_address_channel.ARREADY := io.slave.read_address_channel.ARREADY && !data_active && io.inst_master.read_address_channel.ARVALID

  // R Channel
  io.data_master.read_data_channel.RVALID := io.slave.read_data_channel.RVALID && data_active // Simplification: assume atomic transactions or track state
  io.inst_master.read_data_channel.RVALID := io.slave.read_data_channel.RVALID && !data_active
  io.slave.read_data_channel.RREADY := Mux(data_active, io.data_master.read_data_channel.RREADY, io.inst_master.read_data_channel.RREADY)
  
  io.data_master.read_data_channel.RDATA := io.slave.read_data_channel.RDATA
  io.data_master.read_data_channel.RRESP := io.slave.read_data_channel.RRESP
  io.inst_master.read_data_channel.RDATA := io.slave.read_data_channel.RDATA
  io.inst_master.read_data_channel.RRESP := io.slave.read_data_channel.RRESP

  // AW Channel
  io.slave.write_address_channel.AWVALID := io.data_master.write_address_channel.AWVALID
  io.slave.write_address_channel.AWADDR  := io.data_master.write_address_channel.AWADDR
  io.slave.write_address_channel.AWPROT  := io.data_master.write_address_channel.AWPROT
  io.data_master.write_address_channel.AWREADY := io.slave.write_address_channel.AWREADY
  
  io.inst_master.write_address_channel.AWREADY := false.B

  // W Channel
  io.slave.write_data_channel.WVALID := io.data_master.write_data_channel.WVALID
  io.slave.write_data_channel.WDATA  := io.data_master.write_data_channel.WDATA
  io.slave.write_data_channel.WSTRB  := io.data_master.write_data_channel.WSTRB
  io.data_master.write_data_channel.WREADY := io.slave.write_data_channel.WREADY

  io.inst_master.write_data_channel.WREADY := false.B

  // B Channel
  io.data_master.write_response_channel.BVALID := io.slave.write_response_channel.BVALID
  io.data_master.write_response_channel.BRESP  := io.slave.write_response_channel.BRESP
  io.slave.write_response_channel.BREADY := io.data_master.write_response_channel.BREADY
  
  io.inst_master.write_response_channel.BVALID := false.B
  io.inst_master.write_response_channel.BRESP  := 0.U
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sbt "testOnly bus.DualMasterAXIArbiterTest"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/main/scala/bus/DualMasterAXIArbiter.scala src/test/scala/bus/DualMasterAXIArbiterTest.scala
git commit -m "feat: add DualMasterAXIArbiter with priority logic"
```

---

### Task 2: Refactor CPUBundle and CPU for Dual AXI

**Files:**
- Modify: `src/main/scala/riscv/core/verilator/CPUBundle.scala`
- Modify: `src/main/scala/riscv/core/verilator/CPU.scala`

**Interfaces:**
- Consumes: `DualMasterAXIArbiter`
- Produces: `io.inst_axi` and `io.data_axi` instead of `io.instruction_*` and `io.axi4_channels`.

- [ ] **Step 1: Write the failing test**
(None needed for bundle signature, we will verify by compiling).

- [ ] **Step 2: Modify CPUBundle**

Replace `instruction_address`, `instruction`, `instruction_valid`, and `axi4_channels` with:
```scala
  // Dual AXI4-Lite interfaces
  val inst_axi = new AXI4LiteChannels(Parameters.AddrBits, Parameters.DataBits)
  val data_axi = new AXI4LiteChannels(Parameters.AddrBits, Parameters.DataBits)
```

- [ ] **Step 3: Modify CPU**

Inside `CPU.scala`, rename `io.axi4_channels <> axi_master.io.channels` to `io.data_axi <> axi_master.io.channels`.
Add an AXI master for instruction fetch:
```scala
      val inst_axi_master = Module(new AXI4LiteMaster(Parameters.AddrBits, Parameters.DataBits))
      inst_axi_master.io.bundle.address := cpu.io.instruction_address
      inst_axi_master.io.bundle.read := true.B // Always read for fetch
      inst_axi_master.io.bundle.write := false.B
      inst_axi_master.io.bundle.write_data := 0.U
      inst_axi_master.io.bundle.write_strobe := VecInit(Seq.fill(Parameters.WordSize)(false.B))
      
      cpu.io.instruction := inst_axi_master.io.bundle.read_data
      cpu.io.instruction_valid := inst_axi_master.io.bundle.read_valid
      
      io.inst_axi <> inst_axi_master.io.channels
```

- [ ] **Step 4: Run compilation**

Run: `sbt compile`
Expected: FAIL in `Top.scala` because `Top` still expects `instruction_address`, etc. We will fix `Top` in Task 3. 
Wait, we can comment out `Top.scala` connections temporarily or just proceed to Task 3 to fix the build.

- [ ] **Step 5: Commit**

```bash
git add src/main/scala/riscv/core/verilator/CPUBundle.scala src/main/scala/riscv/core/verilator/CPU.scala
git commit -m "refactor: update CPU to use dual AXI masters"
```

---

### Task 3: Strip Down Top.scala

**Files:**
- Modify: `src/main/scala/board/verilator/Top.scala`

**Interfaces:**
- Consumes: `DualMasterAXIArbiter` and `CPU`

- [ ] **Step 1: Write minimal implementation**

Open `Top.scala` and remove `vga`, `uart`, `dummy`, `bus_switch`, `bus_arbiter`.
Instantiate `DualMasterAXIArbiter` and connect it:

```scala
  val cpu = Module(new CPU)
  val mem_slave = Module(new AXI4LiteSlave(Parameters.AddrBits, Parameters.DataBits))
  io.mem_slave <> mem_slave.io.bundle

  val arbiter = Module(new bus.DualMasterAXIArbiter(Parameters.AddrBits, Parameters.DataBits))
  
  arbiter.io.inst_master <> cpu.io.inst_axi
  arbiter.io.data_master <> cpu.io.data_axi
  arbiter.io.slave <> mem_slave.io.channels

  // Interrupts
  cpu.io.interrupt_flag := io.signal_interrupt

  // Debug
  cpu.io.debug_read_address := io.cpu_debug_read_address
  io.cpu_debug_read_data := cpu.io.debug_read_data
  cpu.io.csr_debug_read_address := io.cpu_csr_debug_read_address
  io.cpu_csr_debug_read_data := cpu.io.csr_debug_read_data
```
Remove any `instruction_*`, `vga_*`, `uart_*` ports from the `io` bundle of `Top`.

- [ ] **Step 2: Run test/compile to verify it passes**

Run: `sbt compile`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add src/main/scala/board/verilator/Top.scala
git commit -m "feat: strip down Top to minimal SoC with dual AXI arbiter"
```

---

### Task 4: Run Compliance Testing

- [ ] **Step 1: Run Compliance Tests**

Run: `make compliance`
Expected: ALL TESTS PASS.

- [ ] **Step 2: Commit any fixes if needed**
