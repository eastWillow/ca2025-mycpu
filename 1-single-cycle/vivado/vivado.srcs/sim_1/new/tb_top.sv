`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 12/13/2025 12:07:11 PM
// Design Name:
// Module Name: tb_top
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
// hexdump -v -e '1/4 "%08x\n"' 1-single-cycle/src/main/resources/fibonacci.asmbin > 1-single-cycle/vivado/fibonacci.txt
// sbt "project singleCycle" "runMain board.verilator.VerilogGenerator"
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module tb_top();
    logic clock;
    logic reset;

    // Instruction Fetch
    logic [31:0] io_instruction_address;
    logic [31:0] io_instruction;
    logic        io_instruction_valid;

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
    logic [1:0]  io_deviceSelect;
    logic [31:0] io_debug_read_address;
    logic [31:0] io_debug_read_data;

    // Memory Simulation
    // 32-bit Memory
    // 16384 * 4 bytes = 64KB
    logic [31:0] ram [0:32'h2000];
    initial begin
        $readmemh("../../../../fibonacci.txt", ram, (32'h1000 / 4));
        clock = 0;
        reset = 1;
        io_instruction_valid = 0;
        io_debug_read_address = 0;
        #10 reset = 0;
        #10 io_instruction_valid = 1;
        #50000;
        if (ram[4/4] == 32'h37) begin
            $display("=================================================");
            $display(" PASS: Fibonacci(10) calculation correct! (55) ");
            $display("=================================================");
        end else begin
            $display("=================================================");
            $display(" FAIL: Expected 55 (0x37), but got 0x%h ", ram[4/4]);
            $display("=================================================");
        end
        $finish;
    end

    always #5 clock = ~clock;

    //Instruction Fetch
    always @(*) begin
        if (io_instruction_address[31:2] < 16384 && io_instruction_valid == 1)
                io_instruction = ram[io_instruction_address[15:2]];
            else
                io_instruction = 32'h00000013; // NOP addi x0, x0, 0
    end

    //Data Load
    always @(*) begin
        if (io_memory_bundle_address[31:2] < 16384)
            io_memory_bundle_read_data = ram[io_memory_bundle_address[15:2]];
        else
            io_memory_bundle_read_data = 32'h00000000;
    end

    //Data Store with Strobes
    always @(posedge clock) begin
        if (io_memory_bundle_write_enable && (io_memory_bundle_address[31:2] < 16384)) begin
            if (io_memory_bundle_write_strobe_0)
                ram[io_memory_bundle_address[15:2]][7:0]   <= io_memory_bundle_write_data[7:0];
            if (io_memory_bundle_write_strobe_1)
                ram[io_memory_bundle_address[15:2]][15:8]  <= io_memory_bundle_write_data[15:8];
            if (io_memory_bundle_write_strobe_2)
                ram[io_memory_bundle_address[15:2]][23:16] <= io_memory_bundle_write_data[23:16];
            if (io_memory_bundle_write_strobe_3)
                ram[io_memory_bundle_address[15:2]][31:24] <= io_memory_bundle_write_data[31:24];
        end
    end

    Top u_Top (
        .clock(clock),
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
        .io_debug_read_address(io_debug_read_address),
        .io_debug_read_data(io_debug_read_data)
    );
endmodule
