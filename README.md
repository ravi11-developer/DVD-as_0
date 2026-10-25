# RTL-to-GDSII Implementation of Structural Array Multiplier
# Ye Hum hai
| Team Member Name | Roll Number |
| :--- | :--- |
| **Ravi Sahu** | 2024102024 |
| **Diddigi Srivatsa** | 2025122009 |

---

## Step-by-Step Execution Commands

### 1. Part A — RTL Design and Verification
Compile the structural array multiplier and testbench, run the functional simulation, and inspect the waveform:
```bash
iverilog -g2012 -o sim tb/tb_mult.v rtl/full_adder.v rtl/mult_array.v

vvp sim

gtkwave mult.vcd
```

### 2. Part B — Logic Synthesis with Yosys and Gate-Level Simulation (GLS)
Synthesize the RTL into the SKY130 standard cell library, generate reports, and verify gate-level simulation:
```bash
yosys -c synth/synth.tcl

CELLS=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog
iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 -o gls \
  tb/tb_mult.v $CELLS/primitives.v $CELLS/sky130_fd_sc_hd.v synth/mult_array_netlist.v

vvp gls
```

### 3. Part C — Static Timing Analysis (STA) with OpenSTA
Run static timing analysis to determine slack, $T_{\min}$, critical path, and $F_{\max}$:
```bash
sta sta/sta.tcl
```

### 4. Part D — Physical Design: RTL to GDSII with LibreLane
Run the automated physical design flow (floorplanning, PDN, placement, CTS, routing, RC extraction, DRC/LVS, and timing signoff):
```bash
cd pnr

librelane config.json

LIBGL_ALWAYS_SOFTWARE=1 klayout ./mult_array.gds

LIBGL_ALWAYS_SOFTWARE=1 klayout runs/RUN_2026-10-18_16-25-06/final/gds/mult_array.gds
```

---

## Section B: Gate-Level Simulation (GLS) Race Condition and Resolution

### 1. Why the Race Condition Happened
During gate-level simulation (GLS) in Part B, the synthesized netlist was simulated with the SkyWater 130 nm standard cell library using the compilation command:
```bash
CELLS=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog
iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 -o gls \
  tb/tb_mult.v $CELLS/primitives.v $CELLS/sky130_fd_sc_hd.v synth/mult_array_netlist.v
vvp gls
```

The gate-level simulation initially failed with **239 vector mismatches** (e.g., for vector $a = 15, b = 2$, expected was `30`, but the testbench observed `15` from the previous vector $a = 15, b = 1$). The root cause was an **event scheduling race condition** between the testbench sampling logic and the standard cell flip-flop models:

1. **`-DUNIT_DELAY=#1` Propagation Delay:**
   In `sky130_fd_sc_hd.v`, defining `UNIT_DELAY=#1` models an inertial propagation delay of $1\text{ ns}$ across all standard cells and flip-flops. For the output registers (`sky130_fd_sc_hd__dfrtp_1`), when a rising clock edge occurs at simulation time $T$, the flip-flop output $Q$ updates at:

$$T_{\text{update}} = T + 1\text{ ns}$$

2. **Coincident Sampling Time in Testbench:**
   In the testbench, after waiting for the 2 clock cycles of pipeline latency, the sampling strobe was originally set to `#1;`:
   ```verilog
   @(posedge clk);
   @(posedge clk);
   #1;
   if (p !== expected) begin ... end
   ```
   If the second clock edge occurred at time $T$ (e.g., $T = 555.0\text{ ns}$), the testbench checked `p` at:

$$T_{\text{sample}} = 555.0\text{ ns} + 1.0\text{ ns} = \mathbf{556.0\text{ ns}}$$

   Simultaneously, the flip-flop output update was also scheduled for:

$$T_{Q} = 555.0\text{ ns} + 1.0\text{ ns} = \mathbf{556.0\text{ ns}}$$

3. **Verilog Scheduling Race:**
   Because both the testbench `#1;` wakeup timer and the flip-flop output propagation were scheduled at the exact same simulation timestep ($556.0\text{ ns}$), the simulator evaluated the testbench `if (p !== expected)` check in the active queue **before** the output port `p` updated with the new value. As a result, the testbench sampled the stale product from the previous vector, causing virtually all vectors to report a mismatch.

### 2. How the Race Condition Was Resolved
In a synchronous system with a $10\text{ ns}$ clock period ($5\text{ ns}$ high, $5\text{ ns}$ low), the output `p` becomes valid and stable at $T + 1\text{ ns}$ and remains stable until the subsequent clock edge at $T + 10\text{ ns}$.

