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
