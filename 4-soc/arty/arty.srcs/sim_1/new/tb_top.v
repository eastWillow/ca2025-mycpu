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
    parameter MEM_SIZE_BYTES = 4 * 1024 * 1024; // 4MB
    parameter MEM_WORDS      = MEM_SIZE_BYTES / 4;
    
    // UART Timing: Based on C++ "CYCLES_PER_BIT = 434"
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

    // I/O Signals connecting to DUT
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
    
    // UART
    logic        io_uart_txd;
    logic        io_uart_rxd;

    // VGA
    logic        io_vga_pixclk;
    logic        io_vga_vsync;
    logic        io_vga_hsync;
    logic        io_vga_activevideo;
    logic [7:0]  io_vga_rrggbb; // Assuming 8-bit total color width based on C++ masking
    logic [15:0] io_vga_x_pos;
    logic [15:0] io_vga_y_pos;

    // Debug (Unused inputs tied to 0)
    logic [31:0] io_cpu_debug_read_address = 0;
    logic [31:0] io_cpu_csr_debug_read_address = 0;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    // Note: Signal names must match your generated Verilog module definition.
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
    // Clock & Reset Generation
    // -------------------------------------------------------------------------
    initial begin
        clock = 0;
        forever #5 clock = ~clock; // 100 MHz (10ns period)
    end

    // VGA Pixel Clock Generation (1/4 System Clock)
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
            // Toggle every 4 cycles to mimic C++ logic: if (++vga_div >= 4) ...
            if (vga_div == 3) begin 
                vga_div <= 0;
                io_vga_pixclk <= ~io_vga_pixclk;
            end
        end
    end

    // Reset Sequence
    initial begin
        reset = 1;
        io_instruction_valid = 1;
        io_signal_interrupt = 0;
        
        repeat(10) @(posedge clock);
        reset = 0;
    end

    // -------------------------------------------------------------------------
    // Memory Model (4MB)
    // -------------------------------------------------------------------------
    logic [31:0] memory [0:MEM_WORDS-1];
    
    // Load Program
    initial begin
        // Initialize memory to 0
        for (int i=0; i < MEM_WORDS; i++) memory[i] = 32'h0;

        // Load hex file (User must convert binary to hex)
        // Format: @address data (see $readmemh documentation)
        // 2. Load hex file starting at WORD index 0x400 (Byte address 0x1000)
        // Syntax: $readmemh("file", memory_array, start_index)
        $readmemh("program.hex", memory, 32'h400);
        $display("Memory initialized from program.hex at offset 0x1000");
    end

    // INSTRUCTION FETCH
    // We use the FULL address in the sensitive list and logic
    always_ff @(posedge clock) begin
        if (io_instruction_req[1:0] != 2'b00) begin
            $display("[Error] Time %t: PC Misaligned! Address: %h", $time, io_instruction_req);
        end
        // 1. Debug Check: Is the address aligned?
        // 2. Convert Byte Address -> Word Index
        // We calculate this locally so you can see the math if needed
        if ((io_instruction_req >> 2) < MEM_WORDS) begin
            io_instruction = memory[io_instruction_req >> 2];
            io_instruction_address = io_instruction_req;
        end else begin
            io_instruction = 32'h0; // Out of bounds -> NOP/Zero
        end
    end
    
    always_comb begin
    end

    // DATA ACCESS (Read/Write)
    always_ff @(posedge clock) begin
        // Default valid signal
        io_mem_slave_read_valid <= 0;

        // ---------------------------------------------------------
        // READ OPERATION
        // ---------------------------------------------------------
        if (io_mem_slave_read) begin
            // Debug: Check alignment
            if (io_mem_slave_address[1:0] != 2'b00) begin
                 $display("[Warning] Time %t: Data Read Misaligned! Addr: %h", $time, io_mem_slave_address);
            end

            // Debug: Check Bounds
            if ((io_mem_slave_address >> 2) >= MEM_WORDS) begin
                 $display("[Error] Time %t: Read Out of Bounds! Addr: %h", $time, io_mem_slave_address);
                 io_mem_slave_read_data <= 32'hDEADBEEF; // Debug value
            end else begin
                // Normal Read
                io_mem_slave_read_data <= memory[io_mem_slave_address >> 2];
            end
            
            io_mem_slave_read_valid <= 1;
        end

        // ---------------------------------------------------------
        // WRITE OPERATION
        // ---------------------------------------------------------
        if (io_mem_slave_write) begin
            // Debug: Print every write to console
            // $display("Write at %h: Data=%h Strb=%b", io_mem_slave_address, io_mem_slave_write_data, {io_mem_slave_write_strobe_3, io_mem_slave_write_strobe_2, io_mem_slave_write_strobe_1, io_mem_slave_write_strobe_0});

            if ((io_mem_slave_address >> 2) < MEM_WORDS) begin
                // Use the full address variable to calculate index right here
                int idx = io_mem_slave_address >> 2;

                if (io_mem_slave_write_strobe_0) memory[idx][7:0]   <= io_mem_slave_write_data[7:0];
                if (io_mem_slave_write_strobe_1) memory[idx][15:8]  <= io_mem_slave_write_data[15:8];
                if (io_mem_slave_write_strobe_2) memory[idx][23:16] <= io_mem_slave_write_data[23:16];
                if (io_mem_slave_write_strobe_3) memory[idx][31:24] <= io_mem_slave_write_data[31:24];
            end

            // Check for Magic Termination Address
            if (io_mem_slave_address == MAGIC_ADDR && io_mem_slave_write_data == MAGIC_VAL) begin
                logic [31:0] result;
                result = memory[RESULT_ADDR >> 2]; // Read result from 0x104
                
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
    // UART Loopback & Decoder
    // -------------------------------------------------------------------------
    
    // Loopback: TX -> RX (matches C++ non-interactive mode)
    assign io_uart_rxd = io_uart_txd;

    // UART Decoder (Simulated Terminal)
    // Prints characters sent by CPU to the simulator console
    logic [7:0] uart_byte;
    
    initial begin
        forever begin
            // 1. Wait for Start Bit (falling edge of TX)
            @(negedge io_uart_txd);
            
            // 2. Wait 1.5 bit periods to sample middle of bit 0
            repeat (CYCLES_PER_BIT + (CYCLES_PER_BIT/2)) @(posedge clock);
            
            // 3. Sample 8 bits
            for (int i = 0; i < 8; i++) begin
                uart_byte[i] = io_uart_txd;
                repeat (CYCLES_PER_BIT) @(posedge clock);
            end

            // 4. Print character
            // Only print printable chars or newlines to keep log clean
            if (uart_byte >= 32 && uart_byte <= 126) begin
                $write("%c", uart_byte);
            end else if (uart_byte == 10 || uart_byte == 13) begin
                $write("\n");
            end else begin
                $write("<%h>", uart_byte);
            end
        end
    end

    // -------------------------------------------------------------------------
    // VGA Diagnostics
    // -------------------------------------------------------------------------
    integer frame_count = 0;
    integer active_pixels = 0;
    
    // Monitor VSYNC to count frames
    logic prev_vsync;
    always_ff @(posedge clock) begin
        if (io_vga_vsync && !prev_vsync) begin
            frame_count++;
            // Report every 60 frames (approx 1 sec)
            if (frame_count % 60 == 0) begin
                $display("[VGA] Time: %t | Frames: %0d | Active Pixels: %0d", 
                         $time, frame_count, active_pixels);
            end
        end
        prev_vsync <= io_vga_vsync;
    end

    // Count active pixels (only when pixel clock rises)
    always_ff @(posedge clock) begin
        // Logic mimics C++: if (top->io_vga_pixclk ...)
        // We need to detect the rising edge of the generated pixclk signal
        // Since pixclk is generated logic, we can't reliably @(posedge) it inside this module 
        // without race conditions against the `vga_div` block. 
        // Instead, we look at the enable condition:
        if (vga_div == 0 && !reset) begin
            if (io_vga_activevideo) begin
                active_pixels++;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Watchdog
    // -------------------------------------------------------------------------
    initial begin
        repeat (50_000_000) @(posedge clock); // 50M cycle timeout
        $display("\nTIMEOUT: Max cycles reached without magic write.");
        $finish;
    end

endmodule