# Module 7: fetchExecuteUnit — Fetch-Execute Cycle Engine

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/fetchExecuteUnit.v`

---

## Purpose

The Fetch-Execute Unit (FEU) implements the **manual fetch-execute cycle** — the fundamental hardware mechanism that connects the Control Unit to Memory and the ALU. Every memory operation (reading a vote count, writing back an incremented count, scanning the NID table) passes through the FEU's multi-cycle pipeline.

The FEU contains three classic CPU registers — **PC (Program Counter)**, **MAR (Memory Address Register)**, and **MBR (Memory Buffer Register)** — and orchestrates them through a state machine that mirrors a simplified Von Neumann fetch-execute cycle.

---

## Port Description

### Control Unit Interface

| Port | Direction | Width | Description |
|---|---|---|---|
| `fe_start` | Input | 1 bit | Pulse to begin an operation |
| `fe_op` | Input | 3 bits | Operation code (see table) |
| `fe_addr` | Input | 9 bits | Target memory address (loaded into PC) |
| `fe_write_data` | Input | 32 bits | Data for WRITE / OR_ACC operand |
| `fe_scan_target` | Input | 16 bits | NID value to search for (SCAN only) |
| `fe_scan_end` | Input | 9 bits | Last address to search (SCAN only) |
| `fe_done` | Output | 1 bit | HIGH for 1 cycle when operation completes |
| `fe_match` | Output | 1 bit | SCAN result: 1 = NID found |
| `fe_match_addr` | Output | 9 bits | Address where SCAN found the match |

### Memory Interface

| Port | Direction | Width | Description |
|---|---|---|---|
| `mem_addr` | Output | 9 bits | Address bus to memoryUnit |
| `mem_wr_en` | Output | 1 bit | Write enable to memoryUnit |
| `mem_data_out` | Output | 32 bits | Write data to memoryUnit |
| `mem_data_in` | Input | 32 bits | Read data from memoryUnit |

### ALU Interface

| Port | Direction | Width | Description |
|---|---|---|---|
| `alu_op` | Output | 3 bits | Operation code to ALU |
| `alu_operand` | Output | 32 bits | Operand to ALU |
| `alu_acc` | Input | 32 bits | Current accumulator value from ALU |

---

## Operation Codes

| Code | Name | Memory Access? | Description |
|---|---|---|---|
| `3'b000` | **NOP** | No | No operation |
| `3'b001` | **READ** | Yes (read) | Read `mem[addr]` → load into ALU accumulator |
| `3'b010` | **WRITE** | Yes (write) | Write `fe_write_data` → `mem[addr]` |
| `3'b011` | **WRITE_AC** | Yes (write) | Write ALU accumulator → `mem[addr]` |
| `3'b100` | **SCAN** | Yes (read loop) | Sequential search through NID table |
| `3'b101` | **INC** | No | Tell ALU to increment accumulator |
| `3'b110` | **OR_ACC** | No | Tell ALU to OR accumulator with `fe_write_data` |

---

## Internal Registers

| Register | Width | Purpose |
|---|---|---|
| `pc` | 9 bits | **Program Counter** — address pointer, loaded from `fe_addr`, incremented after each fetch |
| `mar` | 9 bits | **Memory Address Register** — holds address being accessed |
| `mbr` | 32 bits | **Memory Buffer Register** — holds data read from / to be written to memory |
| `op_latch` | 3 bits | Latched operation code (captured at start) |
| `scan_target_reg` | 16 bits | Latched NID search target |
| `scan_end_reg` | 9 bits | Latched end address for scan |

---

## FSM States

```
             fe_start
    IDLE ──────────────► FETCH1 ──► FETCH2 ──► EXECUTE ──► DONE ──► IDLE
     │                                                       ↑
     │   (SCAN op)                                          │
     └────────────────► SCAN_ADDR ──► SCAN_READ ──► SCAN_CMP ──┤
                            ↑                          │        │
                            └──── (no match, keep) ────┘        │
                                                    (match) ──► SCAN_MATCH ──► DONE
```

