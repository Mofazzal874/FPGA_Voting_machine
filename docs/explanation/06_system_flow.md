# System Flow — Complete Data Path and Voting Process

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/votingMachine.v` (Top Module)

---

## Overview

This document describes the **end-to-end flow** of the FPGA Voting Machine — from the moment a voter touches a button to the moment their vote appears on the seven-segment display. It explains how all 6 modules connect, what signals travel between them, and exactly what happens at each clock cycle.

---

## Module Hierarchy

```
votingMachine (Top Module)
├── buttonControl bc1       ← Candidate 1 button (BTNU)
├── buttonControl bc2       ← Candidate 2 button (BTNL)
├── buttonControl bc3       ← Candidate 3 button (BTNR)
├── buttonControl bc4       ← Candidate 4 button (BTND)
├── voteLogger VL           ← Counts votes per candidate
├── sevenSegDisplay SSD     ← Shows counts on 7-segment display
├── ALU alu_inst            ← Arithmetic operations
├── memoryUnit MEM          ← BRAM vote storage
├── [Memory Write Ctrl]     ← Inline logic in top module
├── [ALU Operation Ctrl]    ← Inline logic in top module
└── [LED Display Logic]     ← Inline logic in top module
```

---

## Physical I/O Mapping

```
BASYS 3 BOARD                           FPGA INTERNAL MODULES
┌─────────────────────────┐
│                         │
│  [BTNU] T18 ───────────├──► button1 ──► buttonControl bc1
│                         │
│  [BTNL] W19 ───────────├──► button2 ──► buttonControl bc2
│                         │
│  [BTNR] T17 ───────────├──► button3 ──► buttonControl bc3
│                         │
│  [BTND] U17 ───────────├──► button4 ──► buttonControl bc4
│                         │
│  [BTNC] U18 ───────────├──► reset   ──► ALL MODULES
│                         │
│  [SW0]  V17 ───────────├──► mode    ──► LED display logic
│                         │
│  [OSC]  W5  ───────────├──► clock   ──► ALL MODULES (100 MHz)
│                         │
│  [LED0-7] U16..V14 ◄───├──◄ led[7:0] ◄── LED display logic
│                         │
│  [SEG a-g] W7..U7  ◄───├──◄ seg[6:0] ◄── sevenSegDisplay
│  [DP]      V7      ◄───├──◄ dp       ◄── sevenSegDisplay
│  [AN0-3]   U2..W4  ◄───├──◄ an[3:0]  ◄── sevenSegDisplay
│                         │
└─────────────────────────┘
```

---

## Complete Signal Flow Diagram

```
                    ┌──────────────┐
 button1 ──────────►│buttonControl │──► valid_vote_1 ──┐
                    │     bc1      │                    │
                    └──────────────┘                    │
                    ┌──────────────┐                    │
 button2 ──────────►│buttonControl │──► valid_vote_2 ──┤
                    │     bc2      │                    │
                    └──────────────┘                    │        ┌──────────────┐
                    ┌──────────────┐                    ├───────►│  voteLogger  │
 button3 ──────────►│buttonControl │──► valid_vote_3 ──┤        │     VL       │
                    │     bc3      │                    │        │              │
                    └──────────────┘                    │        │ cand1 [7:0] ─├──┬──► sevenSegDisplay
                    ┌──────────────┐                    │        │ cand2 [7:0] ─├──┤    (7-seg display)
 button4 ──────────►│buttonControl │──► valid_vote_4 ──┘        │ cand3 [7:0] ─├──┤
                    │     bc4      │                             │ cand4 [7:0] ─├──┤
                    └──────────────┘                             └──────────────┘  │
                                                                                   │
                                      ┌───────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴───────────────────┐
                    │                                     │
                    ▼                                     ▼
           ┌──────────────┐                      ┌──────────────┐
           │  memoryUnit  │◄─── data_in ─────────│  Memory      │
           │     MEM      │                      │  Write Ctrl  │
           │              │                      │  (rotate     │
           │ BRAM 64×32   │                      │   addr 0-3)  │
           │ data_out ────├───► operand          └──────────────┘
           └──────────────┘         │
                                    ▼
                             ┌──────────────┐
                             │     ALU      │
              alu_op ───────►│   alu_inst   │
              (INC/NOP)      │              │
                             │ result ──────├───► (future: FSM)
                             │ overflow ────├───► (future: halt)
                             └──────────────┘

           ┌──────────────┐
  mode ───►│  LED Display │──► led[7:0] ──► LEDs on board
  buttons─►│  Logic       │
  counts──►│  (in top)    │
           └──────────────┘
