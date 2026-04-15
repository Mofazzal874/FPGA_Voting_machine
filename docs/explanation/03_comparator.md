# Module 3: comparator — Subtractor-Based Equality Check

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/comparator.v`

---

## Purpose

The `comparator` module checks whether two 16-bit values are equal using a **subtractor-based approach** (rather than bitwise XOR). It computes `A - B` and checks if the difference is zero. This is a **purely combinational** module — no clock, no registers, result available in the same cycle.

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `input_a` | Input | 16 bits | First value (e.g., voter NID from switches) |
| `input_b` | Input | 16 bits | Second value (e.g., stored NID from memory) |
| `match` | Output | 1 bit | HIGH if `input_a == input_b` (difference is zero) |

---

## How It Works

```verilog
wire [16:0] diff = {1'b0, input_a} - {1'b0, input_b};
assign match = (diff == 17'd0);
```

1. Both inputs are **zero-extended to 17 bits** (`{1'b0, input_a}`) to prevent signed arithmetic issues.
2. The subtraction produces a 17-bit result.
3. If the difference is exactly zero → the inputs are equal → `match = 1`.

### Why Subtractor Instead of `==`?

While Verilog's `==` operator would also work, the subtractor-based approach is a common **DSD (Digital System Design) technique** that maps directly to hardware primitives — specifically a ripple-borrow or carry-lookahead subtractor with zero detect. This makes the design explicitly traceable to the underlying hardware.

---

## Two Instances in the Design

The comparator is instantiated **twice** in the system:

### Instance 1: Inside `fetchExecuteUnit` (NID Scan)

```verilog
comparator scan_cmp(
    .input_a(mbr[15:0]),         // Low 16 bits of memory data
    .input_b(scan_target_reg),   // NID entered by voter (from switches)
    .match(scan_match_wire)
);
```

Used during the SCAN operation to compare each NID entry in memory against the voter's entered NID. The FEU iterates through the NID table (addresses `0x010`–`0x10F`), and for each entry, this comparator checks if `MBR[15:0]` matches the target.

### Instance 2: Inside `controlUnit` (Admin Password)

```verilog
comparator admin_cmp(
    .input_a(saved_switches),    // Password entered by admin
    .input_b(fe_ac[15:0]),       // Password read from memory (via ALU accumulator)
    .match(admin_pw_match)
);
```

Used in the `S_ADMIN_RESULT` state to verify the admin password. The Control Unit reads the stored password from memory address `0x004`, then compares it against what the admin entered on the switches.

---

## Connection Diagram

```
              fetchExecuteUnit                    controlUnit
              ┌────────────────┐                 ┌────────────────┐
              │  mbr[15:0] ──┐ │                 │  saved_sw ───┐ │
              │              ▼ │                 │              ▼ │
              │  ┌───────────┐ │                 │  ┌───────────┐ │
              │  │comparator │ │                 │  │comparator │ │
              │  │ scan_cmp  │ │                 │  │ admin_cmp │ │
  scan_target─┤──►input_b   │ │     fe_ac[15:0]─┤──►input_b   │ │
              │  │  match────┤─┤──►scan_match    │  │  match────┤─┤──►admin_pw_match
              │  └───────────┘ │    (S_SCAN_CMP) │  └───────────┘ │    (S_ADMIN_RESULT)
              └────────────────┘                 └────────────────┘
```

---

## Timing

Because the comparator is **purely combinational**, the `match` output updates in the same clock cycle as the inputs change. There is no clock delay. This means:

- In the FEU: after `mbr` is loaded in `S_SCAN_READ`, the `match` result is valid by the time `S_SCAN_CMP` checks it (next clock edge).
- In the CU: after `fe_ac` is updated by the ALU, `admin_pw_match` is valid immediately for the `S_ADMIN_RESULT` state decision.