### Standard Fetch-Execute Cycle (READ, WRITE, WRITE_AC)

| State | Cycle | What Happens | Register Update |
|---|---|---|---|
| **S_FETCH1** | t0 | Present PC to memory address bus | `MAR ← PC` |
| **S_FETCH2** | t1 | Capture memory output, advance PC | `MBR ← M[MAR]`, `PC ← PC + 1` |
| **S_EXECUTE** | t2 | Perform operation (ALU load, memory write) | Depends on operation |
| **S_DONE** | t3 | Assert `fe_done` for 1 cycle | Return to IDLE |

### SCAN Cycle (NID Table Search)

| State | What Happens |
|---|---|
| **S_SCAN_ADDR** | Present PC to memory, `MAR ← PC` |
| **S_SCAN_READ** | `MBR ← M[MAR]`, `PC ← PC + 1` |
| **S_SCAN_CMP** | Compare `MBR[15:0]` vs `scan_target` using comparator |
| → match | `fe_match ← 1`, go to `S_SCAN_MATCH` (load entry into AC) |
| → empty entry (NID=0) | `fe_match ← 0`, go to `S_DONE` |
| → end of range | `fe_match ← 0`, go to `S_DONE` |
| → no match, keep going | Go back to `S_SCAN_ADDR` |
| **S_SCAN_MATCH** | ALU LOAD: `AC ← MBR` (so CU can check bit 16) |

### ALU-Only Operations (INC, OR_ACC)

These skip the fetch cycle entirely:
- **INC**: `IDLE → S_EXECUTE → S_DONE` (ALU increments accumulator)
- **OR_ACC**: `IDLE → S_EXECUTE → S_DONE` (ALU ORs operand into accumulator; MBR loaded with `fe_write_data`)

---

## Detailed Cycle-by-Cycle: How Data Moves Through BRAM

### The Key Constraint: BRAM Has 1-Cycle Read Latency

BRAM is **synchronous** — you present an address on one clock edge, and the data appears on `data_out` on the **next** clock edge. This is why the fetch cycle takes multiple states:

```
Clock edge N:     addr = 0x010  →  BRAM sees the address
Clock edge N+1:   data_out = mem[0x010]  →  BRAM delivers the data
```

The FEU's entire state machine is designed around this 1-cycle delay.

### The Combinational Address Trick

Look at this critical detail in the Verilog:

```verilog
// Combinational (always @(*)) — NOT clocked
always @(*) begin
    mem_addr = mar;           // Default: drive address from MAR

    case (state)
        S_FETCH1: mem_addr = pc;     // Override: drive from PC directly
        S_SCAN_ADDR: mem_addr = pc;  // Same for scan
        ...
    endcase
end
```

In `S_FETCH1`, the memory address is driven **combinationally from PC**, not from MAR. This means the BRAM sees the address **in the same cycle** that `S_FETCH1` starts, so by the next cycle (`S_FETCH2`), the data is ready. Without this trick, we'd need an extra wait cycle.

---

## READ Operation — Clock by Clock

**Goal**: Read `mem[0x000]` (Candidate 1 vote count) into the ALU accumulator.

Control Unit sets: `fe_op = READ`, `fe_addr = 0x000`, `fe_start = 1`

