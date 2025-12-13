`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/13/2025 03:43:36 PM
// Design Name: 
// Module Name: FPGA_Top
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


module FPGA_Top(
    input  sys_clk,
    input  sys_rst_n
    );
    
    logic cpu_clk;
    logic locked;
    
    clk_wiz_0 u_clock_gen (
        .clk_in1(sys_clk),
        .resetn(sys_rst_n),
        .clk_out1(cpu_clk),
        .locked(locked)
    );
    
    logic sys_reset = !sys_rst_n || !locked;
    
    Top u_cpu_top (
        .clock(cpu_clk),
        .reset(sys_reset)
    );
    
endmodule
