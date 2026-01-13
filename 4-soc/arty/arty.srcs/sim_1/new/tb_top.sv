// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps

/*
Step 0. cd 4-soc
Step 1. CROSS_COMPILE=riscv-none-elf- make check-uart
Step 2. cd csrc
Step 3. hexdump -v -e '1/4 "%08x" "\n"' uart.asmbin > program.mem
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
    logic clock;
    logic reset;

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
    logic        io_vga_pixclk;
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
        .clock                         (clock),
        .reset                         (reset),
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
        .io_vga_pixclk                 (io_vga_pixclk),
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
        clock = 0;
        forever #5 clock = ~clock;
    end

    logic [1:0] vga_div;
    initial begin
        io_vga_pixclk = 0;
        vga_div = 0;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            vga_div <= 0;
            io_vga_pixclk <= 0;
        end else begin
            vga_div <= vga_div + 1;
            if (vga_div == 3) begin 
                vga_div <= 0;
                io_vga_pixclk <= ~io_vga_pixclk;
            end
        end
    end

    initial begin
        reset = 1;
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

        repeat(10) @(posedge clock);
        reset = 0;
    end

    // -------------------------------------------------------------------------
    // Memory Storage (Sparse Model)
    // -------------------------------------------------------------------------
    // IMEM: Stores code AND small data/sbss
    logic [31:0] imem [0:SEGMENT_WORDS-1]; 
    // DMEM: Stores large BSS
    logic [31:0] dmem [0:SEGMENT_WORDS-1];
    // SMEM: Stores Stack
    logic [31:0] smem [0:SEGMENT_WORDS-1]; 
    
    initial begin
        // Clear Memories
        for (int i=0; i < SEGMENT_WORDS; i++) begin
            imem[i] = 32'h0;
            dmem[i] = 32'h0;
            smem[i] = 32'h0;
        end

        // Load hex file
        // Note: program.hex will contain .text, .data, .sdata initialized values
        // They will automatically load into 'imem' because addresses are < 64KB.
        $readmemh("program.mem", imem, 32'h400); 
        $display("[INFO] program.mem loaded into IMEM (covers .text/.sdata)");
    end

    // -------------------------------------------------------------------------
    // Address Decoding Logic (Range Based)
    // -------------------------------------------------------------------------
    // Returns: 2'b00 (IMEM), 2'b01 (DMEM), 2'b10 (SMEM), 2'b11 (Invalid)
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

    // -------------------------------------------------------------------------
    // INSTRUCTION FETCH
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        logic [1:0] sel;
        logic [31:0] word_idx;
        
        sel = decode_address(io_instruction_req);
        
        // Calculate offset
        if (sel == 2'b00) word_idx = (io_instruction_req - IMEM_BASE) >> 2;
        else if (sel == 2'b01) word_idx = (io_instruction_req - DMEM_BASE) >> 2;
        else word_idx = 0;

        if (io_instruction_req[1:0] != 2'b00) begin
            $display("[Error] PC Misaligned! Address: %h", io_instruction_req);
        end

        // Fetch Logic
        if (sel == 2'b00 && word_idx < SEGMENT_WORDS) begin
            io_instruction = imem[word_idx];
            io_instruction_address = io_instruction_req;
        end else if (sel == 2'b01 && word_idx < SEGMENT_WORDS) begin
            io_instruction = dmem[word_idx];
            io_instruction_address = io_instruction_req;
        end else begin
            io_instruction = 32'h0; 
        end
    end

    // -------------------------------------------------------------------------
    // DATA ACCESS (Read/Write)
    // -------------------------------------------------------------------------
    logic [1:0] mem_select;
    logic [31:0] rw_word_idx;
    
    // Address Decode Phase
    always_comb begin
        mem_select = decode_address(io_mem_slave_address);
        
        if (mem_select == 2'b00) rw_word_idx = (io_mem_slave_address - IMEM_BASE) >> 2;
        else if (mem_select == 2'b01) rw_word_idx = (io_mem_slave_address - DMEM_BASE) >> 2;
        else if (mem_select == 2'b10) rw_word_idx = (io_mem_slave_address - SMEM_BASE) >> 2;
        else rw_word_idx = 0;
    end

    always_ff @(posedge clock) begin
        io_mem_slave_read_valid <= 0;

        // --- READ ---
        if (io_mem_slave_read) begin
            if (mem_select == 2'b11) begin
                 $display("[Error] Read Unmapped Address! Addr: %h", io_mem_slave_address);
                 io_mem_slave_read_data <= 32'hDEADBEEF;
            end else begin
                case (mem_select)
                    2'b00: io_mem_slave_read_data <= imem[rw_word_idx]; // Read .text/.sdata/.sbss
                    2'b01: io_mem_slave_read_data <= dmem[rw_word_idx]; // Read .bss
                    2'b10: io_mem_slave_read_data <= smem[rw_word_idx]; // Read Stack
                    default: io_mem_slave_read_data <= 32'h0;
                endcase
            end
            io_mem_slave_read_valid <= 1;
        end

        // --- WRITE ---
        if (io_mem_slave_write) begin
            if (mem_select != 2'b11) begin
                case (mem_select)
                    2'b00: begin // IMEM (Write to .sdata/.sbss)
                        if (io_mem_slave_write_strobe_0) imem[rw_word_idx][7:0]   <= io_mem_slave_write_data[7:0];
                        if (io_mem_slave_write_strobe_1) imem[rw_word_idx][15:8]  <= io_mem_slave_write_data[15:8];
                        if (io_mem_slave_write_strobe_2) imem[rw_word_idx][23:16] <= io_mem_slave_write_data[23:16];
                        if (io_mem_slave_write_strobe_3) imem[rw_word_idx][31:24] <= io_mem_slave_write_data[31:24];
                    end
                    2'b01: begin // DMEM (Write to .bss)
                        if (io_mem_slave_write_strobe_0) dmem[rw_word_idx][7:0]   <= io_mem_slave_write_data[7:0];
                        if (io_mem_slave_write_strobe_1) dmem[rw_word_idx][15:8]  <= io_mem_slave_write_data[15:8];
                        if (io_mem_slave_write_strobe_2) dmem[rw_word_idx][23:16] <= io_mem_slave_write_data[23:16];
                        if (io_mem_slave_write_strobe_3) dmem[rw_word_idx][31:24] <= io_mem_slave_write_data[31:24];
                    end
                    2'b10: begin // SMEM (Stack)
                        if (io_mem_slave_write_strobe_0) smem[rw_word_idx][7:0]   <= io_mem_slave_write_data[7:0];
                        if (io_mem_slave_write_strobe_1) smem[rw_word_idx][15:8]  <= io_mem_slave_write_data[15:8];
                        if (io_mem_slave_write_strobe_2) smem[rw_word_idx][23:16] <= io_mem_slave_write_data[23:16];
                        if (io_mem_slave_write_strobe_3) smem[rw_word_idx][31:24] <= io_mem_slave_write_data[31:24];
                    end
                endcase
            end else begin
                // e.g. Writes to the gap between 64KB and 1MB
                $display("[Warning] Write to unmapped address: %h", io_mem_slave_address);
            end

            // Magic Termination
            if (io_mem_slave_address == MAGIC_ADDR && io_mem_slave_write_data == MAGIC_VAL) begin
                logic [31:0] result;
                result = imem[RESULT_ADDR >> 2]; 
                
                if (result == UART_PASS || result == VGA_PASS) begin
                    $display("\nTEST PASSED (result=0x%0x)", result);
                end else begin
                    $display("\nTEST FAILED (result=0x%0x)", result);
                end
                $finish;
            end
        end
    end

    // -------------------------------------------------------------------------
    // UART, VGA, Watchdog (No changes)
    // -------------------------------------------------------------------------
    assign io_uart_rxd = io_uart_txd;
    logic [7:0] uart_byte;
    
    initial begin
        forever begin
            @(negedge io_uart_txd);
            repeat (CYCLES_PER_BIT + (CYCLES_PER_BIT/2)) @(posedge clock);
            for (int i = 0; i < 8; i++) begin
                uart_byte[i] = io_uart_txd;
                repeat (CYCLES_PER_BIT) @(posedge clock);
            end
            if (uart_byte >= 32 && uart_byte <= 126) $write("%c", uart_byte);
            else if (uart_byte == 10 || uart_byte == 13) $write("\n");
            else $write("<%h>", uart_byte);
        end
    end

    integer frame_count = 0;
    integer active_pixels = 0;
    logic prev_vsync;
    always_ff @(posedge clock) begin
        if (io_vga_vsync && !prev_vsync) begin
            frame_count++;
            if (frame_count % 60 == 0) begin
                $display("[VGA] Time: %t | Frames: %0d | Active Pixels: %0d", 
                         $time, frame_count, active_pixels);
            end
        end
        prev_vsync <= io_vga_vsync;
    end

    always_ff @(posedge clock) begin
        if (vga_div == 0 && !reset) begin
            if (io_vga_activevideo) active_pixels++;
        end
    end

    initial begin
        repeat (50_000_000) @(posedge clock);
        $display("\nTIMEOUT: Max cycles reached without magic write.");
        $finish;
    end

endmodule