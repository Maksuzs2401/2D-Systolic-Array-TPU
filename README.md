# 2D SYSTOLIC ARRAY TPU
It is a 16x16 Systolic Array unit for General Matrix Multiplication (GEMM). It is written in SystemVerilog, the IP is packaged with an AXI4-S interface for plug-and-play integration with Xilinx processors and DMA engines. It is implemented on an Artix UltraScale+, using dedicated DSP48E2 blocks. 

## PERFORMANCE & IMPLEMENTATION STATS

### UTILIZATION REPORT

**Device:** Xilinx Artix UltraScale+ `xcau15p-ffvb676-2-e`  
**Tool:** Vivado v2024.1 | **Design:** `axi_wrapp` | **State:** Fully Placed

---

| Resource         | Used   | Available | Utilization |
|-----------------|--------|-----------|-------------|
| CLB LUTs        | 3,913  | 77,760    | 5.03%       |
| CLB Registers   | 22,758 | 155,520   | 14.63%      |
| **DSPs (DSP48E2)**  | **256**    | **576**      | **44.44%**  🟢  | 
| F7 Muxes        | 1,600  | 38,880    | 4.12%       |
| F8 Muxes        | 800    | 19,440    | 4.12%       |
| Block RAM Tiles | 0      | 144       | 0.00%       |
| Bonded IOBs     | 54     | 228       | 23.68%      |
| BUFGCE (Clocks) | 3      | 84        | 3.57%       |
| CLBs            | 2,648  | 9,720     | 27.24%      |

---

### Design Timing Summary

| Metric                        | Setup      | Hold       | Pulse Width |
|-------------------------------|------------|------------|-------------|
| Worst Negative Slack (WNS/WHS/WPWS) | `1.196 ns` | `0.016 ns` | `2.225 ns` |
| Total Negative Slack (TNS/THS/TPWS) | `0.000 ns` | `0.000 ns` | `0.000 ns` |
| Number of Failing Endpoints   | 0          | 0          | 0           |
| Total Number of Endpoints     | 64,770     | 64,770     | 23,219      |

---

## ARCHITECTURE (Module-by-Module Explanation)

<img width="1000" height="500" alt="micro_arch" src="https://github.com/user-attachments/assets/cc3695e8-bfcc-4c0b-9ea1-67a8461f2514" />

---

### 1. `config.vh` - Global Parameters
It is a central header file the defines all the constants, though only few were used in final design. 

### 2.  `mac_unit.sv` — Multiply-Accumulate Processing Element (PE)
It multiplies two 8-bit signed inputs `a_reg` and `b_reg` combinationally → 16-bit product. It then accumulates the product into a 32-bit register on every valid clock cycle. 
```
    prod_res = a_reg * b_reg;  
    accu_reg <= accu_reg + prod_res;  
    assign out = accu_reg;
```
The data `a` is passed horizontally** (left → right) and **data `b` is passed vertically** (top → bottom) to neighboring PEs  

---
### 3. `array_PE.sv` — N×N Systolic Processing Array
This module instantiates array PEs in a 2D grid using `generate` loop.  
**Data Flow**
 Row `i` of matrix A enters from the **left edge** of row `i`  
- Column `j` of matrix B enters from the **top edge** of column `j`  
- Each PE at position `[i][j]` computes the partial product `A[i][k] × B[k][j]` and accumulates it  
- After N cycles, `pe_out[i][j]` holds the complete dot product = **C[i][j]**
- `a_wire[i][j]` → passes horizontally: `a_pass` of PE[i][j] feeds `a_reg` of PE[i][j+1]
- `b_wire[i][j]` → passes vertically: `b_pass` of PE[i][j] feeds `b_reg` of PE[i+1][j]
- `v_wire[i][j]` → valid signal also propagates rightward with the data

---

### 4. `buffer_net.sv` — Input Buffer & Diagonal Skewing Network
This is responsible for sending the data to each PE correctly. It has two phase of operation:  
**1. Phase-one: Serial Load**
- Matrix A elements arrive serially on `a_in` one by one, stored into `a_reg[row][col]`
- Matrix B elements arrive serially on `b_in` one by one, stored into `b_reg[col][row]`  
- In this skewing network both A and B require N² = 256 clock cycles to load completely.

**2. Phase-two: Diagonal Skew & Feed**
- Once both matrices are loaded, it begins **staggered row feeding**
- Row 0 starts at cycle 0, Row 1 at cycle 1, ..., Row N-1 at cycle N-1
- This **diagonal skewing** ensures that elements that should be multiplied
  together (A[i][k] and B[k][j]) arrive at their target PE at the same clock cycle
- `valid_out[i]` is only asserted while row `i` is actively streaming
- The `load` output pulses high when the last row finishes, signaling the output stage

---
### 5. `output_stage.sv` — Result Capture & Accumulator Control
This module is responsible for managing end-of-computation handshake. 
- It waits for `start` (= `load` from `buffer_net`) to go high
- Counts exactly **N clock cycles** — the pipeline latency needed for all
  partial products to finish accumulating in the last PE column/row
- At cycle N, it:
  - **Snapshots** all `pe_out[N][N]` values into `result[N][N]` simultaneously
  - Asserts `res_valid` to signal the PISO stage
  - Pulses `accu_clear` back to `array_PE` to **reset all accumulators**. Hence, the array is ready for the next matrix multiplication

---
### 6. `array_piso.sv` — Parallel-In Serial-Out Serializer
It converts **NxN = 256 parallel result** into serial result for AXI stream. 
- When `in_valid` is asserted, latches the entire result matrix into `buff_reg`
- Iterates through `[row][col]` from `[0][0]` to `[N-1][N-1]`, row by row
- Outputs one 32-bit word per clock on `out_data` with `out_valid` high
- Asserts `out_last` on the very last element `[N-1][N-1]` (AXI-Stream TLAST)
- Total serialization time: **N² = 256 clock cycles**

---
### 7. `top_wrapper.sv` — Design Integration Layer
It manages all the individual modules and connects them in a correct order. 

---
### 8. `axi_wrapp.sv` — AXI4-Stream Interface Wrapper
It makes the IP compliant with any other system working on AXI4-S protocol. 
**Input (Slave AXI4-Stream):**
- `s_axis_tdata[7:0]` → activation element `a_in` (Matrix A)
- `s_axis_tdata[15:8]` → weight element `b_in` (Matrix B)
- `s_axis_tvalid` → used as `a_valid` and `b_valid` simultaneously
- `s_axis_tready` → always tied HIGH (backpressure not implemented; design always accepts data)

**Output (Master AXI4-Stream):**
- `m_axis_tdata` → 32-bit serialized result
- `m_axis_tvalid` → result is valid
- `m_axis_tlast` → last element of the result matrix

- `s_axis_tdata` register
  <img width="520" height="120" alt="Untitled Diagram drawio (1)" src="https://github.com/user-attachments/assets/618fe3d5-991a-4022-8c47-f36394c0bf67" />

---
## ARRAY DIAGRAM
<img width="1000" height="800" alt="Untitled Diagram drawio (2)" src="https://github.com/user-attachments/assets/c2bd0842-95da-463a-8048-3362b22dd9b7" />

## RESULTS
-FLOORPLANNING 
<img width="1000" height="769" alt="Screenshot 2026-04-29 014124" src="https://github.com/user-attachments/assets/1b1a6579-7470-4c54-bf69-97fb3148b29b" />
> I have drawn a Pblock in order to reduce timing violations and pack the design in efficient way.
