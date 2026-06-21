import re

with open('verilog/verilator/sim.cpp', 'r') as f:
    code = f.read()

# Remove io_instruction references
code = re.sub(r'top->io_instruction_valid =.*?;', '', code)
code = re.sub(r'top->io_instruction =.*?;', '', code)
code = re.sub(r'inst = mem.read\(top->io_instruction_address\);', '', code)
code = re.sub(r'top->io_instruction_address', '0', code)
code = re.sub(r'uint32_t inst =.*?;', '', code)

with open('verilog/verilator/sim.cpp', 'w') as f:
    f.write(code)
