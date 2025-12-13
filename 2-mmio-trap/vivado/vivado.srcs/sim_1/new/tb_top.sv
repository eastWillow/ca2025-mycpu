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
// hexdump -v -e '1/4 "%08x\n"' 2-mmio-trap/src/main/resources/fibonacci.asmbin > 2-mmio-trap/vivado/fibonacci.txt
// sbt "project mmioTrap" "runMain board.verilator.VerilogGenerator"
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module tb_top();
    logic sys_clk;
    initial sys_clk = 0;
    always #5 sys_clk = ~sys_clk; // 100MHz
    
    //Clock Wizard
    logic cpu_clock;
    logic locked;
    logic clk_wiz_reset;
    
    // System reset
    logic reset;
    
    clk_wiz_0 u_clk_gen (
        .clk_in1(sys_clk),      //
        .reset(clk_wiz_reset),  //
        .clk_out1(cpu_clock),   //
        .locked(locked)         //
    );
    
    initial begin
        // Reset Clock Wizard
        clk_wiz_reset = 1;
        #100;
        clk_wiz_reset = 0;
    end
    
    // wait clock wizard lock
    assign reset = (locked == 0) || clk_wiz_reset;
    
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
    logic [2:0]  io_deviceSelect;
    logic [31:0] io_regs_debug_read_address;
    logic [31:0] io_regs_debug_read_data;

    // Memory Simulation
    // 32-bit Memory
    // 4M words (16MB)
    logic [31:0] ram [0:32'h3FFFFF];
    initial begin
        $readmemh("../../../../fibonacci.txt", ram, (32'h1000 / 4));
        
        io_instruction_valid = 0;
        io_regs_debug_read_address = 0;
        
        wait(reset == 0); // wait until the clock wizard stablize
        repeat(10) @(posedge cpu_clock);
        
        io_instruction_valid = 1;
        
        #100000;
        
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

    //Instruction Fetch
    always @(*) begin
        if (io_instruction_address[31:2] < 32'h400000 && io_instruction_valid == 1)
                io_instruction = ram[io_instruction_address[31:2]];
            else
                io_instruction = 32'h00000013; // NOP addi x0, x0, 0
    end

    //Data Load
    always @(*) begin
        if (io_memory_bundle_address[31:2] < 32'h400000)
            io_memory_bundle_read_data = ram[io_memory_bundle_address[31:2]];
        else
            io_memory_bundle_read_data = 32'h00000000;
    end

    //Data Store with Strobes
    always @(posedge cpu_clock) begin
        if (io_memory_bundle_write_enable && (io_memory_bundle_address[31:2] < 32'h400000)) begin
            if (io_memory_bundle_write_strobe_0)
                ram[io_memory_bundle_address[31:2]][7:0]   <= io_memory_bundle_write_data[7:0];
            if (io_memory_bundle_write_strobe_1)
                ram[io_memory_bundle_address[31:2]][15:8]  <= io_memory_bundle_write_data[15:8];
            if (io_memory_bundle_write_strobe_2)
                ram[io_memory_bundle_address[31:2]][23:16] <= io_memory_bundle_write_data[23:16];
            if (io_memory_bundle_write_strobe_3)
                ram[io_memory_bundle_address[31:2]][31:24] <= io_memory_bundle_write_data[31:24];
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