```
Cycle │ FEU State  │ PC    │ MAR   │ MBR       │ mem_addr │ BRAM data_out │ ALU
──────┼────────────┼───────┼───────┼───────────┼──────────┼───────────────┼──────────
  0   │ IDLE       │ ???   │ ???   │ ???       │ mar      │ ???           │ AC = old
      │            │       │       │           │          │               │
      │  fe_start! │ PC ← 0x000   │           │          │               │
      │  op_latch ← READ          │           │          │               │
      │            │       │       │           │          │               │
  1   │ S_FETCH1   │ 0x000 │ ???   │ ???       │ PC=0x000 │ (loading...)  │ AC = old
      │            │       │       │           │ ↑ combinational!         │
      │  Sequential: MAR ← PC = 0x000         │          │               │
      │            │       │       │           │          │               │
  2   │ S_FETCH2   │ 0x000 │ 0x000 │ ???       │ 0x000    │ mem[0x000]=5  │ AC = old
      │            │       │       │           │          │ ↑ data ready! │
      │  Sequential: MBR ← data_out = 5       │          │               │
      │             PC ← PC + 1 = 0x001       │          │               │
      │            │       │       │           │          │               │
  3   │ S_EXECUTE  │ 0x001 │ 0x000 │ 5         │ 0x000    │ 5             │ AC = old
      │            │       │       │           │          │               │
      │  Combinational: alu_op = LOAD, alu_operand = MBR = 5             │
      │  ALU latches: AC ← 5 (on next clock edge)       │               │
      │            │       │       │           │          │               │
  4   │ S_DONE     │ 0x001 │ 0x000 │ 5         │ 0x000    │ 5             │ AC = 5 ✓
      │            │       │       │           │          │               │
      │  fe_done = 1 (combinational)           │          │               │
      │  CU sees fe_done → leaves S_WAIT_FE    │          │               │
      │            │       │       │           │          │               │
  5   │ IDLE       │ 0x001 │ 0x000 │ 5         │ 0x000    │ 5             │ AC = 5
```

**Data journey**: `BRAM[0x000]` → wire `data_out` → register `MBR` → wire `alu_operand` → register `AC`

### Why PC, MAR, AND MBR? Why Not Just Read Directly?

- **PC** holds the target address and gets loaded from `fe_addr`. It auto-increments after each fetch, which is essential for SCAN (sequential table search).
- **MAR** latches the address so it stays stable on the memory bus while we wait for data.
- **MBR** captures the data from BRAM's `data_out`, because that wire changes every cycle — we need to hold the value stable for the ALU to process.

