package bus

import chisel3._
import riscv.Parameters

class DualMasterAXIArbiter(addrWidth: Int, dataWidth: Int) extends Module {
  val io = IO(new Bundle {
    val inst_master = Flipped(new AXI4LiteChannels(addrWidth, dataWidth))
    val data_master = Flipped(new AXI4LiteChannels(addrWidth, dataWidth))
    val slave       = new AXI4LiteChannels(addrWidth, dataWidth)
  })

  // Track pending read requests
  val data_r_pending = RegInit(0.U(8.W))
  val inst_r_pending = RegInit(0.U(8.W))

  val data_ar_fire = io.data_master.read_address_channel.ARVALID && io.data_master.read_address_channel.ARREADY
  val inst_ar_fire = io.inst_master.read_address_channel.ARVALID && io.inst_master.read_address_channel.ARREADY
  
  val data_r_fire = io.data_master.read_data_channel.RVALID && io.data_master.read_data_channel.RREADY
  val inst_r_fire = io.inst_master.read_data_channel.RVALID && io.inst_master.read_data_channel.RREADY

  data_r_pending := data_r_pending + data_ar_fire - data_r_fire
  inst_r_pending := inst_r_pending + inst_ar_fire - inst_r_fire

  // AR Arbitration
  // data_master has priority, but cannot issue if inst has pending reads
  val data_ar_allow = inst_r_pending === 0.U
  val inst_ar_allow = data_r_pending === 0.U && !io.data_master.read_address_channel.ARVALID

  io.slave.read_address_channel.ARVALID := Mux(data_ar_allow && io.data_master.read_address_channel.ARVALID, true.B,
                                           Mux(inst_ar_allow && io.inst_master.read_address_channel.ARVALID, true.B, false.B))
  
  io.slave.read_address_channel.ARADDR := Mux(data_ar_allow && io.data_master.read_address_channel.ARVALID, io.data_master.read_address_channel.ARADDR, io.inst_master.read_address_channel.ARADDR)
  io.slave.read_address_channel.ARPROT := Mux(data_ar_allow && io.data_master.read_address_channel.ARVALID, io.data_master.read_address_channel.ARPROT, io.inst_master.read_address_channel.ARPROT)

  io.data_master.read_address_channel.ARREADY := io.slave.read_address_channel.ARREADY && data_ar_allow
  // No longer includes inst_master's ARVALID
  io.inst_master.read_address_channel.ARREADY := io.slave.read_address_channel.ARREADY && inst_ar_allow

  // R Channel Routing
  io.data_master.read_data_channel.RVALID := io.slave.read_data_channel.RVALID && (data_r_pending =/= 0.U)
  io.inst_master.read_data_channel.RVALID := io.slave.read_data_channel.RVALID && (inst_r_pending =/= 0.U)
  
  io.slave.read_data_channel.RREADY := Mux(data_r_pending =/= 0.U, io.data_master.read_data_channel.RREADY, 
                                       Mux(inst_r_pending =/= 0.U, io.inst_master.read_data_channel.RREADY, true.B))
  
  io.data_master.read_data_channel.RDATA := io.slave.read_data_channel.RDATA
  io.data_master.read_data_channel.RRESP := io.slave.read_data_channel.RRESP
  io.inst_master.read_data_channel.RDATA := io.slave.read_data_channel.RDATA
  io.inst_master.read_data_channel.RRESP := io.slave.read_data_channel.RRESP

  // AW Channel (Data master only)
  io.slave.write_address_channel.AWVALID := io.data_master.write_address_channel.AWVALID
  io.slave.write_address_channel.AWADDR  := io.data_master.write_address_channel.AWADDR
  io.slave.write_address_channel.AWPROT  := io.data_master.write_address_channel.AWPROT
  io.data_master.write_address_channel.AWREADY := io.slave.write_address_channel.AWREADY
  
  io.inst_master.write_address_channel.AWREADY := false.B

  // W Channel (Data master only)
  io.slave.write_data_channel.WVALID := io.data_master.write_data_channel.WVALID
  io.slave.write_data_channel.WDATA  := io.data_master.write_data_channel.WDATA
  io.slave.write_data_channel.WSTRB  := io.data_master.write_data_channel.WSTRB
  io.data_master.write_data_channel.WREADY := io.slave.write_data_channel.WREADY

  io.inst_master.write_data_channel.WREADY := false.B

  // B Channel (Data master only)
  io.data_master.write_response_channel.BVALID := io.slave.write_response_channel.BVALID
  io.data_master.write_response_channel.BRESP  := io.slave.write_response_channel.BRESP
  io.slave.write_response_channel.BREADY := io.data_master.write_response_channel.BREADY
  
  io.inst_master.write_response_channel.BVALID := false.B
  io.inst_master.write_response_channel.BRESP  := 0.U
}
