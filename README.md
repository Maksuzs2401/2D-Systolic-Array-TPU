# 2D SYSTOLIC ARRAY TPU
It is a 16x16 Systolic Array unit for General Matrix Multiplication (GEMM). It is written in SystemVerilog, the IP is packaged with an AXI4-S interface for plug-and-play integration with Xilinx processors and DMA engines. It is implemented on an Artix UltraScale+, using dedicated DSP48E2 blocks. 

## PERFORMANCE & IMPLEMENTATION STATS

### UTILIZATION REPORT

**Device:** Xilinx Artix UltraScale+ `xcau15p-ffvb676-2-e`  
**Tool:** Vivado v2024.1 | **Design:** `axi_wrapp` | **State:** Fully Placed

---

| Resource         | Used   | Available | Utilization |
|-----------------|--------|-----------|-------------|
| CLB LUTs        | 5,865  | 77,760    | 7.54%       |
| CLB Registers   | 23,244 | 155,520   | 14.95%      |
| **DSPs (DSP48E2)**  | **256**    | **576**      | **44.44%**  🟢  | 
| F7 Muxes        | 2560  | 38,880    | 6.58%       |
| F8 Muxes        | 256    | 19,440    | 1.32%       |
| BUFGCE (Clocks) | 2      | 84        | 2.38%       |
| CLBs            | 2,999  | 9,720     | 30.85%      |

---

### Design Timing Summary

| Metric                        | Setup      | Hold       | Pulse Width |
|-------------------------------|------------|------------|-------------|
| Worst Negative Slack (WNS/WHS/WPWS) | `1.194 ns` | `0.043 ns` | `2.225 ns` |
| Total Negative Slack (TNS/THS/TPWS) | `0.000 ns` | `0.000 ns` | `0.000 ns` |
| Number of Failing Endpoints   | 0          | 0          | 0           |
| Total Number of Endpoints     | 65743     | 65743     | 23,704      |

---

## ARCHITECTURE (Module-by-Module Explanation)

<img width="1000" height="500" alt="micro_arch" src="https://github.com/user-attachments/assets/cc3695e8-bfcc-4c0b-9ea1-67a8461f2514" />

---
### Result Propagation Time
**Data Load (AXI to Buffer):** 16 cycles  
**Systolic Array Propagation:** 71 cycles  
**Data Store (PISO to AXI):** 16 cycles  
**Total End-to-End Latency:** 103 cycles 

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
**1. Phase-one: Row-Parallel Load (Vector Loading)**
- Matrix A elements arrive as an entire row simultaneously ($N$ elements) via the wide AXI bus and are stored into `a_reg[row]`
- Matrix B elements arrive as an entire row simultaneously alongside A, and are stored into `b_reg[col]`.
- Because data is ingested row-by-row rather than serially, the buffer requires only N = 16 clock cycles to load both matrices completely.

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
- Counts exactly **N+1 clock cycles** — the pipeline latency needed for all
  partial products to finish accumulating in the last PE column/row
- At cycle N+1, it:
  - **Snapshots** all `pe_out[N][N]` values into `result[N][N]` simultaneously
  - Asserts `res_valid` to signal the PISO stage
  - Pulses `accu_clear` back to `array_PE` to **reset all accumulators**. Hence, the array is ready for the next matrix multiplication

---
### 6. `array_piso.sv` — Parallel-In Serial-Out Serializer
It converts **NxN = 256 parallel result** into serial result for AXI stream. 
- When in_valid is asserted by the output stage, the PISO instantly latches the entire N*N matrix of 32-bit partial products into
a safe holding register (buff_reg).
- it shifts an entire row of results (N elements = 512 bits) onto the out_data bus per clock cycle, achieving high I/O bandwidth.
- The PISO actively monitors the out_ready signal (directly tied to `m_axis_tready`). If the downstream DMA or
computer RAM becomes busy (out_ready == 0), the PISO safely freezes its row counter and holds `out_valid` high,
indefinitely protecting the trapped data until the channel clears.
- It asserts `out_last` (mapped to AXI tlast) concurrently with the final row (Row N-1) to signal the exact end
of the matrix packet to the DMA.
- Because of the wide bus layout, the total serialization time is N = 16 **clock cycle**.
---
### 7. `top_wrapper.sv` — Design Integration Layer
It manages all the individual modules and connects them in a correct order. 

---
### 8. `axi_wrapp.sv` — AXI4-Stream Interface Wrapper
It makes the IP compliant with any other system working on AXI4-S protocol. 
**Input (Slave AXI4-Stream):**
- `s_axis_tdata[256:0]` → wide-bus input
  Bits [127:0]: Unpacked into an entire 16-element row of Matrix A (`a_in_array`).
  Bits [255:128]: Unpacked into an entire 16-element row of Matrix B (`b_in_array`).
- `s_axis_tvalid` → used as `a_valid` and `b_valid` simultaneously
- `s_axis_tready` → Driven directly by the buffer_net state. It drops to `0` when the internal buffers are full,
stalling the upstream DMA to prevent data overflow.
**Output (Master AXI4-Stream):**
- `m_axis_tdata[511:0]` → Wide-bus output payload. The wrapper packs sixteen 32-bit `result_out` partial products
into a single continuous 512-bit word per clock cycle.
- `m_axis_tvalid` → Driven by the PISO, asserts when a 512-bit row of results is ready to be read.
- `m_axis_tlast` →  Driven by the PISO, asserts synchronously with the final row (Row N-1) to signal the end of the matrix packet.
- `m_axis_tready` → Output Stall Logic. Accepted from the downstream system (RAM/DMA). If `0`, it safely propagates backward into the
array_piso to freeze the output sequence until the downstream system clears.

- `s_axis_tdata` register
  <p  align="center">
  <img width="520" height="120" alt="Untitled Diagram drawio (1)" src="https://github.com/user-attachments/assets/618fe3d5-991a-4022-8c47-f36394c0bf67" />
  </p>
---
## ARRAY DIAGRAM
<img width="1000" height="800" alt="Untitled Diagram drawio (2)" src="https://github.com/user-attachments/assets/c2bd0842-95da-463a-8048-3362b22dd9b7" />

## RESULTS
- FLOORPLANNING 
<img width="400" height="500" alt="floor_plan" src="https://github.com/user-attachments/assets/f77a693c-159f-45bb-b476-eef54b0a230d" />

> I have drawn a Pblock in order to reduce timing violations and pack the design in efficient way.