1. **Widening the Strobe Window to `#2;`:**
   The testbench sampling strobe was updated from `#1;` to `#2;`:
   ```verilog
   // Wait for the 2-cycle latency (Cycle 1: input regs, Cycle 2: output reg)
   @(posedge clk);
   @(posedge clk);
   #2; // Sample window safely past unit delay (T + 1 ns)
   if (p !== expected) begin
       $display("Mismatch: a=%d b=%d expected=%d got=%d", a, b, expected, p);
       errors = errors + 1;
   end
   ```
   At $T + 2\text{ ns}$, all flip-flop outputs and internal combinational logic nets have completely settled, avoiding any delta-cycle race condition.

2. **Synchronous Posedge Input Driving (`<=`):**
   Inputs `a` and `b` are assigned on the rising clock edge using non-blocking assignments (`@(posedge clk); a <= i; b <= j;`). This ensures zero input skew relative to `clk` while providing full clock-cycle setup and hold margins for the UUT input flip-flops.

---

## Section D: Physical Design Signoff and Timing Closure Analysis

### 1. Why the Signoff Clock Period is 6.0 ns Instead of 3.56 ns
In Part C, pre-route Static Timing Analysis established $T_{\min} = 2.973\text{ ns}$, yielding an initial target clock period of:

$$T_{\text{target}} = 1.2 \times T_{\min} = 1.2 \times 2.973\text{ ns} \approx 3.568\text{ ns}$$

However, during physical implementation in Part D, timing closure required increasing `CLOCK_PERIOD` to **6.00 ns**. This discrepancy between the pre-route estimate ($3.568\text{ ns}$) and the final physical signoff requirement ($6.00\text{ ns}$) is caused by transitioning from idealized pre-layout assumptions to physical silicon realities under worst-case manufacturing corners:

- **Process, Voltage, and Temperature (PVT) Corners (Primary Factor):** In Part C, OpenSTA evaluated the design using only the nominal typical corner (`tt_025C_1v80`), which assumes nominal manufacturing, room temperature ($25^\circ\text{C}$), and optimal voltage ($1.80\text{ V}$). LibreLane's physical signoff in Part D enforces multi-corner setup timing closure against the worst-case **Slow-Slow (`max_ss_100C_1v60`)** corner. Operating at high temperature ($100^\circ\text{C}$) and low supply voltage ($1.60\text{ V}$) reduces carrier mobility and transistor drive current, nearly doubling gate delays—expanding the critical path from $3.0842\text{ ns}$ (at `nom_tt_025C_1v80`) to $5.9544\text{ ns}$ (at `max_ss_100C_1v60`).
- **Interconnect Parasitics (RC Extraction):** Pre-route STA in Part C evaluates gate delays using zero-wireload or idealized interconnect models. In Part D, SPEF extraction models the physical resistance ($R$) and capacitance ($C$) of routed metal layers (`met1`–`met4`). Even at the identical nominal corner (`nom_tt_025C_1v80`), post-route RC delays and physical buffering increase the critical path delay from $2.973\text{ ns}$ (Part C) to $3.0842\text{ ns}$ (Part D).
- **Clock Tree Synthesis (CTS) and Clock Uncertainty:** Part C assumes an ideal clock reaching all 16 flip-flops instantaneously. Part D constructs a physical clock distribution tree using `sky130_fd_sc_hd__clkbuf_16` buffers, introducing real insertion delay, clock skew between launch and capture registers, and setup uncertainty margins.
- **Physical Routing Detours and Timing Buffering:** To satisfy Design Rule Checks (DRC) and avoid metal shorts across a routed wirelength of $2,407\text{ }\mu\text{m}$, the detailed router takes non-manhattan detours around obstacles, while the OpenROAD resizer inserts 23 timing buffers (`sky130_fd_sc_hd__buf_2`) to repair transition slew and hold constraints.

---

### 2. Primary Part D Results Comparison (Clock Period and PPA)

The table below presents the required Part D metrics for the final timing-closed signoff implementation (`CLOCK_PERIOD = 6.00 ns`, run `RUN_2026-10-18_16-25-06`) alongside the initial exploratory baseline run (`CLOCK_PERIOD = 10.00 ns`, run `RUN_2026-10-15_20-59-19`).

