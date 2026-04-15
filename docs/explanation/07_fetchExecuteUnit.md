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

## Worked Example: Voting for Candidate 1

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
