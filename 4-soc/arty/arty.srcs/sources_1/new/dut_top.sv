// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps


module dut_top (
    input wire CLK100MHZ,      // Arty 100MHz Oscillator
    input wire ck_rst,         // Arty Reset Button (Active Low)

    // UART (USB-UART Bridge)
    input  wire uart_txd_in,   // FPGA RX
    output wire uart_rxd_out,  // FPGA TX

    // VGA Pmod (Headers JB/JC)
//    output wire [3:0] VGA_R,
//    output wire [3:0] VGA_G,
//    output wire [3:0] VGA_B,
//    output wire       VGA_HS_O,
//    output wire       VGA_VS_O,
    
    // HDMI Pmod (Headers JC)
    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n,

    // Debug LEDs
    output reg [7:0] led
);

    // -------------------------------------------------------------------------
    // Parameters & Constants (Matching tb_top)
    // -------------------------------------------------------------------------
    parameter SEGMENT_SIZE_BYTES = 64 * 1024; 
    
    localparam IMEM_BASE         = 32'h0000_0000;
    localparam DMEM_BASE         = 32'h0010_0000;
    localparam SMEM_BASE         = 32'h003F_0000; 

    // Magic Values for Hardware "Pass" indication
    localparam MAGIC_ADDR    = 32'h0000_0100;
    localparam MAGIC_VAL     = 32'hCAFE_F00D;
    localparam UART_PASS     = 32'hF;
    localparam VGA_PASS      = 32'h3F;

    // -------------------------------------------------------------------------
    // 1. Clock Generation (IP: clk_wiz_0)
    // -------------------------------------------------------------------------
    wire clk_cpu;    // 100 MHz
    wire clk_vga;    // 31.5 MHz
    wire clk_serial; // 31.5 * 5 = 157.5 MHz for HDMI Serial
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
        .clk_serial (clk_serial),
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
    wire [5:0]  io_vga_rrggbb;
    wire        io_vga_hsync_int;
    wire        io_vga_vsync_int;
    wire        io_vga_activevideo;

    // -------------------------------------------------------------------------
    // 3. DUT Instantiation
    // -------------------------------------------------------------------------
    Top dut (
        .clock                         (clk_cpu),
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
        .io_uart_interrupt             (),

        // VGA Signals
        .io_vga_pixclk                 (clk_vga),  
        .io_vga_vsync                  (io_vga_vsync_int),
        .io_vga_hsync                  (io_vga_hsync_int),
        .io_vga_activevideo            (io_vga_activevideo),
        .io_vga_rrggbb                 (io_vga_rrggbb),
        .io_vga_x_pos                  (),
        .io_vga_y_pos                  (),
        
        // Debug
        .io_cpu_debug_read_address     (),
        .io_cpu_debug_read_data        (),
        .io_cpu_csr_debug_read_address (),
        .io_cpu_csr_debug_read_data    ()
    );

    // -------------------------------------------------------------------------
    // 4. Memory Subsystem (Multi-Segment Architecture)
    // -------------------------------------------------------------------------
    
    // Address Decoding Helper (Same as tb_top)
    function automatic logic [1:0] decode_address(logic [31:0] addr);
        if (addr >= IMEM_BASE && addr < (IMEM_BASE + SEGMENT_SIZE_BYTES))
            return 2'b00; 
        else if (addr >= DMEM_BASE && addr < (DMEM_BASE + SEGMENT_SIZE_BYTES))
            return 2'b01; 
        else if (addr >= SMEM_BASE && addr < (SMEM_BASE + SEGMENT_SIZE_BYTES))
            return 2'b10; 
        else
            return 2'b11;
    endfunction

    // ------------------------------
    // 4.1 Instruction Fetch Logic
    // ------------------------------
    wire [31:0] imem_doutb, dmem_doutb, smem_doutb;
    wire [1:0]  fetch_sel;
    reg  [1:0]  fetch_sel_r; 
    
    assign fetch_sel = decode_address(io_instruction_req);

    always @(posedge clk_cpu) begin
        fetch_sel_r <= fetch_sel;
        // In simulation this was io_instruction_address <= io_instruction_req
        // But in dut_top io_instruction_address is an output from DUT?
        // Wait, check Top.v definition. Usually address is output FROM CPU.
        // In tb_top: .io_instruction_address(io_instruction_address) -> wire driven by CPU?
        // Actually, looking at Top.v instantiation in tb_top:
        // .io_instruction_address(io_instruction_address) -> It is an OUTPUT from Top.
        // So we don't assign it here.
    end

    // MUX Output for Instruction
    always_comb begin
        case (fetch_sel_r)
            2'b00: io_instruction = imem_doutb;
            2'b01: io_instruction = dmem_doutb;
            2'b10: io_instruction = smem_doutb;
            default: io_instruction = 32'h0;
        endcase
    end

    // ------------------------------
    // 4.2 Data Access Logic
    // ------------------------------
    wire [31:0] imem_douta, dmem_douta, smem_douta;
    wire [3:0]  imem_we, dmem_we, smem_we;
    wire [1:0]  data_sel;
    reg  [1:0]  data_sel_r;
    
    assign data_sel = decode_address(io_mem_slave_address);

    // Write Enable Decoding
    wire [3:0] global_we = {
        io_mem_slave_write && io_mem_slave_write_strobe_3,
        io_mem_slave_write && io_mem_slave_write_strobe_2,
        io_mem_slave_write && io_mem_slave_write_strobe_1,
        io_mem_slave_write && io_mem_slave_write_strobe_0
    };

    assign imem_we = (data_sel == 2'b00) ? global_we : 4'b0;
    assign dmem_we = (data_sel == 2'b01) ? global_we : 4'b0;
    assign smem_we = (data_sel == 2'b10) ? global_we : 4'b0;

    // Read Data Control
    always @(posedge clk_cpu) begin
        data_sel_r <= data_sel;
        io_mem_slave_read_valid <= io_mem_slave_read;
    end

    always @(posedge clk_cpu) begin
        if (sys_reset) begin
            led[7:4] <= 4'b0;
        end 
        else begin
            // Hardware Magic Check: If test passes, turn on all LEDs
            if (io_mem_slave_write && 
                io_mem_slave_address == MAGIC_ADDR && 
                io_mem_slave_write_data == MAGIC_VAL) begin
                // We can't peek into RAM easily in HW logic for the result 
                // without adding read port logic, so we just assume if it writes
                // Magic Val to Magic Addr, it reached the end.
                // You could enhance this to latch the result.
                led[7:4] <= 4'b1111; 
            end
        end
    end

    // Default LED behavior (if not passed yet): Show PC lower bits
    always @(posedge clk_cpu) begin
        if (!(io_mem_slave_write && io_mem_slave_address == MAGIC_ADDR)) begin
             led[3:0] <= io_instruction_req[5:2];
        end
    end

    // Data Read MUX
    always_comb begin
        case (data_sel_r)
            2'b00: io_mem_slave_read_data = imem_douta;
            2'b01: io_mem_slave_read_data = dmem_douta;
            2'b10: io_mem_slave_read_data = smem_douta;
            default: io_mem_slave_read_data = 32'h0;
        endcase
    end

    // ------------------------------
    // 4.3 RAM Instantiations
    // ------------------------------
    // Note: Addresses are shifted by 2 (word alignment) and masked/subtracted by base.
    // Address Width 14 => 16K words => 64KB.

    // IMEM: Load program.mem
    TrueDualPortRAM32_DUT #(
        .DEPTH(8192),
        .ADDR_WIDTH(13),
        .LOAD_OFFSET(1024),
        .INIT_FILE("program.mem")
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

    // DMEM: Empty Init
    TrueDualPortRAM32_DUT #(
        .DEPTH(8192),
        .ADDR_WIDTH(13),
        .LOAD_OFFSET(1024),
        .INIT_FILE("")
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

    // SMEM: Empty Init
    TrueDualPortRAM32_DUT #(
        .DEPTH(8192),
        .ADDR_WIDTH(13),
        .LOAD_OFFSET(1024),
        .INIT_FILE("")
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
    // 5. IO Output Mapping
    // -------------------------------------------------------------------------
//    assign VGA_R[3:0] = {2{io_vga_rrggbb[5:4]}};
//    assign VGA_G[3:0] = {2{io_vga_rrggbb[3:2]}};
//    assign VGA_B[3:0] = {2{io_vga_rrggbb[1:0]}};
    
//    assign VGA_HS_O = io_vga_hsync_int;
//    assign VGA_VS_O = io_vga_vsync_int;
    
    logic [23:0] rgb2dvi_in;
    
    // Channel 2 (Red)   : vid_pData[23:16] <- io_vga_rrggbb[5:4]
    // Channel 0 (Blue)  : vid_pData[15:8]  <- io_vga_rrggbb[1:0]
    // Channel 1 (Green) : vid_pData[7:0]   <- io_vga_rrggbb[3:2]
    
    assign rgb2dvi_in[23:16] = {4{io_vga_rrggbb[5:4]}}; // Red
    assign rgb2dvi_in[15:8]  = {4{io_vga_rrggbb[1:0]}}; // Blue
    assign rgb2dvi_in[7:0]   = {4{io_vga_rrggbb[3:2]}}; // Green
    
    rgb2dvi u_rgb2dvi (
        .PixelClk(clk_vga),
        .SerialClk(clk_serial),
        .aRst( sys_reset ), 
    
        .vid_pData(rgb2dvi_in),
        .vid_pVDE(io_vga_activevideo),
        .vid_pHSync(io_vga_hsync_int),
        .vid_pVSync(io_vga_vsync_int),
    
        .TMDS_Clk_p(tmds_clk_p),
        .TMDS_Clk_n(tmds_clk_n),
        .TMDS_Data_p(tmds_data_p),
        .TMDS_Data_n(tmds_data_n)
    );
    
endmodule