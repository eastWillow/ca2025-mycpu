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
    always #5 sys_clk = ~sys_clk; // 100MHz For clock wiz
    
    //Clock Wizard
    logic locked;
    logic cpu_clock;
    logic bram_clock;
    logic clk_wiz_reset;
    
    // System reset
    logic reset;
    
    clk_wiz_0 u_clk_gen (
        .clk_in1(sys_clk),      // 100 MHz From ARTY7-35T on Board
        .reset(clk_wiz_reset),  //
        .clk_out1(bram_clock),  // 100 MHz for BRAM
        .clk_out2(cpu_clock),   // 20 MHz For CPU
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
    
    // --------------------------------------------------------
    // CPU Signals
    // --------------------------------------------------------
    // Instruction Fetch
    logic [31:0] io_instruction_address;
    logic [31:0] io_instruction;
    logic io_instruction_valid;

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
    // [New] Block Memory Generator Instantiation
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
    
    initial begin        
        io_instruction_valid = 0;
        io_regs_debug_read_address = 0;
        test_passed = 0;
        result_data = 0;
        
        wait(reset == 0); // Wait for Reset Release
        repeat(10) @(posedge cpu_clock);
        
        io_instruction_valid = 1;
        
        #135000;
        
        // Check Result
        if (test_passed) begin
            $display("=================================================");
            $display(" PASS: Fibonacci(10) calculation correct! (%0d) ", result_data);
            $display("=================================================");
        end else begin
            $display("=================================================");
            $display(" FAIL: Timeout or result incorrect. Last Addr: %h", io_memory_bundle_address);
            $display("=================================================");
        end
        $finish;
    end

    always @(posedge cpu_clock) begin
            if (io_memory_bundle_write_enable && (io_memory_bundle_address == 32'h4)) begin
            // catch write mem address 0x4
            if (io_memory_bundle_write_data == 32'h37) begin
                test_passed = 1;
                result_data = io_memory_bundle_write_data;
            end else begin
                $display("[Monitor] Write to 0x4 detected but value is %h (Expected 0x37)", io_memory_bundle_write_data);
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