```

---

## The Voting Process — Clock by Clock

Here is the **complete lifecycle of a single vote**, from button press to display update:

### Phase 1: Button Press Detection (~1 second)

**What the voter does**: Press and hold BTNU (Candidate 1).

**What happens internally:**

| Time | Clock Cycle | `button1` | `bc1.counter` | `bc1.valid_vote` | What's Happening |
|---|---|---|---|---|---|
| 0.000s | 0 | 1 | 0 | 0 | Button pressed, counter starts |
| 0.000s | 1 | 1 | 1 | 0 | Counter incrementing... |
| 0.000s | 2 | 1 | 2 | 0 | Counter incrementing... |
| ... | ... | 1 | ... | 0 | (99,999,997 cycles pass) |
| 1.000s | 99,999,999 | 1 | 99,999,999 | 0 | Almost there... |
| 1.000s | 100,000,000 | 1 | **100,000,000** | **1** | ✅ **VOTE PULSE!** |
| 1.000s | 100,000,001 | 1 | 100,000,001 | 0 | Pulse ends, counter stops |

The entire 1-second count happens at the hardware level. The voter just sees a brief moment where nothing happens, then the display changes.

### Phase 2: Vote Registration (1 clock cycle = 10 ns)

The single-cycle `valid_vote_1` pulse triggers three things simultaneously:

#### 2a. voteLogger Increments

```
Clock edge: valid_vote_1 goes HIGH
→ voteLogger: cand1_vote_recvd <= cand1_vote_recvd + 1
→ cand1_votes changes from 0 to 1
```

This happens in **one clock cycle** (10 ns). The counter is immediately updated.

#### 2b. ALU Receives INC

```
Clock edge: valid_vote_1 is HIGH
→ Top module: alu_op = 2'b01 (INC)
→ ALU: acc <= acc + 1
```

The ALU's accumulator increments, tracking total votes across all candidates.

#### 2c. Memory Gets Updated

```
Within the next 4 clock cycles (40 ns):
→ mem_write_sel rotates to 0
→ mem_addr = 0, mem_din = {24'd0, cand1_votes} = 1
→ mem[0] <= 1
```

The updated vote count is written to BRAM address 0. Since the write controller cycles through all 4 addresses every 4 clocks, the update reaches memory within 40 ns maximum.

### Phase 3: Display Update (Continuous)

The `sevenSegDisplay` module is **always running** — it doesn't need to be triggered. It continuously reads the vote count values and displays them:

```
sevenSegDisplay reads cand1_votes = 1
→ When digit_select = 2'b11 (AN3 turn):
   → hex_digit = 1
   → seg = 7'b1111001 (shows "1")
   → an = 4'b0111 (AN3 active)
```

The display updates appear **instantaneous** to the human eye because:
- The vote count changes in 10 ns
- The display cycles through all 4 digits in ~10.5 ms
- Human reaction time is ~200 ms

So the display showing "1" appears to happen the instant the voter completes their 1-second hold.

### Phase 4: LED Feedback

If the mode switch (SW0) is OFF (voting mode):

```
led = {0000, button4, button3, button2, button1}
    = {0000, 0, 0, 0, 1}
    = 00000001
→ LED0 is lit while BTNU is held
```

This gives the voter visual feedback that their button press is being registered.

---

## The Result Viewing Process

### Step 1: Flip SW0 to ON (mode = 1)

The system enters **result display mode**. The 7-segment display continues showing vote counts regardless of mode.

### Step 2: Press a Button

```
mode = 1, button2 pressed:
→ LED display logic:
   if (button2)
       led <= cand2_votes;
→ LEDs show the binary representation of Candidate 2's vote count
```

**Example**: If Candidate 2 has 5 votes:
- `cand2_votes = 8'b00000101`
- LEDs: `○ ○ ○ ○ ○ 1 ○ 1` (LED0 and LED2 lit)

This allows viewing counts larger than F (15) which the 7-segment hex display cannot show.

### Step 3: Release Button

```
mode = 1, no buttons pressed:
→ led <= 8'd0
→ All LEDs off
```

---

## Reset Process

When the user presses **BTNC** (center button), `reset` goes HIGH:

```
ALL MODULES SIMULTANEOUSLY:
├── buttonControl bc1-bc4: counter <= 0, valid_vote <= 0
├── voteLogger: all 4 counters <= 0
├── sevenSegDisplay: refresh_counter <= 0
├── ALU: acc <= 0, overflow <= 0
├── memoryUnit: (no runtime reset — but voteLogger zeros propagate)
│   └── Within 4 cycles: mem[0-3] all written with 0
└── LED logic: led <= 0
```

**Timeline:**
- Cycle 0: Reset asserted → all registers clear
- Cycle 1: voteLogger outputs are 0 → write controller starts writing 0 to mem[0]
- Cycle 2: 0 written to mem[1]
- Cycle 3: 0 written to mem[2]
- Cycle 4: 0 written to mem[3]
- Cycle 5+: Reset released → system ready for new votes

The entire reset completes in **50 nanoseconds** (5 clock cycles). The voter sees the display instantly show `0 0 0 0`.

---

## Concurrent Operations

Because this is **hardware** (not software), many things happen simultaneously on every clock edge:

```
EVERY CLOCK EDGE (every 10 ns):
   │
   ├── buttonControl bc1: check button1, update counter1
   ├── buttonControl bc2: check button2, update counter2
   ├── buttonControl bc3: check button3, update counter3
   ├── buttonControl bc4: check button4, update counter4      ← ALL PARALLEL
   │
   ├── voteLogger: check all 4 valid signals, update counts   ← PARALLEL
   │
   ├── sevenSegDisplay: increment refresh_counter              ← PARALLEL
   │   └── combinational: select digit, decode hex→segments
   │
   ├── ALU: check alu_op, update accumulator                  ← PARALLEL
   │
   ├── memoryUnit: write data_in if wr_en, read to data_out   ← PARALLEL
   │
   ├── Memory write ctrl: advance mem_write_sel                ← PARALLEL
   │
   └── LED logic: update led based on mode and buttons         ← PARALLEL
```

In software, these would need to be executed sequentially. In hardware, they all happen **at exactly the same time** on every rising clock edge. This is why FPGAs are so fast — true parallelism.

---

## Data Flow Summary Table

| Source | Signal | Width | Destination | Purpose |
|---|---|---|---|---|
| BTNU/L/R/D pins | `button1–4` | 1 bit each | `buttonControl` bc1–4 | Raw button input |
| `buttonControl` bc1–4 | `valid_vote_1–4` | 1 bit each | `voteLogger`, ALU ctrl | Vote registered pulse |
| `voteLogger` | `cand1–4_votes` | 8 bits each | `sevenSegDisplay`, Memory ctrl, LED logic | Current vote counts |
| `sevenSegDisplay` | `seg`, `dp`, `an` | 7+1+4 bits | FPGA pins → display | Visual output |
| Memory write ctrl | `mem_addr`, `mem_wr`, `mem_din` | 6+1+32 bits | `memoryUnit` | Store votes |
| `memoryUnit` | `mem_dout` | 32 bits | `ALU` operand | Data for computation |
| ALU ctrl logic | `alu_op` | 2 bits | `ALU` | Select operation |
| `ALU` | `alu_result`, `alu_overflow` | 32+1 bits | (Future: Control Unit) | Computation results |
| SW0 pin | `mode` | 1 bit | LED logic | Switch display mode |
| LED logic | `led` | 8 bits | FPGA pins → LEDs | Binary vote display |
| BTNC pin | `reset` | 1 bit | All modules | System reset |
| Oscillator W5 | `clock` | 1 bit | All modules | 100 MHz heartbeat |

---

## Complete Top Module Port-to-Pin Mapping

```verilog
// Top module declaration:
module votingMachine(
    input clock,        // W5   — 100 MHz oscillator
    input reset,        // U18  — BTNC (center)
    input mode,         // V17  — SW0 (slide switch)
    input button1,      // T18  — BTNU (up)     → Candidate 1
    input button2,      // W19  — BTNL (left)   → Candidate 2
    input button3,      // T17  — BTNR (right)  → Candidate 3
    input button4,      // U17  — BTND (down)   → Candidate 4
    output reg [7:0] led,  // U16..V14 — LED0 to LED7
    output [6:0] seg,      // W7..U7   — 7-seg cathodes {g,f,e,d,c,b,a}
    output dp,             // V7       — decimal point
    output [3:0] an        // U2..W4   — 7-seg anodes {AN3,AN2,AN1,AN0}
);
```

---

## What the Voter Sees — Complete Walkthrough

### Scenario: 3 votes for Candidate 1, 1 vote for Candidate 3

| Step | Voter Action | Time | 7-Seg Display | LEDs (mode=0) |
|---|---|---|---|---|
| 1 | Board powers on | 0s | `0 0 0 0` | All off |
| 2 | Hold BTNU | 0–1s | `0 0 0 0` | LED0 on |
| 3 | Release BTNU after 1s | 1s | `1 0 0 0` | LED0 off |
| 4 | Hold BTNU again | 1–2s | `1 0 0 0` | LED0 on |
| 5 | Release BTNU after 1s | 2s | `2 0 0 0` | LED0 off |
| 6 | Hold BTNU again | 2–3s | `2 0 0 0` | LED0 on |
| 7 | Release BTNU after 1s | 3s | `3 0 0 0` | LED0 off |
| 8 | Hold BTNR | 3–4s | `3 0 0 0` | LED2 on |
| 9 | Release BTNR after 1s | 4s | `3 0 1 0` | LED2 off |
| 10 | Flip SW0 ON | 4s | `3 0 1 0` | All off |
| 11 | Press BTNU briefly | 4s | `3 0 1 0` | `00000011` (3 in binary) |
| 12 | Press BTNR briefly | 4s | `3 0 1 0` | `00000001` (1 in binary) |
| 13 | Press BTNC | 4s | `0 0 0 0` | All off (reset) |
