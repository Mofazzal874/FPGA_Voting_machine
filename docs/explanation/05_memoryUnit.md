# Module 5: memoryUnit — BRAM-Based Vote Counter Storage

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/memoryUnit.v`

---

## Purpose

The Memory Unit provides **persistent on-chip storage** for vote counts using the FPGA's Block RAM (BRAM) resources. It matches the **Chapter 3** specification of the project report. Instead of relying solely on the `voteLogger`'s flip-flop registers (which are fast but limited), the Memory Unit stores vote data in dedicated BRAM blocks — the same physical memory cells used for large data storage on Xilinx Artix-7 FPGAs.

Currently, it shadow-stores vote counts from the `voteLogger`. When the Control Unit FSM is implemented, the Memory Unit will become the **primary vote storage**, and the ALU will perform read-modify-write cycles through it.

---

## Full Source Code

```verilog
`timescale 1ns / 1ps

// Memory Unit — BRAM-based vote counter storage
// Matches report Chapter 3 specification
// 64 x 32-bit words (inferred as Block RAM by Vivado)
// Addresses 0-3: candidate vote counters
// Addresses 4-63: reserved for voter ID hashes (future)
module memoryUnit(
    input clk,
    input reset,
    input [5:0] addr,       // 6-bit address (0-63)
    input wr_en,            // Write enable
    input [31:0] data_in,   // Write data
    output reg [31:0] data_out  // Read data (synchronous)
);

// Infer Block RAM — 64 x 32-bit
(* ram_style = "block" *) reg [31:0] mem [0:63];

// Initialize all memory to zero (loaded into FPGA bitstream)
integer i;
initial begin
    for (i = 0; i < 64; i = i + 1)
        mem[i] = 32'd0;
end

// Synchronous read/write (single-port BRAM pattern)
always @(posedge clk) begin
    if (wr_en)
        mem[addr] <= data_in;
    data_out <= mem[addr];
end

endmodule
```

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | Input | 1 bit | 100 MHz system clock |
| `reset` | Input | 1 bit | Active-high synchronous reset (**Not used** — BRAM is initialized via `initial` block instead) |
| `addr` | Input | 6 bits | Memory address selecting one of 64 locations (0–63) |
| `wr_en` | Input | 1 bit | Write enable — when HIGH, data is written to `mem[addr]` on the clock edge |
| `data_in` | Input | 32 bits | Data to write into memory at the addressed location |
| `data_out` | Output | 32 bits | Data read from the addressed location (one clock cycle latency) |

---

## Memory Map

The 64 addressable locations are organized as follows:

| Address Range | Size | Purpose | Status |
|---|---|---|---|
| `0x00` (0) | 32 bits | **Candidate 1 vote count** | ✅ Used |
| `0x01` (1) | 32 bits | **Candidate 2 vote count** | ✅ Used |
| `0x02` (2) | 32 bits | **Candidate 3 vote count** | ✅ Used |
| `0x03` (3) | 32 bits | **Candidate 4 vote count** | ✅ Used |
| `0x04`–`0x3F` (4–63) | 60 × 32 bits | Reserved for voter ID hashes | 🔜 Future |

This matches the report's memory segment allocation (Table 3.1), with the vote counters occupying the first 4 addresses and the remaining space reserved for the voter hash registry.

---

## How It Works — Step by Step

### Part 1: BRAM Inference Attribute

```verilog
(* ram_style = "block" *) reg [31:0] mem [0:63];
```

This line declares a **64-element array** of 32-bit registers. The Verilog synthesis attribute `(* ram_style = "block" *)` is a directive to Vivado's synthesizer:

- **Without the attribute**: Vivado might infer this as distributed RAM (using LUT resources) or Block RAM, depending on size and usage patterns.
- **With `ram_style = "block"`**: Vivado is **forced** to use dedicated Block RAM (BRAM) primitives on the Artix-7 FPGA.

**Why BRAM matters:**
- The Artix-7 XC7A35T on the Basys 3 has **50 Block RAM tiles** (each 36 Kbit).
- Our memory uses 64 × 32 = 2,048 bits = 2 Kbit — fits easily in a single BRAM tile.
- Using BRAM frees up LUT resources for logic (like the ALU, FSM, etc.).
- BRAM is synchronous and has guaranteed timing characteristics.

### Part 2: Initialization