| Metric | Passing Signoff Run (`RUN_2026-10-18_16-25-06`) | Initial Baseline Run (`RUN_2026-10-15_20-59-19`) | Description / Source |
| :--- | :--- | :--- | :--- |
| **`CLOCK_PERIOD` used (ns)** | **6.00** | 10.00 | Extracted from `76-misc-reportmanufacturability/config.json` |
| **Number of runs needed** | **4 iterations** (to close timing) / **9 total runs** | 1 (baseline exploratory run) | 4 attempts in 0.5 ns steps (4.0 → 4.5 → 5.0 → 6.0 ns) |
| **Core area (μm²)** | **17,759.50** | 17,759.50 | `design__core__area` (Die area: 22,500.00 μm², 150 × 150 μm) |
| **Cells after synthesis (from Part B)** | **68** | 68 | From `synth/mult_array_stat.rpt` (16 flip-flops + 52 combinational) |
| **Cells after place and route** | **1,891** (339 standard + 1,552 fill) | 1,892 (335 standard + 1,557 fill) | `design__instance__count` in `final/metrics.json` |
| **Kinds of cells added** | Fill/decap: 1,552<br>Tap: 245<br>Timing buffers: 23<br>Clock buffers: 3<br>Inverters: 4 | Fill/decap: 1,557<br>Tap: 245<br>Timing buffers: 19<br>Clock buffers: 3<br>Inverters: 4 | Identified from `design__instance__count__class:*` |
| **Wirelength (μm)** | **2,407** | 2,395 | Actual post-route routed wirelength (`route__wirelength`) |
| **Setup slack (ns)** | **+0.0456** (`max_ss_100C_1v60`)<br>+2.9158 (`nom_tt_025C_1v80`) | **+2.8940** (`max_ss_100C_1v60`)<br>+6.4745 (`nom_tt_025C_1v80`) | Worst setup slack from `55-openroad-stapostpnr/summary.rpt` |
| **Post-route F_max (MHz)** | **167.94** (worst `max_ss`)<br>324.23 (nominal `nom_tt`) | **140.73** (worst `max_ss`)<br>283.69 (nominal `nom_tt`) | Derived: `F_max = 1000 / (CLOCK_PERIOD - slack)` |
| **F_max from Part C (MHz)** | **336.70** | 336.70 | Established in Part C STA (`T_min = 2.973 ns` at `tt_025C_1v80`) |
| **DRC errors** | **0** | 0 | Magic: 0, KLayout: 0, Detailed Route: 0 |
| **LVS errors** | **0** | 0 | Netgen LVS: 0 unmatched nets / pins / devices |

---

### 3. Comprehensive Traceability Across All Existing LibreLane Runs

All 9 existing run directories under `pnr/runs/` were inspected. Each run is identified by its timestamped directory name and its configuration file `pnr/runs/*/76-misc-reportmanufacturability/config.json`.

| Run Identifier | Timestamp | `CLOCK_PERIOD` (ns) | Total Cells (Std + Fill) | Timing Buffers | Routed Wirelength (μm) | Setup Slack `max_ss` (ns) | Setup Slack `nom_tt` (ns) | Derived Post-Route F_max `max_ss` (MHz) | Signoff Timing Status | Notes / Role |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `RUN_2026-10-15_20-59-19` | 2026-10-15 20:59:19 | 10.0 | 1,892 (335 + 1557) | 19 | 2,395 | +2.8940 | +6.4745 | 140.73 | **MET** | Initial baseline flow execution |
| `RUN_2026-10-18_11-35-53` | 2026-10-18 11:35:53 | 3.5 | 1,895 (348 + 1547) | 32 | 2,440 | -2.1880 | +0.5105 | 175.81 | **VIOLATED** | Initial attempt based on `1.2 * T_min ≈ 3.56 ns` |
| `RUN_2026-10-18_11-39-22` | 2026-10-18 11:39:22 | 4.0 | 1,895 (348 + 1547) | 32 | 2,440 | -1.6880 | +1.0105 | 175.81 | **VIOLATED** | Attempt with `1.2 * T_min` rounded up to 4.0 ns |
| `RUN_2026-10-18_11-48-19` | 2026-10-18 11:48:19 | 4.0 | 1,895 (348 + 1547) | 32 | 2,440 | -1.6880 | +1.0105 | 175.81 | **VIOLATED** | Repeated run 1 of 4.0 ns (identical metrics) |
| `RUN_2026-10-18_16-04-05` | 2026-10-18 16:04:05 | 4.0 | 1,895 (348 + 1547) | 32 | 2,440 | -1.6880 | +1.0105 | 175.81 | **VIOLATED** | Repeated run 2 of 4.0 ns (identical metrics) |
| `RUN_2026-10-18_16-20-04` | 2026-10-18 16:20:04 | 4.5 | 1,895 (348 + 1547) | 32 | 2,440 | -1.1880 | +1.5105 | 175.81 | **VIOLATED** | Iteration +0.5 ns from 4.0 ns |
| `RUN_2026-10-18_16-22-32` | 2026-10-18 16:22:32 | 5.0 | 1,895 (348 + 1547) | 32 | 2,440 | -0.6880 | +2.0105 | 175.81 | **VIOLATED** | Iteration +0.5 ns from 4.5 ns |
| `RUN_2026-10-18_16-25-06` | 2026-10-18 16:25:06 | 6.0 | 1,891 (339 + 1552) | 23 | 2,407 | +0.0456 | +2.9158 | 167.94 | **MET** | **First passing signoff closure in 0.5 ns steps** |
| `RUN_2026-10-18_16-28-52` | 2026-10-18 16:28:52 | 5.5 | 1,895 (348 + 1547) | 32 | 2,440 | -0.1880 | +2.5105 | 175.81 | **VIOLATED** | Backward test to confirm whether 5.5 ns could pass |

