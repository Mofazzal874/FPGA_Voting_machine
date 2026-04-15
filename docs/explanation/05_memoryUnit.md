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

The BRAM is pre-loaded from `nid_table.hex` at synthesis time. This file contains:
- Addresses 0–3: initial vote counts (0)
- Address 4: admin password (e.g., `00002580` for password "2580")
- Addresses 16+: registered voter NIDs

On an FPGA, `initial` blocks are embedded into the bitstream — the BRAM starts with this data at power-on.

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