Without MBR, the data from BRAM would be gone by the time the ALU needs it (BRAM's output changes when `mem_addr` changes).

---

## WRITE Operation — Clock by Clock

**Goal**: Write value `0x00000000` to `mem[0x000]` (clear Candidate 1 count).

Control Unit sets: `fe_op = WRITE`, `fe_addr = 0x000`, `fe_write_data = 0x00000000`

```
Cycle │ FEU State  │ PC    │ MAR   │ MBR       │ mem_addr │ mem_wr_en │ mem_data_out
──────┼────────────┼───────┼───────┼───────────┼──────────┼───────────┼─────────────
  0   │ IDLE       │ ???   │ ???   │ ???       │ mar      │ 0         │ 0
      │            │       │       │           │          │           │
      │  fe_start! │ PC ← 0x000              │          │           │
      │  op_latch ← WRITE                    │          │           │
      │  MBR ← fe_write_data = 0x00000000    │ ← loaded in IDLE!   │
      │            │       │       │           │          │           │
  1   │ S_FETCH1   │ 0x000 │ ???   │ 0         │ PC=0x000 │ 0         │ 0
      │  MAR ← PC = 0x000                    │          │           │
      │            │       │       │           │          │           │
  2   │ S_FETCH2   │ 0x000 │ 0x000 │ 0         │ 0x000    │ 0         │ 0
      │  MBR stays (WRITE skips data capture) │          │           │
      │  PC ← PC + 1 = 0x001                 │          │           │
      │            │       │       │           │          │           │
  3   │ S_EXECUTE  │ 0x001 │ 0x000 │ 0         │ MAR=0x000│ 1 ← ON!  │ MBR = 0
      │            │       │       │           │          │           │
      │  Combinational: mem_wr_en = 1                    │           │
      │                  mem_addr  = MAR = 0x000         │           │
      │                  mem_data_out = MBR = 0          │           │
      │  BRAM writes: mem[0x000] ← 0x00000000           │           │ ✓ WRITTEN!
      │            │       │       │           │          │           │
  4   │ S_DONE     │ 0x001 │ 0x000 │ 0         │ 0x000    │ 0         │ 0
      │  fe_done = 1                           │          │           │
```

**Data journey**: `fe_write_data` → register `MBR` → wire `mem_data_out` → `BRAM[MAR]`

**Key detail for WRITE**: In `S_FETCH2`, the FEU does **NOT** overwrite MBR with `data_out`:

```verilog
S_FETCH2: begin
    if (op_latch != FE_OP_WRITE) begin
        mbr <= mem_data_in;      // READ/WRITE_AC: capture memory data
    end
    // WRITE: MBR already has fe_write_data, don't overwrite it!
end
```

---

## WRITE_AC Operation — Clock by Clock

**Goal**: Write the current ALU accumulator value back to `mem[0x000]`.

This is used after INC — the accumulator holds the incremented vote count, and we need to store it back.

```
Cycle │ FEU State  │ MAR   │ mem_addr │ mem_wr_en │ mem_data_out │ ALU AC
──────┼────────────┼───────┼──────────┼───────────┼──────────────┼────────
  0   │ IDLE       │       │          │ 0         │              │ 6
      │  PC ← 0x000, op_latch ← WRITE_AC        │              │
      │            │       │          │           │              │
  1   │ S_FETCH1   │       │ PC=0x000 │ 0         │              │ 6
      │  MAR ← 0x000      │          │           │              │
      │            │       │          │           │              │
  2   │ S_FETCH2   │ 0x000 │ 0x000    │ 0         │              │ 6
      │  MBR ← mem_data_in (old value, but we don't use it)     │
      │  PC ← 0x001       │          │           │              │
      │            │       │          │           │              │
  3   │ S_EXECUTE  │ 0x000 │ MAR=0x000│ 1 ← ON!  │ alu_acc = 6  │ 6
      │            │       │          │           │ ↑ directly!  │
      │  mem_data_out = alu_acc (NOT MBR!)       │              │
      │  BRAM writes: mem[0x000] ← 6            │              │ ✓
      │            │       │          │           │              │
  4   │ S_DONE     │ 0x000 │ 0x000    │ 0         │              │ 6
```

**Data journey**: ALU `acc` register → wire `alu_acc` → wire `mem_data_out` → `BRAM[MAR]`

**Key difference from WRITE**: WRITE puts MBR on the data bus (`mem_data_out = mbr`), but WRITE_AC puts the **accumulator** directly (`mem_data_out = alu_acc`). The MBR is bypassed entirely.

---

## SCAN Operation — Multi-Entry Search Example

**Goal**: Search NID table for voter `0x0037`, starting at `0x010`.

Memory contents:
```
mem[0x010] = 0x00000037  ← target (we want to find this)
mem[0x011] = 0x00000097
mem[0x012] = 0x00000106
```

But let's say the target is `0x0097` (second entry) to show the loop:

```
Cycle │ FEU State   │ PC    │ MAR   │ MBR           │ Comparator      │ Action
──────┼─────────────┼───────┼───────┼───────────────┼─────────────────┼───────────
  0   │ IDLE        │       │       │               │                 │ Latch SCAN
      │ PC←0x010, target←0x0097, end←0x10F          │                 │
      │             │       │       │               │                 │
  1   │ S_SCAN_ADDR │ 0x010 │       │               │                 │ mem_addr=PC
      │ MAR ← 0x010│       │       │               │                 │
      │             │       │       │               │                 │
  2   │ S_SCAN_READ │ 0x010 │ 0x010 │               │                 │ BRAM delivers
      │ MBR ← mem[0x010] = 0x00000037              │                 │
      │ PC ← 0x011 │       │       │               │                 │
      │             │       │       │               │                 │
  3   │ S_SCAN_CMP  │ 0x011 │ 0x010 │ 0x00000037    │ 0037 vs 0097    │ NO MATCH
      │             │       │       │               │ diff ≠ 0        │
      │ NID ≠ 0 and PC ≤ end → keep searching      │                 │
      │             │       │       │               │                 │
  4   │ S_SCAN_ADDR │ 0x011 │ 0x010 │ 0x00000037    │                 │ mem_addr=PC
      │ MAR ← 0x011│       │       │               │                 │
      │             │       │       │               │                 │
  5   │ S_SCAN_READ │ 0x011 │ 0x011 │               │                 │ BRAM delivers
      │ MBR ← mem[0x011] = 0x00000097              │                 │
      │ PC ← 0x012 │       │       │               │                 │
      │             │       │       │               │                 │
  6   │ S_SCAN_CMP  │ 0x012 │ 0x011 │ 0x00000097    │ 0097 vs 0097    │ MATCH! ✓
      │             │       │       │               │ diff = 0        │
      │ fe_match ← 1, fe_match_addr ← MAR = 0x011  │                 │
      │             │       │       │               │                 │
  7   │ S_SCAN_MATCH│ 0x012 │ 0x011 │ 0x00000097    │                 │ ALU LOAD
      │ ALU: AC ← MBR = 0x00000097                 │                 │
      │ (CU will check AC[16] for voted flag)       │                 │
      │             │       │       │               │                 │
  8   │ S_DONE      │       │       │               │                 │ fe_done=1
      │ CU reads: fe_match=1, fe_match_addr=0x011, fe_ac=0x00000097  │
```

**Why SCAN loads into AC**: After finding the NID, the Control Unit needs to check bit 16 (the "already voted" flag). By loading the full 32-bit entry into the accumulator, the CU can simply check `fe_ac[16]` — if it's `1`, the voter already voted → ERROR state.

---

## Summary: Register Roles

| Register | Lives In | Purpose | Analogy |
|---|---|---|---|
| **PC** | FEU | "Where to look" — address pointer, auto-increments for sequential access | A bookmark that moves forward |
| **MAR** | FEU | "Where we're looking right now" — stable address on the memory bus | The page currently open |
| **MBR** | FEU | "What we found / what to write" — holds data in transit | A clipboard |
| **AC** | ALU | "Working value" — where computation happens | A calculator display |

Data always flows through these registers — never directly between the Control Unit and BRAM.

---

## Worked Example: Full Vote Recording Pipeline

The Control Unit issues this sequence of FEU operations:

```
Step 1: READ addr=0x000        → FEU reads candidate 1's vote count into AC
Step 2: INC                    → AC becomes count+1
Step 3: WRITE_AC addr=0x000    → FEU writes AC back to candidate 1's address
Step 4: READ addr=matched_NID  → FEU reads the voter's NID entry into AC
Step 5: OR_ACC data=0x10000    → AC gets bit 16 set (voted flag)
Step 6: WRITE_AC addr=matched_NID → FEU writes marked entry back
```

Each step takes 3–4 clock cycles through the fetch-execute pipeline.

---

## Connection Diagram

```
                  controlUnit
                  ┌───────────────┐
                  │  fe_start ────┤──┐
                  │  fe_op [2:0] ─┤──┤
                  │  fe_addr [8:0]┤──┤    fetchExecuteUnit
                  │  fe_write_data┤──┤    ┌────────────────────┐
                  │  fe_scan_*  ──┤──┤───►│  PC ──► MAR        │
                  │               │  │    │         │          │
                  │  fe_done ◄────┤◄─┤────┤  M[MAR] → MBR     │───► memoryUnit
                  │  fe_match ◄───┤◄─┤────┤                    │◄─── mem_data_in
                  │  fe_match_addr┤◄─┤────┤  MBR → ALU (LOAD)  │
                  │  fe_ac ◄──────┤◄─┘    │         or          │───► ALU
                  └───────────────┘       │  ALU → M[MAR](WR)  │◄─── alu_acc
                                          └────────────────────┘
```

The FEU is the **bridge** between the Control Unit (which decides *what* to do) and the Memory + ALU (which *do* it). The Control Unit never directly touches memory or the ALU.