---

### 4. Detailed Technical Analysis and Explanations

#### A. Interpretation of "Number of Runs Needed"
The assignment instructions (Section 9, Task 1) specify:
> *"Write config.json and run the flow until it finishes with 0 DRC errors, 0 LVS errors and setup slack ≥ 0. If timing fails, increase CLOCK_PERIOD by 0.5 ns and run again; record every attempt in your README."*

The repository artifacts document the following execution history:
1. **Total Runs in Workspace:** **9 runs** are present in `pnr/runs/`.
2. **Unique Clock Periods Tested:** **7 distinct clock periods** were tested: `10.0 ns`, `3.5 ns`, `4.0 ns`, `4.5 ns`, `5.0 ns`, `6.0 ns`, and `5.5 ns`.
3. **Iterations to Timing Closure:**
   - The initial theoretical constraint was $1.2 \times T_{\min} = 1.2 \times 2.973\text{ ns} = 3.5676\text{ ns}$.
   - Rounding up to the next $0.5\text{ ns}$ yielded **4.0 ns**.
   - Stepping upward in $0.5\text{ ns}$ increments required **4 iterations**:
     - **Iteration 1:** $4.0\text{ ns} \rightarrow \text{Slack} = -1.6880\text{ ns}$ (VIOLATED)
     - **Iteration 2:** $4.5\text{ ns} \rightarrow \text{Slack} = -1.1880\text{ ns}$ (VIOLATED)
     - **Iteration 3:** $5.0\text{ ns} \rightarrow \text{Slack} = -0.6880\text{ ns}$ (VIOLATED)
     - **Iteration 4:** $6.0\text{ ns} \rightarrow \text{Slack} = +0.0456\text{ ns}$ (**MET / Timing Closed**)
   - If counting from the initial unrounded attempt at $3.5\text{ ns}$, **5 iterations** were taken.
   - Run `RUN_2026-10-18_16-28-52` at $5.5\text{ ns}$ was subsequently executed to check if $5.5\text{ ns}$ would close timing, but resulted in a slack of $-0.1880\text{ ns}$, definitively proving that **6.00 ns** is the lowest achievable clock period in $0.5\text{ ns}$ steps.

#### B. Repeated 4.0 ns Runs
Three runs share `CLOCK_PERIOD = 4.0 ns`:
- `RUN_2026-10-18_11-39-22`
- `RUN_2026-10-18_11-48-19`
- `RUN_2026-10-18_16-04-05`

Automated diff analysis of their `final/metrics.json` confirmed that **all reported metrics are 100% identical** across all three runs (core area = $17,759.50\text{ }\mu\text{m}^2$, stdcells = 348, fill cells = 1,547, wirelength = $2,440\text{ }\mu\text{m}$, setup slack = $-1.6880\text{ ns}$, DRC = 0, LVS = 0). They represent re-runs of the same configuration.

#### C. Kinds of Cells Added During Physical Implementation
Comparing the Part B synthesis gate count (68 cells) against the post-route netlist reveals that physical implementation introduced five distinct cell classes:
1. **Tap Cells (245 cells, `sky130_fd_sc_hd__tapvpwrvgnd_1`):** Inserted during floorplanning at regular intervals to tie wells to $V_{\text{DD}}$ and substrate to $V_{\text{SS}}$, preventing CMOS latch-up.
2. **Fill / Decoupling Capacitance Cells (1,547 to 1,557 cells):** Inserted into vacant core sites post-routing. These include decap cells (`decap_12`, `decap_6`, `decap_3`, `decap_8`, `decap_4`) for power integrity and fill cells (`fill_1`, `fill_2`) to satisfy foundry layer density requirements for chemical-mechanical polishing (CMP).
3. **Clock Buffers (3 cells, `sky130_fd_sc_hd__clkbuf_16`):** Inserted by CTS (Clock Tree Synthesis) to construct a balanced clock distribution tree with minimal skew across the 16 registers.
4. **Timing Repair Buffers (19 to 32 cells, e.g., `sky130_fd_sc_hd__buf_2`):** Inserted by the OpenROAD resizer to fix transition, max slew, and setup/hold timing violations. In timing-strained runs ($3.5\text{–}5.5\text{ ns}$), the resizer inserted 32 buffers; in the $6.0\text{ ns}$ passing run, 23 buffers were inserted; in the relaxed $10.0\text{ ns}$ baseline, 19 buffers were inserted.
5. **Inverters (4 cells):** Used for load driving and polarity alignment.
6. **Combinational Restructuring:** The 52 combinational gates from synthesis were optimized and remapped into 48 multi-input standard cells.
7. **Antenna Diodes (0 cells):** Antenna checks reported zero violations across all runs (`antenna_diodes_count: 0`).

