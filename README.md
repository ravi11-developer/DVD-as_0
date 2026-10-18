LIBGL_ALWAYS_SOFTWARE=1 klayout ./mult_array.gds

# SEC-D (smth need to be done Here)
Sec -d exec successfully in time period 6 , but got 3.56 from formula 1.2*$t_{min}$


Need to find reason for this like why this happed - compete (status)
here is the possible reason **(need to verify)**
The discrepancy between your pre-route estimate of ~3.5 ns and the final physical requirement of 6.0 ns is caused by the transition from idealized logic assumptions to physical silicon realities under worst-case environmental conditions.

* **Process, Voltage, and Temperature (PVT) Corners:** In Part C, OpenSTA evaluated your design using only the typical corner (`tt_025C_1v80`), which assumes ideal manufacturing, room temperature (25°C), and optimal voltage (1.8V). LibreLane's physical signoff in Part D tests setup timing against the absolute worst-case "Slow-Slow" corner (`max_ss_100C_1v60`). Operating at a high temperature (100°C) and low voltage (1.6V) severely restricts transistor drive current, slowing down logic gates significantly compared to Part C.


* **Interconnect Parasitics (RC Delay):** Pre-route timing analysis evaluates gate delays but treats the wires connecting them as ideal paths with zero or negligible delay. During routing in Part D, LibreLane draws physical metal wires that introduce real resistance (R) and capacitance (C). Charging and discharging these physical wires adds significant propagation delay to your critical path.


* **Clock Tree Synthesis (CTS):** Part C assumes an ideal, instantaneous clock signal arriving at every flip-flop simultaneously. Part D builds a physical clock distribution network using buffers (`clkbuf`), which introduces clock skew (arrival time differences between flip-flops), insertion delay, and required margins for clock jitter. These real-world clock uncertainties consume a large portion of your available clock period.


* **Physical Routing Detours:** To satisfy manufacturing Design Rule Checks (DRC) and avoid metal shorts, the router cannot always use the shortest straight-line path between cells. Congestion forces detours, increasing wirelength and further exacerbating RC delays on critical nets.