```verilog
integer i;
initial begin
    for (i = 0; i < 64; i = i + 1)
        mem[i] = 32'd0;
end
```

**What this does**: Sets all 64 memory locations to zero when the FPGA is programmed.

**How it works on an FPGA**: Unlike software, `initial` blocks in synthesizable Verilog are NOT executed at runtime. Instead, Vivado reads these values and **embeds them into the bitstream** — the binary file loaded into the FPGA. When the board powers up and the bitstream is loaded, the BRAM is pre-configured with all zeros.

**Why not use `reset`?**: Resetting BRAM contents at runtime requires writing zeros to every address sequentially (64 clock cycles with a counter). The `initial` block handles power-on initialization, while runtime reset would need the Control Unit FSM to orchestrate. Currently, the top module's memory write controller continuously overwrites addresses 0–3 with voteLogger values, so after a reset, voteLogger's zeroed counts propagate to BRAM within 4 clock cycles.

### Part 3: Synchronous Read/Write

```verilog
always @(posedge clk) begin
    if (wr_en)
        mem[addr] <= data_in;
    data_out <= mem[addr];
end
```

This is the **core BRAM access logic**, using the standard single-port BRAM pattern that Vivado recognizes for BRAM inference.

**On every rising edge of the clock:**

1. **Write path** (`if (wr_en)`):
   - If `wr_en` is HIGH, the value on `data_in` is written to `mem[addr]`
   - The non-blocking assignment (`<=`) means the write takes effect at the end of the current simulation delta cycle

2. **Read path** (`data_out <= mem[addr]`):
   - The value at `mem[addr]` is read and stored in `data_out`
   - This happens **every clock cycle**, regardless of `wr_en`
   - There is a **one clock cycle latency** — the data appears on `data_out` one clock cycle after the address is presented

**Read-during-write behavior**: When a write and read happen at the same address on the same clock edge, the output shows the **old value** (read-before-write). This is because the Verilog non-blocking assignment schedules the write after the read. This is the default behavior for Xilinx BRAM and is called "Read First" mode.

---

## Timing Diagram — Write Operation

```
Clock    : _|‾|_|‾|_|‾|_|‾|_|‾|_
addr     :   0  |  1  |  2  |  3  |  0
wr_en    : ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾  (always HIGH)
data_in  :   5  |  3  |  1  |  7  |  X
mem[0]   : --0--| --5--|  5  |  5  |  5
mem[1]   :   0  | --0--| --3--|  3  |  3
mem[2]   :   0  |  0   | --0--| --1--|  1
mem[3]   :   0  |  0   |  0  | --0--| --7--
data_out :   0  |  0   |  5  |  3  |  1
                                ↑
                         1 cycle read latency
```

Note: `data_out` always shows the value from the **previous** clock cycle's address, due to BRAM's synchronous read latency.

---

## Timing Diagram — Read Operation

```
Clock    : _|‾|_|‾|_|‾|_|‾|_
wr_en    : ___________________  (LOW — read only)
addr     :   0  |  1  |  2  |  3
data_out :  old | mem[0] | mem[1] | mem[2]
                  ↑
           data appears 1 cycle after address
```

To read address 2, present `addr = 2` on one clock edge; `data_out` shows `mem[2]` on the **next** clock edge.

---

## How the Top Module Writes to Memory

The top module (`votingMachine.v`) contains a simple **rotating write controller** that continuously stores vote counts into BRAM:

```verilog
// In votingMachine.v:
reg [1:0] mem_write_sel;

always @(posedge clock) begin
    if (reset)
        mem_write_sel <= 2'd0;
    else
        mem_write_sel <= mem_write_sel + 1;
end

always @(*) begin
    mem_addr = {4'b0000, mem_write_sel};
    mem_wr = 1'b1;
    case (mem_write_sel)
        2'd0: mem_din = {24'd0, cand1_votes};
        2'd1: mem_din = {24'd0, cand2_votes};
        2'd2: mem_din = {24'd0, cand3_votes};
        2'd3: mem_din = {24'd0, cand4_votes};
    endcase
end
```

**How this works:**

1. A 2-bit counter `mem_write_sel` cycles through values `0 → 1 → 2 → 3 → 0 → 1 → ...` every clock cycle.

2. On each cycle, the counter selects:
   - **Which address** to write to: `mem_addr = {4'b0000, mem_write_sel}` = address 0, 1, 2, or 3
   - **Which vote count** to write: the 8-bit vote count is zero-extended to 32 bits (`{24'd0, candX_votes}`)

