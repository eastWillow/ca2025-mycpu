`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/13/2025 09:55:30 PM
// Design Name: 
// Module Name: dut_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// hexdump -v -e '1/4 "%08x\n"' 2-mmio-trap/src/main/resources/fibonacci.asmbin > 2-mmio-trap/vivado/fibonacci.txt
// sbt "project mmioTrap" "runMain board.verilator.VerilogGenerator"
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// Copy From tb_top.sv
// Repleace the Simulation Signal with Real Signal
module dut_top(
    input sys_clk,
    input clk_wiz_reset,
    output [7:0]led
    );
    
    //Clock Wizard
    logic locked;
    reg cpu_clock;
    logic bram_clock;
    
    // System reset
    logic reset;

    clk_wiz_0 u_clk_gen (
        .clk_in1(sys_clk),      // 100 MHz From ARTY7-35T on Board
        .reset(!clk_wiz_reset), //
        .clk_out1(bram_clock),  // 50 MHz for BRAM
//        .clk_out2(cpu_clock),   // 10 MHz For CPU
        .locked(locked)         //
    );
    
    // Cpu Clock From BRAM Clock
    reg [2:0] counter;
    reg cpu_clock;
    always @(posedge bram_clock) begin
        if (clk_wiz_reset) begin
            counter <= 0;
            cpu_clock <= 0;
        end else begin
            if (counter == 4) begin 
                counter <= 0;
                cpu_clock <= 1;
            end else begin 
                counter <= counter + 1;
                cpu_clock <= 0;
            end
        end
    end

    // wait clock wizard lock
    assign reset = (locked == 0) || !clk_wiz_reset;
    assign io_instruction_valid = !reset;
    // --------------------------------------------------------
    // CPU Signals
    // --------------------------------------------------------
    // Instruction Fetch
    logic [31:0] io_instruction_address;
    logic [31:0] io_instruction;

    // Data Memory Access
    logic [31:0] io_memory_bundle_address;
    logic [31:0] io_memory_bundle_write_data;
    logic [31:0] io_memory_bundle_read_data;
    logic        io_memory_bundle_write_enable;
    logic        io_memory_bundle_write_strobe_0;
    logic        io_memory_bundle_write_strobe_1;
    logic        io_memory_bundle_write_strobe_2;
    logic        io_memory_bundle_write_strobe_3;

    // Debug
    logic [2:0]  io_deviceSelect;
    logic [31:0] io_regs_debug_read_address;
    logic [31:0] io_regs_debug_read_data;
    
    // --------------------------------------------------------
    // Block Memory Generator Instantiation
    // --------------------------------------------------------
    // =========================================================================
    //  Memory Decoder
    // =========================================================================
    // Stack BRAM 64KB (0x10000 bytes)
    // Stack Top = 0x400000, Stack Base = 0x3F0000
    logic is_stack_access;
    assign is_stack_access = (io_memory_bundle_address >= 32'h003F0000) && 
                             (io_memory_bundle_address <= 32'h00400000);
    // =========================================================================
    // 1. Main BRAM
    // =========================================================================
    // Mapping: 0x00000000 - 0x0000FFFF (64KB)
    logic [31:0] main_rdata;
    blk_mem_gen_0 u_bram (
            // --- Port A: Instruction Fetch (Read Only) ---
            .clka(bram_clock),
            .ena(1'b1),                                             // io_instruction_valid
            .wea(4'b0),                                             // Read Only
            .addra(io_instruction_address[17:2]-(32'h1000/4)),      // Word Address
            .dina(32'b0),
            .douta(io_instruction),
            
            // --- Port B: Data Access (Read/Write) ---
            .clkb(bram_clock),
            .enb(1'b1),
            .web( !is_stack_access ?
                  ({io_memory_bundle_write_strobe_3, 
                  io_memory_bundle_write_strobe_2, 
                  io_memory_bundle_write_strobe_1, 
                  io_memory_bundle_write_strobe_0} & {4{io_memory_bundle_write_enable}})
                  : 4'b0),
            .addrb(io_memory_bundle_address[17:2]),
            .dinb(io_memory_bundle_write_data),
            .doutb(main_rdata)
    );
    // =========================================================================
    // 2. Stack BRAM 
    // =========================================================================
    // Mapping: 0x003F0000 - 0x00400000 (Vritual) -> 0x0000 - 0xFFFF (Physical)
    logic [31:0] stack_rdata;
    // 0x003FFFFC (Address Aliasing) -> 0xFFFC
    blk_mem_gen_0 u_bram_stack (
        // Stack BRAM Port A is not used.
        .clka(bram_clock),
        .ena(1'b0),
        .wea(4'b0),
        .addra(14'b0),
        .dina(32'b0),
        .douta(),
        
        // --- Port B: Data Access (R/W) ---
        .clkb(bram_clock),
        .enb(1'b1),
        .web( is_stack_access ? 
              ({io_memory_bundle_write_strobe_3,
                io_memory_bundle_write_strobe_2, 
                io_memory_bundle_write_strobe_1,
                io_memory_bundle_write_strobe_0} & {4{io_memory_bundle_write_enable}}) 
              : 4'b0 ),
        .addrb(io_memory_bundle_address[17:2]),
        .dinb(io_memory_bundle_write_data),
        .doutb(stack_rdata)
    );
    // =========================================================================
    // 3. Read BRAM Data Mux  
    // =========================================================================
    assign io_memory_bundle_read_data = is_stack_access ? stack_rdata : main_rdata;

    logic test_passed;
    logic [31:0] result_data;
    assign led = result_data[7:0];

    always @(posedge cpu_clock) begin
            if (io_memory_bundle_write_enable && (io_memory_bundle_address == 32'h4)) begin
            // catch write mem address 0x4
            result_data = io_memory_bundle_write_data;
            if (io_memory_bundle_write_data == 32'h37) begin
                test_passed = 1;
            end
        end
    end

    Top u_Top (
        .clock(cpu_clock),
        .reset(reset),

        .io_instruction_address(io_instruction_address),
        .io_instruction(io_instruction),
        .io_instruction_valid(io_instruction_valid),

        .io_memory_bundle_address(io_memory_bundle_address),
        .io_memory_bundle_write_enable(io_memory_bundle_write_enable),
        .io_memory_bundle_write_data(io_memory_bundle_write_data),
        .io_memory_bundle_read_data(io_memory_bundle_read_data),

        .io_memory_bundle_write_strobe_0(io_memory_bundle_write_strobe_0),
        .io_memory_bundle_write_strobe_1(io_memory_bundle_write_strobe_1),
        .io_memory_bundle_write_strobe_2(io_memory_bundle_write_strobe_2),
        .io_memory_bundle_write_strobe_3(io_memory_bundle_write_strobe_3),

        .io_deviceSelect(io_deviceSelect),
        .io_regs_debug_read_address(io_regs_debug_read_address),
        .io_regs_debug_read_data(io_regs_debug_read_data)
    );

endmodule
