`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/16/2026 10:21:48 PM
// Design Name: 
// Module Name: TrueDualPortRAM32_DUT
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// -----------------------------------------------------------------------------
// True dual-port, dual-clock RAM behavioral model
// Modified to support Byte Enables (for RISC-V SB/SH/SW support) and Data Read
// -----------------------------------------------------------------------------
module TrueDualPortRAM32_DUT #(
    parameter DEPTH = 16384,      // Number of 32-bit words
    parameter ADDR_WIDTH = 14,    // Address width in bits
    parameter LOAD_OFFSET = 1024, // Offset for $readmemh
    parameter INIT_FILE = ""      // Filename to load (Optional)
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
    (* ram_style = "block", ram_decomp = "power" *) reg [31:0] mem [0:DEPTH-1];

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
        // Only load if INIT_FILE is provided (not empty string)
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem, LOAD_OFFSET);
        end
    end

endmodule