3. `mem_wr` is always HIGH — every cycle performs a write.

4. The result: **all 4 candidate vote counts are mirrored to BRAM every 4 clock cycles** (40 ns at 100 MHz). This is effectively instantaneous — the BRAM always contains an up-to-date snapshot of all vote counts.

```
Cycle 0: Write cand1_votes → mem[0]
Cycle 1: Write cand2_votes → mem[1]
Cycle 2: Write cand3_votes → mem[2]
Cycle 3: Write cand4_votes → mem[3]
Cycle 4: Write cand1_votes → mem[0]  ← repeats
...
```

---

## Behaviour on the FPGA Board

The Memory Unit has **no direct visible effect** on the board — it is an internal storage module. Its effects are observed through the data it provides to other modules:

1. **After programming the FPGA**: All 64 memory locations contain `0` (from the `initial` block in the bitstream).

2. **During voting**: As votes are counted by `voteLogger`, the top module's write controller continuously mirrors those counts into BRAM addresses 0–3. The BRAM is always in sync with the current vote tallies.

3. **After reset** (BTNC): `voteLogger` zeroes its counters, and within 4 clock cycles (40 ns), those zeros are written to BRAM addresses 0–3.

4. **Memory read**: The ALU's `operand` input is wired to `mem_dout`. When the FSM (future) presents an address and reads data, the ALU can process it. Currently, the continuous write cycle means `data_out` shows whatever address `mem_write_sel` is pointing to at that instant.

5. **Data persistence**: BRAM is **volatile** — if the board loses power, all data is lost. The report's Chapter 3 describes checkpointing to SPI Flash for non-volatile persistence, which is a future enhancement.

---

## Connection to Other Modules

```
  votingMachine.v                          memoryUnit
  Memory Write Controller                ┌───────────────────────┐
  ┌───────────────────────┐              │                       │
  │ mem_write_sel (2-bit) │              │   addr [5:0] ────────┤◄── {0000, mem_write_sel}
  │   cycles 0→1→2→3→0   │              │                       │
  │                       │              │   wr_en ─────────────┤◄── 1 (always writing)
  │ voteLogger outputs:   │              │                       │
  │ cand1_votes [7:0] ──┐ │              │   data_in [31:0] ────┤◄── {24'd0, candX_votes}
  │ cand2_votes [7:0] ──┤ ├─[32 bits]──►│                       │
  │ cand3_votes [7:0] ──┤ │              │   ┌─────────────────┐ │
  │ cand4_votes [7:0] ──┘ │              │   │  BRAM 64×32     │ │
  └───────────────────────┘              │   │  ┌───┬───────┐  │ │
                                         │   │  │ 0 │ cand1 │  │ │
                                         │   │  │ 1 │ cand2 │  │ │
                                         │   │  │ 2 │ cand3 │  │ │
                                         │   │  │ 3 │ cand4 │  │ │
                                         │   │  │4-63│ (rsvd)│  │ │
                                         │   │  └───┴───────┘  │ │
                                         │   └────────┬────────┘ │
                                         │            │          │
                                         │   data_out [31:0] ───┤──► ALU operand input
                                         │                       │
                                         └───────────────────────┘
```

---

## FPGA Resource Usage

| Resource | Usage |
|---|---|
| BRAM tiles | 1 of 50 available (2%) |
| Storage capacity | 64 × 32 = 2,048 bits used out of 36 Kbit per tile |
| LUTs | 0 (all storage in BRAM, no distributed RAM) |
| Clock-to-output delay | 1 clock cycle (10 ns at 100 MHz) |

The Memory Unit is extremely lightweight. Even with the reserved space for voter ID hashes (addresses 4–63), it uses less than 6% of a single BRAM tile's capacity.

---

## Report Comparison (Chapter 3)

| Report Spec | Our Implementation | Notes |
|---|---|---|
| Vote Counters in BRAM | ✅ Addresses 0–3 as 32-bit | Matches exactly |
| Voter ID Hash Table | 🔜 Addresses 4–63 reserved | Storage ready, hash logic is future work |
| SPI Flash persistence | ❌ Not implemented | Requires SPI controller — future enhancement |
| CRC-32 integrity check | ❌ Not implemented | Will be added with FSM |
| Write-enable arbitration | ✅ Simple rotating controller | FSM will replace with proper arbitration |
