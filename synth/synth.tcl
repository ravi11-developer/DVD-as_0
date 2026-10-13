# Set the Liberty file path using the PDK_ROOT environment variable
set lib $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

# Step 1: Read the design
yosys read_verilog rtl/full_adder.v rtl/mult_array.v

# Step 2: Generic synthesis; flatten the full adders into one module
yosys synth -top mult_array -flatten

# Step 3: Map flip-flops to SKY130 flip-flop cells
yosys dfflibmap -liberty $lib

# Step 4: Map the logic to SKY130 gate cells
yosys abc -liberty $lib

# Step 5: Remove unused wires
yosys opt_clean -purge

# Step 6: Write the cell and area report
yosys tee -o synth/mult_array_stat.rpt stat -liberty $lib

# Step 7: Write the gate-level netlist
yosys write_verilog -noattr synth/mult_array_netlist.v