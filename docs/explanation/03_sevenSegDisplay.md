# Module 3: sevenSegDisplay — 7-Segment Multiplexed Display Driver

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/sevenSegDisplay.v`

---

## Purpose

The `sevenSegDisplay` module drives the **4-digit common-anode seven-segment display** on the Basys 3 board. It shows the vote count for each of the 4 candidates simultaneously — one hex digit (0–F) per display position.

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `clock` | Input | 1 bit | 100 MHz system clock |
| `reset` | Input | 1 bit | Active-high synchronous reset |
| `cand1_count` | Input | 8 bits | Candidate 1 vote count (from voteLogger) |
| `cand2_count` | Input | 8 bits | Candidate 2 vote count |
| `cand3_count` | Input | 8 bits | Candidate 3 vote count |
| `cand4_count` | Input | 8 bits | Candidate 4 vote count |
| `seg` | Output | 7 bits | Cathode signals `{g,f,e,d,c,b,a}` — active-low |
| `dp` | Output | 1 bit | Decimal point — always OFF (tied to 1) |
| `an` | Output | 4 bits | Anode signals `{AN3,AN2,AN1,AN0}` — active-low |

---

## Understanding the Basys 3 Seven-Segment Display

The Basys 3 has **4 seven-segment digits** sharing a common set of 7 cathode lines. They are **multiplexed** — only one digit is actually lit at any instant, but they cycle so fast (~380 Hz) that the human eye perceives all 4 as lit simultaneously.

### Physical Segment Layout

```
    ___a___
   |       |
 f |       | b
   |___g___|
   |       |
 e |       | c
   |___d___|  .dp
```

### Active-Low Logic

The Basys 3 uses **common-anode** displays with **active-low** control:
- **Cathodes** (`seg[6:0]`): A segment lights up when its cathode is driven **LOW** (0)
- **Anodes** (`an[3:0]`): A digit is active when its anode is driven **LOW** (0)

So to light segment `a` on digit AN0: set `seg[0] = 0` and `an[0] = 0`.

---

## How It Works — Step by Step

### Step 1: Refresh Counter (Lines 23–30)

```verilog
reg [19:0] refresh_counter;

always @(posedge clock) begin
    if (reset)
        refresh_counter <= 20'd0;
    else
        refresh_counter <= refresh_counter + 1;
end

wire [1:0] digit_select = refresh_counter[19:18];
```

A free-running 20-bit counter increments every clock cycle. The **top 2 bits** (`[19:18]`) select which of the 4 digits is currently active.

**Timing math:**
- Counter range: 0 to 2^20 − 1 = 1,048,575
- Full cycle time: 1,048,576 × 10 ns = **10.49 ms**
- Each digit is active for: 10.49 ms / 4 = **2.62 ms**
- Refresh rate per digit: 1 / 2.62 ms ≈ **381 Hz**

At 381 Hz, the human eye cannot detect any flickering — all 4 digits appear continuously lit.

### Step 2: Digit Selection and Value Mapping (Lines 37–60)

```verilog
always @(*) begin
    case (digit_select)
        2'b00: begin  // AN0 = Candidate 4 (rightmost)
            an = 4'b1110;
            hex_digit = cand4_count[3:0];
        end
        2'b01: begin  // AN1 = Candidate 3
            an = 4'b1101;
            hex_digit = cand3_count[3:0];
        end
        2'b10: begin  // AN2 = Candidate 2
            an = 4'b1011;
            hex_digit = cand2_count[3:0];
        end
        2'b11: begin  // AN3 = Candidate 1 (leftmost)
            an = 4'b0111;
            hex_digit = cand1_count[3:0];
        end
    endcase
end
```

This combinational block does two things based on which digit is selected:

1. **Sets the anode pattern**: Only the selected digit's anode goes LOW (active), the other three are HIGH (inactive).

2. **Selects the vote count value**: Extracts the **low nibble** (`[3:0]` = bits 3 down to 0) of the corresponding candidate's count. This gives a 4-bit hex value (0–F).

**Digit Layout on the Board:**

```
  ┌─────────┬─────────┬─────────┬─────────┐
  │  AN3    │  AN2    │  AN1    │  AN0    │
  │ Cand 1  │ Cand 2  │ Cand 3  │ Cand 4  │
  │ (left)  │         │         │ (right) │
  └─────────┴─────────┴─────────┴─────────┘
```

### Step 3: Hex-to-Seven-Segment Decoder (Lines 64–84)

```verilog
always @(*) begin
    case (hex_digit)
        4'h0: seg = 7'b1000000;  //  _
        4'h1: seg = 7'b1111001;  // |   (only b,c)
        4'h2: seg = 7'b0100100;  //  _
        4'h3: seg = 7'b0110000;  //  _
        4'h4: seg = 7'b0011001;  //
        4'h5: seg = 7'b0010010;  //  _
        4'h6: seg = 7'b0000010;  //  _
        4'h7: seg = 7'b1111000;  //  _
        4'h8: seg = 7'b0000000;  //  _  (all segments on)
        4'h9: seg = 7'b0010000;  //  _
        4'hA: seg = 7'b0001000;  //  _
        4'hB: seg = 7'b0000011;  //     (lowercase b)
        4'hC: seg = 7'b1000110;  //  _
        4'hD: seg = 7'b0100001;  //     (lowercase d)
        4'hE: seg = 7'b0000110;  //  _
        4'hF: seg = 7'b0001110;  //  _
        default: seg = 7'b1111111; // all off
    endcase
