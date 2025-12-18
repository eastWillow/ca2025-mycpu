`timescale 1ns / 1ns
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
// hexdump -v -e '1/4 "%08x\n"' 2-mmio-trap/src/main/resources/nyancat.asmbin > 2-mmio-trap/vivado/nyancat.txt
// Use Repleace '\n' to ',' in nyancat.txt to generate the nyancat.coe file
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
    
    logic clk_wiz_reset;
    logic raw_cpu_reset;
    
    //Clock Wizard
    logic locked;
    logic bram_clock;
    
    // System reset
    logic reset;
    
    clk_wiz_0 u_clk_gen (
        .clk_in1(sys_clk),      // 100 MHz From ARTY7-35T on Board
        .reset(!clk_wiz_reset),  //
        .clk_out1(bram_clock),  // 25 MHz for BRAM
        .clk_out2(io_vga_pixclk),  // 31.5 MHz for VGA (640 x 480 @ 72Hz DMT)
        .locked(locked)         //
    );
    
    reg [4:0] counter;
    logic cpu_clock_raw;
    logic cpu_clock;
    always @(posedge bram_clock) begin
        if (!clk_wiz_reset) begin
            counter <= 0;
            cpu_clock_raw <= 0;
        end else begin
            if (counter == 9) begin 
                counter <= 0;
                cpu_clock_raw <= 1;
            end else begin 
                counter <= counter + 1;
                cpu_clock_raw <= 0;
            end
        end
    end
    
    BUFG u_bufg_cpu (
            .I(cpu_clock_raw), // 
            .O(cpu_clock)      //
    );
    
    // wait clock wizard lock
    logic io_instruction_valid;
    assign reset = (locked == 0) || !clk_wiz_reset;
    assign io_instruction_valid = !reset;
    
    // --------------------------------------------------------
    // CPU Signals
    // --------------------------------------------------------
    // Instruction Fetch
    logic [31:0] io_instruction_address;
    logic [31:0] io_instruction;

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
    // =========================================================
    // BRAM Interface Synchronization
    // =========================================================
    reg [2:0] cpu_clk_sync;
    logic cpu_rise_pulse;

    always @(posedge bram_clock) begin
        cpu_clk_sync <= {cpu_clk_sync[1:0], cpu_clock};
    end
    
    assign cpu_rise_pulse = (cpu_clk_sync[1] == 1'b1) && (cpu_clk_sync[2] == 1'b0);
    reg [31:0] bram_addr_reg;
    reg [31:0] bram_wdata_reg;
    reg [3:0]  bram_we_reg;
    reg bram_sel_stack_reg;
    
    always @(posedge bram_clock) begin
        if (cpu_rise_pulse) begin
            bram_addr_reg  <= io_memory_bundle_address;
            bram_wdata_reg <= io_memory_bundle_write_data;
// Stack BRAM 64KB (0x10000 bytes)
// Stack Top = 0x400000, Stack Base = 0x3F0000
            bram_sel_stack_reg <= (io_memory_bundle_address >= 32'h003F0000) && 
                                   (io_memory_bundle_address <= 32'h00400000);
            
            if (bram_sel_stack_reg) begin
                 bram_we_reg <= {io_memory_bundle_write_strobe_3, 
                                 io_memory_bundle_write_strobe_2, 
                                 io_memory_bundle_write_strobe_1, 
                                 io_memory_bundle_write_strobe_0} 
                                 & {4{io_memory_bundle_write_enable}} 
                                 & {4{io_deviceSelect == 0}};
            end else begin
                 bram_we_reg <= (!bram_sel_stack_reg) ? 
                                ({io_memory_bundle_write_strobe_3, 
                                  io_memory_bundle_write_strobe_2, 
                                  io_memory_bundle_write_strobe_1, 
                                  io_memory_bundle_write_strobe_0} 
                                  & {4{io_memory_bundle_write_enable}}
                                  & {4{io_deviceSelect == 0}})
                                : 4'b0;
            end
        end else begin
            bram_we_reg <= 4'b0;
        end
    end

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
            .douta(io_instruction)
    );
    blk_mem_gen_stack u_bram_ram (
        // Stack BRAM Port A is not used.
        .clka(bram_clock),
        .ena(1'b1),
        .wea(4'b0),
        .addra(bram_addr_reg[17:2]),
        .dina(32'b0),
        .douta(main_rdata),
        
        // --- Port B: Data Access (Read/Write) ---
        .clkb(bram_clock),
        .enb(1'b1),
        .web( bram_sel_stack_reg ? 4'b0 : bram_we_reg),
        .addrb(bram_addr_reg[17:2]),
        .dinb(bram_wdata_reg),
        .doutb()
    );
    // =========================================================================
    // 2. Stack BRAM 
    // =========================================================================
    // Mapping: 0x003F0000 - 0x00400000 (Vritual) -> 0x0000 - 0xFFFF (Physical)
    logic [31:0] stack_rdata;
    // 0x003FFFFC (Address Aliasing) -> 0xFFFC
    blk_mem_gen_stack u_bram_stack (
        // Stack BRAM Port A is not used.
        .clka(bram_clock),
        .ena(1'b1),
        .wea(4'b0),
        .addra(bram_addr_reg[17:2]),
        .dina(32'b0),
        .douta(stack_rdata),
        
        // --- Port B: Data Access (R/W) ---
        .clkb(bram_clock),
        .enb(1'b1),
        .web( bram_sel_stack_reg ? bram_we_reg : 4'b0 ),
        .addrb(bram_addr_reg[17:2]),
        .dinb(bram_wdata_reg),
        .doutb()
    );
    // =========================================================================
    // 3. Read BRAM Data Mux  
    // =========================================================================
    assign io_memory_bundle_read_data = bram_sel_stack_reg ? stack_rdata : main_rdata;

    logic cpu_reset;
    always @(posedge cpu_clock) begin
        cpu_reset <= raw_cpu_reset;
    end

    initial begin
        // Reset Clock Wizard
        clk_wiz_reset = 0;
        raw_cpu_reset = 1;
        #10;
        clk_wiz_reset = 1;

        io_regs_debug_read_address = 0;
        
        wait(cpu_clock == 1); // Wait for Reset Release
        wait(cpu_clock == 0); // Wait for Reset Release
        wait(cpu_clock == 1); // Wait for Reset Release
        raw_cpu_reset = 0;
    end

    // MMIO map
    // deviceSelect=1: VGA (0x20000000-0x2FFFFFFF)
    
    logic io_vga_vsync;
    logic io_vga_hsync;
    logic[5:0] io_vga_rrggbb;
    logic[3:0] VGA_R, VGA_G, VGA_B;
    logic io_activevideo;
    assign VGA_R[3:0] = {2{io_vga_rrggbb[1:0]}};
    assign VGA_G[3:0] = {2{io_vga_rrggbb[3:2]}};
    assign VGA_B[3:0] = {2{io_vga_rrggbb[5:4]}};
    
    logic[10:0] frame_count;
    integer file;
    reg [1023:0] filename;
    
    initial begin
        frame_count = 0;
    end
    
    // Handle Frame switching and file I/O operations
    always @(posedge io_vga_vsync) begin
        // Close the previous file if it is already open
        if (file != 0) begin
            $fclose(file);
            file = 0; // Reset file handle after closing
        end
    
        // Generate a new filename (e.g., frame_0.ppm, frame_1.ppm)
        // The path "../../../../" points to the Project Root in a standard Vivado setup
        $swrite(filename, "frame_%0d.ppm", frame_count);
        file = $fopen(filename, "w");
        
        if (file != 0) begin
            $display("Status: Capturing %s...", filename);
            // Write PPM Header: P3 (ASCII), Width, Height, Max Color Value
            $fwrite(file, "P3\n640 480\n255\n");
        end
    
        frame_count <= frame_count + 1;
    
        // Stop simulation after capturing a specific number of frames
//        if (frame_count == 5) begin
//            $display("Capture Complete: 5 frames saved to Project Root.");
//            $finish;
//        end
    end
    
    // Handle pixel data writing
    always @(posedge io_vga_pixclk) begin
        // Write data only if the file is open and the signal is within the Active Video region
        // Replace 'video_active' with your actual signal (e.g., Display Enable / DE)
        if (file != 0 && io_activevideo) begin
            // Extract 2-bit RGB and scale to 8-bit (Value * 85)
            $fwrite(file, "%3d %3d %3d ", 
                    ((io_vga_rrggbb >> 4) & 2'b11) * 85, // Red
                    ((io_vga_rrggbb >> 2) & 2'b11) * 85, // Green
                    ((io_vga_rrggbb >> 0) & 2'b11) * 85  // Blue
            );
        end
        
        // Add a newline at the end of each horizontal line (HSYNC transition) 
        // This improves PPM file readability and structure
        if (!io_vga_hsync && file != 0) begin
            $fwrite(file, "\n");
        end
    end
    
    logic [9:0]  io_vga_x_pos;
    logic [9:0]  io_vga_y_pos;

    Top u_Top (
        .clock(cpu_clock),
        .reset(cpu_reset),

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
        .io_regs_debug_read_data(io_regs_debug_read_data),
        .io_interrupt_flag(0),
        
        .io_vga_pixclk(io_vga_pixclk),
        .io_vga_vsync(io_vga_vsync),
        .io_vga_hsync(io_vga_hsync),
        .io_vga_rrggbb(io_vga_rrggbb),
        .io_vga_activevideo(io_activevideo),
        .io_vga_x_pos(io_vga_x_pos),
        .io_vga_y_pos(io_vga_y_pos)
    );
endmodule
