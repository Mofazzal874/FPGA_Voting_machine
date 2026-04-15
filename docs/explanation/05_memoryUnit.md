# Module 5: memoryUnit — BRAM-Based Storage

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/memoryUnit.v`

---

## Purpose

The Memory Unit provides **512 × 32-bit on-chip storage** using the FPGA's Block RAM (BRAM). It is the **primary data store** for the entire voting system — holding candidate vote counts, the admin password, and the voter NID registry. Contents are pre-loaded from a hex file (`nid_table.hex`) at synthesis/simulation time.

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | Input | 1 bit | 100 MHz system clock |
| `reset` | Input | 1 bit | Active-high synchronous reset (currently unused — BRAM init via hex file) |
| `addr` | Input | 9 bits | Memory address (0–511) |
| `wr_en` | Input | 1 bit | Write enable — when HIGH, `data_in` is written to `mem[addr]` |
| `data_in` | Input | 32 bits | Data to write |
| `data_out` | Output | 32 bits | Data read from `mem[addr]` (1-cycle latency) |

---

## Memory Map

| Address Range | Hex | Size | Purpose |
|---|---|---|---|
| `0x000` – `0x003` | `000`–`003` | 4 × 32-bit | **Candidate 1–4 vote counts** |
| `0x004` | `004` | 1 × 32-bit | **Admin password** (BCD in bits [15:0]) |
| `0x005` | `005` | 1 × 32-bit | Election status flags (reserved) |
| `0x006` – `0x00F` | `006`–`00F` | 10 × 32-bit | Reserved |
| `0x010` – `0x10F` | `010`–`10F` | 256 × 32-bit | **NID table** (voter registry) |
| `0x110` – `0x1FF` | `110`–`1FF` | 240 × 32-bit | Reserved |

### NID Table Entry Format (32 bits)

```
Bits [31:17] : Unused (zero)
Bit  [16]    : Voted flag — 1 = this voter has already cast a vote
Bits [15:0]  : Voter NID — 16-bit BCD national ID number
```

Example NID table entries in hex:
- `00000037` — NID 0037, not yet voted
- `00010037` — NID 0037, **already voted** (bit 16 set)

---

## Initialization

```verilog
initial begin
    $readmemh("nid_table.hex", mem);
end
```

The BRAM is pre-loaded from `nid_table.hex` at synthesis time. Each line in the file corresponds to one BRAM address (line 1 = address 0, line 2 = address 1, etc.). On an FPGA, `initial` blocks are embedded into the bitstream — the BRAM starts with this data at power-on.

### Hex File Layout — Line by Line

```
Line   Address   Content              Purpose
─────────────────────────────────────────────────────────────
 1     0x000     00000000             Candidate 1 vote count (starts at 0)
 2     0x001     00000000             Candidate 2 vote count (starts at 0)
 3     0x002     00000000             Candidate 3 vote count (starts at 0)
 4     0x003     00000000             Candidate 4 vote count (starts at 0)
 5     0x004     00002580             Admin password (BCD "2580")         ★
 6     0x005     00000000             Election status flags (reserved)
 7–16  0x006–0x00F  00000000 ×10      Reserved gap (alignment padding)
17     0x010     00000037             First registered NID (voter 0037)
18     0x011     00000097             Second NID (voter 0097)
19     0x012     00000106             Third NID (voter 0106)
...    ...       ...                  ... (256 NID slots total)
272    0x10F     00009938             Last registered NID
273–512 0x110–0x1FF 00000000 ×240    Unused BRAM (filled with zeros)
```

### Why Are There Zeros Before the Password? (Lines 1–4)

Those are the **4 candidate vote counters**. They initialize to zero because no votes have been cast yet. During voting, the FEU writes incremented counts back to these addresses (e.g., Candidate 1 at `0x000`).

### Why Are There Zeros After the Password? (Lines 6–16)

- **Line 6** (addr `0x005`): Reserved for election status flags — not currently used.
- **Lines 7–16** (addr `0x006`–`0x00F`): A **reserved gap** of 10 empty addresses. This keeps the NID table aligned at a clean starting address (`0x010` = decimal 16), making the memory map organized and the address arithmetic simple.

### Why Are There Zeros After the NIDs? (Lines 273–512)

Two reasons:

1. **End-of-table marker**: The FEU's SCAN operation treats `NID == 0` as an end-of-table sentinel. When scanning the NID table for a voter, if it hits a zero entry, it stops searching and reports "no match." So the zeros after the last real NID (line 272) act as a terminator.

2. **BRAM fill**: `$readmemh` loads into a 512-entry array (`mem[0:511]`), so the hex file has 512 lines to fully initialize all BRAM locations. Any uninitialized entries would be undefined.

---

## Configuration Guide

### Changing the Admin Password

Edit **line 5** of `nid_table.hex`. The password is the lower 16 bits in BCD format:

```
00001234    ← password becomes "1234" (switches set to 0x1234)
```

No code changes needed — the password is data, not logic.

### Changing the Election Duration

Edit [`votingTimer.v`](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/sources_1/new/votingTimer.v) line 8:

```verilog
parameter ELECTION_MINS = 10    // ← change to desired minutes
```

Or override from the top module `votingMachine.v` (line 130):

```verilog
votingTimer #(
    .ONE_SEC(ONE_SEC),
    .ELECTION_MINS(5)           // ← 5-minute election
) TIMER( ... );
```

---

## Read/Write Behavior

```verilog
always @(posedge clk) begin
    if (wr_en)
        mem[addr] <= data_in;
    data_out <= mem[addr];
end
```

- **Single-port BRAM, read-first mode**: On each clock edge, the read always happens, and if `wr_en` is HIGH, the write also happens. If both target the same address, the output shows the **old value** (read before write).
- **1-cycle latency**: Data appears on `data_out` one cycle after the address is presented.
- The `(* ram_style = "block" *)` attribute forces Vivado to use dedicated BRAM tiles (not LUTs).

---

## Timing — Read Operation

```
Clock    : __|‾‾|__|‾‾|__|‾‾|__
addr     :   010 |  011 |  012
wr_en    :   0   |   0  |   0
data_out :  old  | mem[010] | mem[011]
                   ↑
            1-cycle read latency
```

---

## Connection to Other Modules

```
         fetchExecuteUnit
         ┌──────────────────┐
         │                  │
         │  mem_addr [8:0] ─┤────► memoryUnit.addr
         │                  │
         │  mem_wr_en ──────┤────► memoryUnit.wr_en
         │                  │
         │  mem_data_out ───┤────► memoryUnit.data_in
         │   [31:0]         │
         │                  │
         │  mem_data_in ◄───┤◄──── memoryUnit.data_out
         │   [31:0]         │
         └──────────────────┘
```

The FEU is the **sole master** of the memory bus. It controls the address, write enable, and write data. The Control Unit never touches memory directly — it always goes through the FEU.

---

## FPGA Resource Usage

| Resource | Usage |
|---|---|
| BRAM tiles | 1 of 50 available (~2%) |
| Storage capacity | 512 × 32 = 16,384 bits (1 BRAM tile = 36 Kbit) |
| LUTs | 0 (all storage in BRAM) |
| Read latency | 1 clock cycle (10 ns) |