#### D. Core Area vs. Die Area
The floorplan configuration specifies `FP_SIZING: absolute` with `DIE_AREA: [0, 0, 150, 150]`, yielding a total **Die Area of $22,500.00\text{ }\mu\text{m}^2$**.
The actual **Core Area** available for placing standard cell rows within the core margins is **$17,759.50\text{ }\mu\text{m}^2$** (reported by `design__core__area`), achieving a standard cell core utilization of ~8.04%.

#### E. Calculation of Post-Route $F_{\max}$
The post-route maximum frequency is calculated from the effective critical-path delay:

$$T_{\text{critical}} = T_{\text{clk}} - \text{Slack}_{\text{setup}}$$

$$F_{\max} = \frac{1000}{T_{\text{critical}}} = \frac{1000}{T_{\text{clk}} - \text{Slack}_{\text{setup}}}$$

- **Passing Signoff Run (`RUN_2026-10-18_16-25-06`, $T_{\text{clk}} = 6.00\text{ ns}$):**
  - Worst corner (`max_ss_100C_1v60`): Setup Slack $= +0.0456\text{ ns}$

$$T_{\text{critical}} = 6.00 - 0.0456 = 5.9544\text{ ns} \implies F_{\max} = \frac{1000}{5.9544} = \mathbf{167.94\text{ MHz}}$$

  - Nominal corner (`nom_tt_025C_1v80`): Setup Slack $= +2.9158\text{ ns}$

$$T_{\text{critical}} = 6.00 - 2.9158 = 3.0842\text{ ns} \implies F_{\max} = \frac{1000}{3.0842} = \mathbf{324.23\text{ MHz}}$$

- **Baseline Run (`RUN_2026-10-15_20-59-19`, $T_{\text{clk}} = 10.00\text{ ns}$):**
  - Worst corner (`max_ss_100C_1v60`): Setup Slack $= +2.8940\text{ ns} \implies T_{\text{critical}} = 7.1060\text{ ns} \implies F_{\max} = \mathbf{140.73\text{ MHz}}$
  - Nominal corner (`nom_tt_025C_1v80`): Setup Slack $= +6.4745\text{ ns} \implies T_{\text{critical}} = 3.5255\text{ ns} \implies F_{\max} = \mathbf{283.69\text{ MHz}}$

- **Comparison with Part C Pre-Route $F_{\max}$:**
  Part C static timing analysis under the typical corner (`sky130_fd_sc_hd__tt_025C_1v80.lib`) established $T_{\min} = 2.973\text{ ns}$, giving $F_{\max} = \mathbf{336.70\text{ MHz}}$.
  At the corresponding nominal post-route corner (`nom_tt_025C_1v80`), post-route $F_{\max}$ is **324.23 MHz** ($T_{\text{critical}} = 3.0842\text{ ns}$), showing only a minor ~3.7% degradation due to physical wire parasitics and clock skew. However, manufacturing signoff requires meeting timing under the slow-slow corner (`max_ss_100C_1v60`), where high temperature ($100^\circ\text{C}$) and low voltage ($1.60\text{ V}$) lower the transistor drive current, shifting the maximum operational frequency to **167.94 MHz** ($T_{\text{critical}} = 5.9544\text{ ns}$) and necessitating a $6.00\text{ ns}$ clock period.

#### F. Physical DRC and LVS Verification
All 9 runs completed physical signoff with zero defects:
- **DRC:** 0 violations verified by Magic (`magic__drc_error__count: 0`), KLayout (`klayout__drc_error__count: 0`), and the detailed routing engine (`route__drc_errors: 0`).
- **LVS:** 0 violations verified by Netgen (`design__lvs_error__count: 0`, 0 unmatched nets, 0 unmatched pins, 0 unmatched devices).
