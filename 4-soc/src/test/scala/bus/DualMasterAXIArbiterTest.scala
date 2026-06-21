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

  it should "route RVALID correctly when ARVALID drops before RVALID" in {
    test(new DualMasterAXIArbiter(32, 32)) { dut =>
      dut.io.data_master.read_address_channel.ARVALID.poke(true.B)
      dut.io.data_master.read_address_channel.ARADDR.poke(0x1000.U)
      dut.io.slave.read_address_channel.ARREADY.poke(true.B)

      dut.clock.step(1)

      // Address accepted, drop ARVALID
      dut.io.data_master.read_address_channel.ARVALID.poke(false.B)
      dut.io.slave.read_address_channel.ARREADY.poke(false.B)

      // Inst master wants to read now, but should be blocked because data_master has pending read
      dut.io.inst_master.read_address_channel.ARVALID.poke(true.B)
      dut.io.slave.read_address_channel.ARREADY.poke(true.B)
      dut.io.inst_master.read_address_channel.ARREADY.expect(false.B)

      // Now R channel responds
      dut.io.slave.read_data_channel.RVALID.poke(true.B)
      dut.io.slave.read_data_channel.RDATA.poke(0x12345678.U)
      dut.io.data_master.read_data_channel.RREADY.poke(true.B)

      // Should route to data_master, not inst_master
      dut.io.data_master.read_data_channel.RVALID.expect(true.B)
      dut.io.inst_master.read_data_channel.RVALID.expect(false.B)

      dut.clock.step(1)
      dut.io.slave.read_data_channel.RVALID.poke(false.B)
    }
  }
}
