// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps

/*
Step 0. cd 4-soc
Step 1. CROSS_COMPILE=riscv-none-elf- make check-uart
Step 2. cd csrc
Step 3. hexdump -v -e '1/4 "%08x" "\n"' uart.asmbin > program.mem


launch_simulation  -scripts_only

edit : simulate.sh
comment out -view and -log

edit : tb_top.tcl

open_vcd my_trace.vcd
log_vcd /tb_top/io_vga_hsync
log_vcd /tb_top/io_vga_vsync
log_vcd /tb_top/io_vga_activevideo
log_vcd /tb_top/io_vga_rrggbb
log_vcd /tb_top/io_vga_x_pos
log_vcd /tb_top/io_vga_y_pos
run 6ms
close_vcd
quit

*/


module tb_top;

    // -------------------------------------------------------------------------
    // Parameters & Constants
    // -------------------------------------------------------------------------
    // Segment Size: 64KB
    parameter SEGMENT_SIZE_BYTES = 64 * 1024; 
    parameter SEGMENT_WORDS      = SEGMENT_SIZE_BYTES / 4;
    
    // -------------------------------------------------------------------------
    // MEMORY MAP CONFIGURATION (Adapted to Linker Script)
    // -------------------------------------------------------------------------
    
    // 1. LOW MEMORY (IMEM): 0x0000_0000 ~ 0x0000_FFFF
    //    Based on Linker Script:
    //    - .text  starts at 0x1000
    //    - .data  follows .text (ALIGN 0x1000)
    //    - .sdata follows .data
    //    - .sbss  follows .sdata
    //    Since these are contiguous, they all fit in this first 64KB block.
    localparam IMEM_BASE         = 32'h0000_0000;
    
    // 2. HIGH DATA (DMEM): 0x0010_0000 ~ 0x0010_FFFF
    //    Based on Linker Script:
    //    - . = 0x00100000
    //    - .bss section sits here.
    //    We move DMEM_BASE to 1MB to capture writes to .bss.
    localparam DMEM_BASE         = 32'h0010_0000;
    
    // 3. STACK (SMEM): 0x003F_0000 ~ 0x003F_FFFF
    //    Supports SP = 0x0040_0000 (Grows down into this region)
    localparam SMEM_BASE         = 32'h003F_0000; 

    // Expected Initial SP Value
    localparam EXPECTED_SP       = 32'h0040_0000;

    // UART Timing
    parameter CYCLES_PER_BIT = 434;

    // Test termination magic values
    localparam MAGIC_ADDR    = 32'h0000_0100;
    localparam RESULT_ADDR   = 32'h0000_0104;
    localparam MAGIC_VAL     = 32'hCAFE_F00D;
    localparam UART_PASS     = 32'hF;
    localparam VGA_PASS      = 32'h3F;

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    logic clk_cpu;    // 100 MHz
    logic clk_vga;    // 31.5 MHz
    logic locked;
    logic mmcm_reset;
    logic sys_reset;
    logic ck_rst;       // ARTY RESET Push is Low
    logic CLK100MHZ;

    logic        io_instruction_valid;
    logic [31:0] io_instruction_address;
    logic [31:0] io_instruction;
    logic [31:0] io_instruction_req;
    
    logic        io_mem_slave_read;
    logic        io_mem_slave_read_valid;
    logic [31:0] io_mem_slave_address;
    logic [31:0] io_mem_slave_read_data;
    
    logic        io_mem_slave_write;
    logic [31:0] io_mem_slave_write_data;
    logic        io_mem_slave_write_strobe_0;
    logic        io_mem_slave_write_strobe_1;
    logic        io_mem_slave_write_strobe_2;
    logic        io_mem_slave_write_strobe_3;

    logic        io_signal_interrupt;
    logic        io_uart_txd;
    logic        io_uart_rxd;
    
    // VGA signals
    logic        io_vga_vsync;
    logic        io_vga_hsync;
    logic        io_vga_activevideo;
    logic [7:0]  io_vga_rrggbb;
    logic [15:0] io_vga_x_pos;
    logic [15:0] io_vga_y_pos;

    // Debug signals
    logic [31:0] io_cpu_debug_read_address = 0;
    logic [31:0] io_cpu_csr_debug_read_address = 0;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    Top dut (
        .clock                         (clk_cpu),
        .reset                         (sys_reset),
        .io_instruction_valid          (io_instruction_valid),
        .io_instruction                (io_instruction),
        .io_instruction_req            (io_instruction_req),
        .io_instruction_address        (io_instruction_address),
        .io_mem_slave_read             (io_mem_slave_read),
        .io_mem_slave_read_valid       (io_mem_slave_read_valid),
        .io_mem_slave_address          (io_mem_slave_address),
        .io_mem_slave_read_data        (io_mem_slave_read_data),
        .io_mem_slave_write            (io_mem_slave_write),
        .io_mem_slave_write_data       (io_mem_slave_write_data),
        .io_mem_slave_write_strobe_0   (io_mem_slave_write_strobe_0),
        .io_mem_slave_write_strobe_1   (io_mem_slave_write_strobe_1),
        .io_mem_slave_write_strobe_2   (io_mem_slave_write_strobe_2),
        .io_mem_slave_write_strobe_3   (io_mem_slave_write_strobe_3),
        .io_signal_interrupt           (io_signal_interrupt),
        .io_uart_txd                   (io_uart_txd),
        .io_uart_rxd                   (io_uart_rxd),
        .io_vga_pixclk                 (clk_vga),
        .io_vga_vsync                  (io_vga_vsync),
        .io_vga_hsync                  (io_vga_hsync),
        .io_vga_activevideo            (io_vga_activevideo),
        .io_vga_rrggbb                 (io_vga_rrggbb),
        .io_vga_x_pos                  (io_vga_x_pos),
        .io_vga_y_pos                  (io_vga_y_pos),
        .io_cpu_debug_read_address     (io_cpu_debug_read_address),
        .io_cpu_csr_debug_read_address (io_cpu_csr_debug_read_address)
    );

    // -------------------------------------------------------------------------
    // Clock & Reset
    // -------------------------------------------------------------------------
    initial begin
        CLK100MHZ = 0;
        forever #5 CLK100MHZ = ~CLK100MHZ; // 100MHz = 10ns period
    end
    
    // Arty Reset Button is Active Low (0 = Reset).
    // MMCM Reset is usually Active High (1 = Reset).
    assign mmcm_reset = ~ck_rst;

    // System Reset: Assert if button pressed OR clock not stable
    assign sys_reset = mmcm_reset | ~locked;

    clk_wiz_0 u_clk_wiz (
        .clk_cpu (clk_cpu),
        .clk_vga (clk_vga),
        .reset   (mmcm_reset),
        .locked  (locked),
        .clk_in1 (CLK100MHZ)
    );

    initial begin
        ck_rst = 0;
        io_instruction_valid = 1;
        io_signal_interrupt = 0;
        
        // Print Memory Configuration for Debugging
        $display("\n=============================================================");
        $display("[INFO] Memory Map Updated for Linker Script");
        $display("-------------------------------------------------------------");
        $display("  [IMEM] 0x%08x - 0x%08x : .text, .data, .sdata, .sbss", IMEM_BASE, IMEM_BASE + SEGMENT_SIZE_BYTES - 1);
        $display("  [DMEM] 0x%08x - 0x%08x : .bss (Starts at 1MB)", DMEM_BASE, DMEM_BASE + SEGMENT_SIZE_BYTES - 1);
        $display("  [SMEM] 0x%08x - 0x%08x : Stack (Ends at 4MB)", SMEM_BASE, SMEM_BASE + SEGMENT_SIZE_BYTES - 1);
        $display("-------------------------------------------------------------");
        $display("[INFO] Boot Info:");
        $display("       Start Address: 0x00001000");
        $display("       Initial SP   : 0x%08x", EXPECTED_SP);
        $display("=============================================================\n");

        repeat(50) @(posedge CLK100MHZ); // Wait for MMCM lock
        ck_rst = 1;
    end

    // -------------------------------------------------------------------------
    // Memory Subsystem (Instantiating TrueDualPortRAM32_DUT for each segment)
    // -------------------------------------------------------------------------
    
    // Address Decoding Helper
    function automatic logic [1:0] decode_address(logic [31:0] addr);
        if (addr >= IMEM_BASE && addr < (IMEM_BASE + SEGMENT_SIZE_BYTES))
            return 2'b00; // .text, .sdata, .sbss
        else if (addr >= DMEM_BASE && addr < (DMEM_BASE + SEGMENT_SIZE_BYTES))
            return 2'b01; // .bss (at 1MB)
        else if (addr >= SMEM_BASE && addr < (SMEM_BASE + SEGMENT_SIZE_BYTES))
            return 2'b10; // Stack
        else
            return 2'b11;
    endfunction

    // ------------------------------
    // 1. Instruction Fetch (Port B)
    // ------------------------------
    wire [31:0] imem_doutb, dmem_doutb, smem_doutb;
    wire [1:0]  fetch_sel;
    reg  [1:0]  fetch_sel_r; // Registered selector for synchronous RAM
    
    assign fetch_sel = decode_address(io_instruction_req);

    // Register the selector to match RAM latency (1 cycle)
    always_ff @(posedge clk_cpu) begin
        fetch_sel_r <= fetch_sel;
        io_instruction_address <= io_instruction_req;
        
        // Misalignment Check
        if (io_instruction_req[1:0] != 2'b00) 
            $display("[Error] PC Misaligned! Address: %h", io_instruction_req);
    end

    // MUX Output
    always_comb begin
        case (fetch_sel_r)
            2'b00: io_instruction = imem_doutb;
            2'b01: io_instruction = dmem_doutb;
            2'b10: io_instruction = smem_doutb;
            default: io_instruction = 32'h0;
        endcase
    end

    // ------------------------------
    // 2. Data Access (Port A)
    // ------------------------------
    wire [31:0] imem_douta, dmem_douta, smem_douta;
    wire [3:0]  imem_we, dmem_we, smem_we;
    wire [1:0]  data_sel;
    reg  [1:0]  data_sel_r;
    
    assign data_sel = decode_address(io_mem_slave_address);

    // Write Enable Decoding (Combinational)
    wire [3:0] global_we = {
        io_mem_slave_write && io_mem_slave_write_strobe_3,
        io_mem_slave_write && io_mem_slave_write_strobe_2,
        io_mem_slave_write && io_mem_slave_write_strobe_1,
        io_mem_slave_write && io_mem_slave_write_strobe_0
    };

    assign imem_we = (data_sel == 2'b00) ? global_we : 4'b0;
    assign dmem_we = (data_sel == 2'b01) ? global_we : 4'b0;
    assign smem_we = (data_sel == 2'b10) ? global_we : 4'b0;

    // Read Data Muxing
    always_ff @(posedge clk_cpu) begin
        data_sel_r <= data_sel;
        io_mem_slave_read_valid <= io_mem_slave_read;
        
        // Warnings
        if (io_mem_slave_read && data_sel == 2'b11) 
             $display("[Error] Read Unmapped Address! Addr: %h", io_mem_slave_address);
        if (io_mem_slave_write && data_sel == 2'b11)
             $display("[Warning] Write to unmapped address: %h", io_mem_slave_address);
             
        // Magic Termination
        if (io_mem_slave_write && 
            io_mem_slave_address == MAGIC_ADDR && 
            io_mem_slave_write_data == MAGIC_VAL) begin
            
            // Read result directly from IMEM instance
            logic [31:0] result;
            result = u_imem.mem[RESULT_ADDR >> 2];
            
            if (result == UART_PASS || result == VGA_PASS) begin
                $display("\nTEST PASSED (result=0x%0x)", result);
            end else begin
                $display("\nTEST FAILED (result=0x%0x)", result);
            end
            $finish;
        end
    end

    always_comb begin
        case (data_sel_r)
            2'b00: io_mem_slave_read_data = imem_douta;
            2'b01: io_mem_slave_read_data = dmem_douta;
            2'b10: io_mem_slave_read_data = smem_douta;
            default: io_mem_slave_read_data = 32'h0;
        endcase
    end

    // -------------------------------------------------------------------------
    // 3. Module Instantiations
    // -------------------------------------------------------------------------
    
    // IMEM Instance
    TrueDualPortRAM32_DUT #(
        .DEPTH(16384), .ADDR_WIDTH(14), .LOAD_OFFSET(1024), .INIT_FILE("program.mem")
    ) u_imem (
        .clka  (clk_cpu),
        .wea   (imem_we),
        .addra ((io_mem_slave_address - IMEM_BASE) >> 2),
        .dina  (io_mem_slave_write_data),
        .douta (imem_douta),
        .clkb  (clk_cpu),
        .addrb ((io_instruction_req - IMEM_BASE) >> 2),
        .doutb (imem_doutb)
    );

    // DMEM Instance
    TrueDualPortRAM32_DUT #(
        .DEPTH(16384), .ADDR_WIDTH(14), .LOAD_OFFSET(1024), .INIT_FILE("")
    ) u_dmem (
        .clka  (clk_cpu),
        .wea   (dmem_we),
        .addra ((io_mem_slave_address - DMEM_BASE) >> 2),
        .dina  (io_mem_slave_write_data),
        .douta (dmem_douta),
        .clkb  (clk_cpu),
        .addrb ((io_instruction_req - DMEM_BASE) >> 2),
        .doutb (dmem_doutb)
    );

    // SMEM Instance
    TrueDualPortRAM32_DUT #(
        .DEPTH(16384), .ADDR_WIDTH(14), .LOAD_OFFSET(1024), .INIT_FILE("")
    ) u_smem (
        .clka  (clk_cpu),
        .wea   (smem_we),
        .addra ((io_mem_slave_address - SMEM_BASE) >> 2),
        .dina  (io_mem_slave_write_data),
        .douta (smem_douta),
        .clkb  (clk_cpu),
        .addrb ((io_instruction_req - SMEM_BASE) >> 2),
        .doutb (smem_doutb)
    );

    // -------------------------------------------------------------------------
    // UART, VGA, Watchdog (No changes)
    // -------------------------------------------------------------------------
    assign io_uart_rxd = io_uart_txd;
    logic [7:0] uart_byte;
    
    initial begin
        forever begin
            @(negedge io_uart_txd);
            repeat (CYCLES_PER_BIT + (CYCLES_PER_BIT/2)) @(posedge clk_cpu);
            for (int i = 0; i < 8; i++) begin
                uart_byte[i] = io_uart_txd;
                repeat (CYCLES_PER_BIT) @(posedge clk_cpu);
            end
            if (uart_byte >= 32 && uart_byte <= 126) $write("%c", uart_byte);
            else if (uart_byte == 10 || uart_byte == 13) $write("\n");
            else $write("<%h>", uart_byte);
        end
    end

    integer frame_count = 0;
    integer active_pixels = 0;
    logic prev_vsync;
    always_ff @(posedge clk_cpu) begin
        if (io_vga_vsync && !prev_vsync) begin
            frame_count++;
            if (frame_count % 60 == 0) begin
                $display("[VGA] Time: %t | Frames: %0d | Active Pixels: %0d", 
                         $time, frame_count, active_pixels);
            end
        end
        prev_vsync <= io_vga_vsync;
    end

    always_ff @(posedge clk_cpu) begin
        if (!sys_reset) begin
            if (io_vga_activevideo) active_pixels++;
        end
    end

    initial begin
        repeat (50_000_000) @(posedge clk_cpu);
        $display("\nTIMEOUT: Max cycles reached without magic write.");
        $finish;
    end

endmodule
