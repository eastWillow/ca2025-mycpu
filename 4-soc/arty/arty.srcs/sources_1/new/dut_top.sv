// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps

module dut_top (
    input wire CLK100MHZ,      // Arty 100MHz Oscillator
    input wire ck_rst,         // Arty Reset Button (Active Low)

    // UART (USB-UART Bridge)
    input  wire uart_txd_in,   // FPGA RX
    output wire uart_rxd_out,  // FPGA TX

    // VGA Pmod (Headers JB/JC)
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire       vga_hs,
    output wire       vga_vs,
    
    // Debug LEDs
    output wire [3:0] led
);

    // -------------------------------------------------------------------------
    // 1. Clock Generation (IP: clk_wiz_0)
    // -------------------------------------------------------------------------
    wire clk_cpu;    // 100 MHz
    wire clk_vga;    // 31.5 MHz
    wire locked;
    wire mmcm_reset;
    wire sys_reset;

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

    // -------------------------------------------------------------------------
    // 2. Internal Signals
    // -------------------------------------------------------------------------
    wire        io_instruction_valid = 1'b1;
    wire [31:0] io_instruction_address;
    reg  [31:0] io_instruction;
    wire [31:0] io_instruction_req;

    wire        io_mem_slave_read;
    reg         io_mem_slave_read_valid;
    wire [31:0] io_mem_slave_address;
    reg  [31:0] io_mem_slave_read_data;
    
    wire        io_mem_slave_write;
    wire [31:0] io_mem_slave_write_data;
    wire        io_mem_slave_write_strobe_0;
    wire        io_mem_slave_write_strobe_1;
    wire        io_mem_slave_write_strobe_2;
    wire        io_mem_slave_write_strobe_3;

    wire        io_signal_interrupt = 1'b0;

    // VGA Internal
    wire [7:0]  io_vga_rrggbb;
    wire        io_vga_hsync_int;
    wire        io_vga_vsync_int;
    wire        io_vga_activevideo;

    // -------------------------------------------------------------------------
    // 3. DUT Instantiation
    // -------------------------------------------------------------------------
    Top dut (
        .clock                         (clk_cpu),   // CPU runs at 100MHz
        .reset                         (sys_reset),
        
        // Instruction Interface
        .io_instruction_valid          (io_instruction_valid),
        .io_instruction                (io_instruction),
        .io_instruction_req            (io_instruction_req),
        .io_instruction_address        (io_instruction_address),
        
        // Data Memory Interface
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
        
        // Interrupt & UART
        .io_signal_interrupt           (io_signal_interrupt),
        .io_uart_txd                   (uart_rxd_out),
        .io_uart_rxd                   (uart_txd_in),
        
        // VGA Signals
        .io_vga_pixclk                 (clk_vga),  // 31.5 MHz Pixel Clock
        .io_vga_vsync                  (io_vga_vsync_int),
        .io_vga_hsync                  (io_vga_hsync_int),
        .io_vga_activevideo            (io_vga_activevideo),
        .io_vga_rrggbb                 (io_vga_rrggbb),
        .io_vga_x_pos                  (),
        .io_vga_y_pos                  (),
        
        // Debug
        .io_cpu_debug_read_address     (),
        .io_cpu_csr_debug_read_address ()
    );

    // -------------------------------------------------------------------------
    // 4. Synthesizable Memory (True Dual Port RAM - 64KB)
    // -------------------------------------------------------------------------
    
    wire [3:0] ram_wea;
    wire [13:0] ram_addra; // Data Address
    wire [13:0] ram_addrb; // Instruction Address
    wire [31:0] ram_douta; // Data Out
    wire [31:0] ram_doutb; // Instruction Out
    
    // Address Mapping (Alias to 64KB: Mask upper bits)
    assign ram_addra = io_mem_slave_address[15:2];
    assign ram_addrb = io_instruction_req[15:2];

    // Byte Enable Generation for Write
    assign ram_wea = {
        io_mem_slave_write && io_mem_slave_write_strobe_3,
        io_mem_slave_write && io_mem_slave_write_strobe_2,
        io_mem_slave_write && io_mem_slave_write_strobe_1,
        io_mem_slave_write && io_mem_slave_write_strobe_0
    };

    TrueDualPortRAM32_DUT #(
        .DEPTH(16384),     // 16K * 4 bytes = 64KB
        .ADDR_WIDTH(14),
        .LOAD_OFFSET(1024) // 0x1000 bytes
    ) unified_memory (
        // Port A: CPU Data (RW) - CPU Domain
        .clka  (clk_cpu),
        .wea   (ram_wea),
        .addra (ram_addra),
        .dina  (io_mem_slave_write_data),
        .douta (ram_douta),

        // Port B: CPU Instruction (R) - CPU Domain
        .clkb  (clk_cpu),
        .addrb (ram_addrb),
        .doutb (ram_doutb)
    );

    // Capture Read Data from RAM
    always @(posedge clk_cpu) begin
        // Data Read
        io_mem_slave_read_valid <= io_mem_slave_read;
        io_mem_slave_read_data  <= ram_douta;

        // Instruction Fetch
        io_instruction <= ram_doutb;
    end

    // -------------------------------------------------------------------------
    // 5. IO Mapping
    // -------------------------------------------------------------------------
    assign vga_r = io_vga_activevideo ? {io_vga_rrggbb[7:5], 1'b0} : 4'b0;
    assign vga_g = io_vga_activevideo ? {io_vga_rrggbb[4:2], 1'b0} : 4'b0;
    assign vga_b = io_vga_activevideo ? {io_vga_rrggbb[1:0], 2'b0} : 4'b0;
    
    assign vga_hs = io_vga_hsync_int;
    assign vga_vs = io_vga_vsync_int;

    // LEDs show lower bits of PC
    assign led = io_instruction_req[5:2];

endmodule

// -----------------------------------------------------------------------------
// True dual-port, dual-clock RAM behavioral model
// Modified to support Byte Enables (for RISC-V SB/SH/SW support) and Data Read
// -----------------------------------------------------------------------------
module TrueDualPortRAM32_DUT #(
    parameter DEPTH = 16384,      // Number of 32-bit words
    parameter ADDR_WIDTH = 14,    // Address width in bits
    parameter LOAD_OFFSET = 1024  // Offset for $readmemh
) (
    // Port A: Data Port (RW)
    input wire clka,
    input wire [3:0] wea,         // Modified: 4-bit Byte Enable
    input wire [ADDR_WIDTH-1:0] addra,
    input wire [31:0] dina,
    output reg [31:0] douta,      // Added: Data Read Output

    // Port B: Instruction Port (Read Only)
    input wire clkb,
    input wire [ADDR_WIDTH-1:0] addrb,
    output reg [31:0] doutb
);

    // RAM storage
    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];

    // Port A: Read/Write
    always @(posedge clka) begin
        if (wea[0]) mem[addra][7:0]   <= dina[7:0];
        if (wea[1]) mem[addra][15:8]  <= dina[15:8];
        if (wea[2]) mem[addra][23:16] <= dina[23:16];
        if (wea[3]) mem[addra][31:24] <= dina[31:24];
        douta <= mem[addra];
    end

    // Port B: Read Only
    always @(posedge clkb) begin
        doutb <= mem[addrb];
    end

    // Initialize memory
    integer i;
    initial begin
        // 1. Clear memory
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = 32'h0;
        end
        // 2. Load Program (Crucial for CPU operation)
        $readmemh("program.mem", mem, LOAD_OFFSET);
    end

endmodule