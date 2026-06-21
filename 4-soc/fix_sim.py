import re

with open('verilog/verilator/sim.cpp', 'r') as f:
    code = f.read()

# Remove VGA references
code = re.sub(r'top->io_vga_pixclk =.*?;', '', code)
code = re.sub(r'top->io_vga_pixclk\b', '0', code)

code = re.sub(r'top->io_vga_rrggbb\b', '0', code)
code = re.sub(r'top->io_vga_activevideo\b', '0', code)
code = re.sub(r'top->io_vga_vsync\b', '0', code)
code = re.sub(r'top->io_vga_hsync\b', '0', code)
code = re.sub(r'top->io_vga_x_pos\b', '0', code)
code = re.sub(r'top->io_vga_y_pos\b', '0', code)

# Remove UART references
code = re.sub(r'top->io_uart_rxd =.*?;', '', code)
code = re.sub(r'top->io_uart_rxd\b', '1', code)
code = re.sub(r'top->io_uart_txd\b', '1', code)

with open('verilog/verilator/sim.cpp', 'w') as f:
    f.write(code)