end
```

This is a lookup table that converts a 4-bit hex value into the 7-segment pattern.

**Encoding format**: `seg = {g, f, e, d, c, b, a}` — remember, **0 = ON, 1 = OFF** (active-low).

**Example — displaying digit "0":**
- Segments ON: a, b, c, d, e, f (all except g)
- Segments OFF: g
- Pattern: `g=1, f=0, e=0, d=0, c=0, b=0, a=0` → `7'b1000000`

**Example — displaying digit "1":**
- Segments ON: b, c only
- Pattern: `g=1, f=1, e=1, d=1, c=0, b=0, a=1` → `7'b1111001`

### Complete Segment Map

| Hex | Segments ON | seg[6:0] | Display |
|---|---|---|---|
| 0 | a,b,c,d,e,f | `1000000` | `0` |
| 1 | b,c | `1111001` | `1` |
| 2 | a,b,d,e,g | `0100100` | `2` |
| 3 | a,b,c,d,g | `0110000` | `3` |
| 4 | b,c,f,g | `0011001` | `4` |
| 5 | a,c,d,f,g | `0010010` | `5` |
| 6 | a,c,d,e,f,g | `0000010` | `6` |
| 7 | a,b,c | `1111000` | `7` |
| 8 | a,b,c,d,e,f,g | `0000000` | `8` |
| 9 | a,b,c,d,f,g | `0010000` | `9` |
| A | a,b,c,e,f,g | `0001000` | `A` |
| B | c,d,e,f,g | `0000011` | `b` |
| C | a,d,e,f | `1000110` | `C` |
| D | b,c,d,e,g | `0100001` | `d` |
| E | a,d,e,f,g | `0000110` | `E` |
| F | a,e,f,g | `0001110` | `F` |

---

## Multiplexing Visualized

At any given instant, only ONE digit is lit. The display cycles through all 4 rapidly:

```
Time Slot 1 (2.6ms):  AN3=ON, others OFF → Shows Cand1 count
Time Slot 2 (2.6ms):  AN2=ON, others OFF → Shows Cand2 count
Time Slot 3 (2.6ms):  AN1=ON, others OFF → Shows Cand3 count
Time Slot 4 (2.6ms):  AN0=ON, others OFF → Shows Cand4 count
Time Slot 5:          Repeats from Slot 1...
```

Because this cycles at ~381 Hz per digit, human persistence of vision makes all 4 digits appear solidly lit.

---

## Behaviour on the FPGA Board

1. **After reset**: All 4 digits show `0` — the display reads `0 0 0 0`.

2. **Candidate 1 gets 3 votes**: Leftmost digit (AN3) changes to `3`. Display: `3 0 0 0`.

3. **Candidate 4 gets 12 votes**: 12 in hex = C. Rightmost digit (AN0) shows `C`. Display: `3 0 0 C`.

4. **Candidate 2 gets 16 votes**: 16 in hex = 10. Only the low nibble is shown, so `10 & 0xF = 0`. The display wraps: digit shows `0`. For counts above 15, the user should use the LED result mode (SW0 ON + press button) to see the full 8-bit binary value on the LEDs.

5. **Decimal point**: Always OFF. The `dp` output is permanently tied to `1` (inactive).

---

## Connection to Other Modules

```
voteLogger                    sevenSegDisplay
┌──────────────┐              ┌───────────────────┐
│ cand1_recvd ─├──[8 bits]───►│ cand1_count       │
│ cand2_recvd ─├──[8 bits]───►│ cand2_count       │
│ cand3_recvd ─├──[8 bits]───►│ cand3_count       │
│ cand4_recvd ─├──[8 bits]───►│ cand4_count       │
└──────────────┘              │                   │
                              │ refresh_counter   │
                              │ ↓                 │
          100MHz clock ──────►│ digit_select      │
                              │ ↓                 │
                              │ hex_to_seg decoder│
                              │ ↓                 │
                              │ seg[6:0] ─────────├──► 7-seg cathodes (W7..U7)
                              │ dp ───────────────├──► decimal point  (V7)
                              │ an[3:0] ──────────├──► digit anodes   (W4..U2)
                              └───────────────────┘
```

---

## Pin Mapping (from Basys3_constraints.xdc)

| Signal | FPGA Pin | Board Label |
|---|---|---|
| `seg[0]` (a) | W7 | CA |
| `seg[1]` (b) | W6 | CB |
| `seg[2]` (c) | U8 | CC |
| `seg[3]` (d) | V8 | CD |
| `seg[4]` (e) | U5 | CE |
| `seg[5]` (f) | V5 | CF |
| `seg[6]` (g) | U7 | CG |
| `dp` | V7 | DP |
| `an[0]` | U2 | AN0 (rightmost) |
| `an[1]` | U4 | AN1 |
| `an[2]` | V4 | AN2 |
| `an[3]` | W4 | AN3 (leftmost) |
