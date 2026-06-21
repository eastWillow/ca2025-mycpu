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
