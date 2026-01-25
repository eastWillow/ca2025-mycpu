// =================================================================================
// Module      : rgb2dvi
// Type        : SystemVerilog (Wrapper)
// Function    : A drop-in replacement for Digilent's rgb2dvi IP, based on
//               wangxuan95's HDMI TX logic. It encodes parallel RGB video
//               into DVI/TMDS serial signals.
//
// Reference   : Inspired by Digilent's rgb2dvi Input Signal:
//               https://github.com/Digilent/vivado-library/blob/master/ip/rgb2dvi/src/rgb2dvi.vhd
//               Insipred By WangXuan95's FPGA-HDMI TMDS Encoder Output Signal:
//               https://github.com/WangXuan95/FPGA-HDMI
//
// Dependencies: This module requires the following sub-modules from wangxuan95:
//               - hdmi_tmds_encode.v
//               - hdmi_async_fifo.v
//               - hdmi_tddr.v
// =================================================================================

module rgb2dvi (
    input  logic        PixelClk,    // ~25MHz to ~150MHz
    input  logic        SerialClk,   // 5x PixelClk
    input  logic        aRst,        // Active High Reset

    // Video Interface
    input  logic [23:0] vid_pData,   // RGB888 {R[7:0], G[7:0], B[7:0]} (See mapping below)
    input  logic        vid_pVDE,    // Active High Video Data Enable
    input  logic        vid_pHSync,  // HSync
    input  logic        vid_pVSync,  // VSync

    // TMDS Output Interface
    output logic        TMDS_Clk_p,
    output logic        TMDS_Clk_n,
    output logic [2:0]  TMDS_Data_p, // [2]=Red, [1]=Green, [0]=Blue
    output logic [2:0]  TMDS_Data_n
);

    // 1. Reset Handling (Convert Active High to Active Low for internal logic)
    logic rstn_async;
    assign rstn_async = ~aRst;

    // 2. Map standard RGB24 input to internal signals
    // Standard rgb2dvi expects:
    // vid_pData[23:16] = Channel 2 (Red)
    // vid_pData[15:8]  = Channel 1 (Green) -> But standard DVI mapping often puts Blue on Ch0.
    // Let's assume standard RGB ordering: R[23:16], G[15:8], B[7:0]
    logic [7:0] d_red, d_green, d_blue;
    assign d_red   = vid_pData[23:16];
    assign d_green = vid_pData[7:0];    // Based on user's previous VHDL snippet: Green is Ch1 (7:0)
    assign d_blue  = vid_pData[15:8];   // Based on user's previous VHDL snippet: Blue is Ch0 (15:8)

    // NOTE: If colors look swapped, swap the assignments above.
    // Standard RGB888 is usually R[23:16], G[15:8], B[7:0].

    // 3. Reset Synchronization
    // We need to synchronize the reset to both PixelClk and SerialClk domains
    logic [3:0] rstn_x5_shift = 4'd0;
    logic       rstn_x5;
    assign rstn_x5 = rstn_x5_shift[3];

    always_ff @(posedge SerialClk or negedge rstn_async) begin
        if (~rstn_async) rstn_x5_shift <= 4'd0;
        else             rstn_x5_shift <= {rstn_x5_shift[2:0], 1'b1};
    end

    logic [3:0] rstn_main_shift = 4'd0;
    logic       rstn_main;
    assign rstn_main = rstn_main_shift[3];

    // Reset for PixelClk domain (sync de-assertion)
    always_ff @(posedge PixelClk or negedge rstn_x5) begin
        if (~rstn_x5) rstn_main_shift <= 4'd0;
        else          rstn_main_shift <= {rstn_main_shift[2:0], 1'b1};
    end

    // 4. TMDS Encoding
    // The encoders take 8-bit color + 2 control bits (HS/VS) and output 10-bit TMDS symbols.
    // Blue channel carries the Sync signals.
    logic h_en; // Enable signal for FIFO
    logic [9:0] h_tmds0_bits, h_tmds1_bits, h_tmds2_bits;

    // Channel 2: Red (Control D0=0, D1=0)
    hdmi_tmds_encode u_tmds_encode_red (
        .rstn        (rstn_main),
        .clk         (PixelClk),
        .i_en        (1'b1),        // Always enabled to transmit continuous stream (incl. blanking)
        .i_vde       (vid_pVDE),
        .i_vd        (d_red),
        .i_cd        (2'b00),       // Red channel carries no control data
        .o_en        (),            // Not used
        .o_tmds_bits (h_tmds2_bits)
    );

    // Channel 1: Green (Control D0=0, D1=0)
    hdmi_tmds_encode u_tmds_encode_green (
        .rstn        (rstn_main),
        .clk         (PixelClk),
        .i_en        (1'b1),
        .i_vde       (vid_pVDE),
        .i_vd        (d_green),
        .i_cd        (2'b00),       // Green channel carries no control data
        .o_en        (),
        .o_tmds_bits (h_tmds1_bits)
    );

    // Channel 0: Blue (Carries HSync and VSync)
    hdmi_tmds_encode u_tmds_encode_blue (
        .rstn        (rstn_main),
        .clk         (PixelClk),
        .i_en        (1'b1),
        .i_vde       (vid_pVDE),
        .i_vd        (d_blue),
        .i_cd        ({vid_pVSync, vid_pHSync}), // {C1, C0}
        .o_en        (h_en),                     // Use this valid signal for FIFO
        .o_tmds_bits (h_tmds0_bits)
    );

    // 5. Clock Domain Crossing (Async FIFO)
    // Crosses 30-bit parallel TMDS data from PixelClk to SerialClk
    logic       j_en;
    logic       j_fetch;
    logic [9:0] j_tmds0_bits, j_tmds1_bits, j_tmds2_bits;
    logic       half_empty; // Unused in this config as we don't throttle source

    hdmi_async_fifo #(
        .DW(30),
        .EA(5)
    ) u_hdmi_async_fifo (
        .i_rstn       (rstn_main),
        .i_clk        (PixelClk),
        .i_tready     (),             // We ignore backpressure; VGA timing is rigid
        .i_tvalid     (h_en),
        .i_tdata      ({h_tmds0_bits, h_tmds1_bits, h_tmds2_bits}),

        .o_rstn       (rstn_x5),
        .o_clk        (SerialClk),
        .o_tready     (j_fetch),      // Read strobe generated by serializer state machine
        .o_tvalid     (j_en),
        .o_tdata      ({j_tmds0_bits, j_tmds1_bits, j_tmds2_bits}),
        .w_half_empty (half_empty)
    );

    // 6. Serializer Control (Modulo-5 Counter)
    // DVI uses 10-bit symbols. With DDR output, we need 5 clock cycles of SerialClk to send 10 bits.
    logic [2:0] j_cnt5 = 3'd0;
    logic       j_fetch_start = 1'b0;

    always_ff @(posedge SerialClk or negedge rstn_x5) begin
        if (~rstn_x5) begin
            j_cnt5        <= 3'd0;
            j_fetch_start <= 1'b0;
            j_fetch       <= 1'b0;
        end else begin
            // Count 0..4
            j_cnt5  <= j_cnt5[2] ? 3'd0 : (j_cnt5 + 3'd1);

            // Start fetching once we have valid data from FIFO
            if (j_en & j_cnt5[2])
                j_fetch_start <= 1'b1;

            // Generate read strobe every 5th cycle
            j_fetch <= j_cnt5[2] & j_fetch_start;
        end
    end

    // 7. Parallel to Serial Conversion (Shift Registers)
    logic [9:0] k_tmds0_bits = 10'd0;
    logic [9:0] k_tmds1_bits = 10'd0;
    logic [9:0] k_tmds2_bits = 10'd0;
    logic [9:0] k_tmdsc_bits = 10'd0;

    always_ff @(posedge SerialClk) begin
        if (j_fetch) begin
            // Load new 10-bit symbol
            k_tmds0_bits <= j_tmds0_bits;
            k_tmds1_bits <= j_tmds1_bits;
            k_tmds2_bits <= j_tmds2_bits;
            k_tmdsc_bits <= 10'b0000011111; // 10-bit clock pattern (0000011111 -> output 010101...)
        end else begin
            // Shift out (LSB first for HDMI/DVI? wangxuan95 shifts right, outputting [1:0])
            k_tmds0_bits <= k_tmds0_bits >> 2;
            k_tmds1_bits <= k_tmds1_bits >> 2;
            k_tmds2_bits <= k_tmds2_bits >> 2;
            k_tmdsc_bits <= k_tmdsc_bits >> 2;
        end
    end

    // 8. Output Buffers (DDR)
    // We map internal channels to standard rgb2dvi outputs:
    // Ch2 = Red, Ch1 = Green, Ch0 = Blue/Sync
    logic hdmi_tx0_p, hdmi_tx0_n; // Blue
    logic hdmi_tx1_p, hdmi_tx1_n; // Green
    logic hdmi_tx2_p, hdmi_tx2_n; // Red
    logic hdmi_clk_p_int, hdmi_clk_n_int;

    hdmi_tddr u0p_ddr (SerialClk,  k_tmds0_bits[1:0], hdmi_tx0_p);
    hdmi_tddr u0n_ddr (SerialClk, ~k_tmds0_bits[1:0], hdmi_tx0_n);

    hdmi_tddr u1p_ddr (SerialClk,  k_tmds1_bits[1:0], hdmi_tx1_p);
    hdmi_tddr u1n_ddr (SerialClk, ~k_tmds1_bits[1:0], hdmi_tx1_n);

    hdmi_tddr u2p_ddr (SerialClk,  k_tmds2_bits[1:0], hdmi_tx2_p);
    hdmi_tddr u2n_ddr (SerialClk, ~k_tmds2_bits[1:0], hdmi_tx2_n);

    hdmi_tddr u3p_ddr (SerialClk,  k_tmdsc_bits[1:0], hdmi_clk_p_int);
    hdmi_tddr u3n_ddr (SerialClk, ~k_tmdsc_bits[1:0], hdmi_clk_n_int);

    // Map to Output Ports
    assign TMDS_Clk_p = hdmi_clk_p_int;
    assign TMDS_Clk_n = hdmi_clk_n_int;

    // Combining into bus [2:0] (2:Red, 1:Green, 0:Blue)
    assign TMDS_Data_p = {hdmi_tx2_p, hdmi_tx1_p, hdmi_tx0_p};
    assign TMDS_Data_n = {hdmi_tx2_n, hdmi_tx1_n, hdmi_tx0_n};

endmodule