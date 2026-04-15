# Module 6: sevenSegDisplay — 7-Segment Multiplexed Display Driver

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/sevenSegDisplay.v`

---

## Purpose

The `sevenSegDisplay` module drives the **4-digit common-anode seven-segment display** on the Basys 3 board. It supports two display categories:

1. **Hex mode** (`display_mode = 0`): Shows a 16-bit `display_value` as 4 hex digits
2. **Text modes** (`display_mode = 1–4`): Shows fixed text messages — "donE", "Err ", "uotE" (vote), "PASS"

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `clock` | Input | 1 bit | 100 MHz system clock |
| `reset` | Input | 1 bit | Active-high synchronous reset |
| `display_value` | Input | 16 bits | Value to show in hex mode (4 digits, each 4 bits) |
| `display_mode` | Input | 3 bits | Display mode selector (see table below) |
| `seg` | Output | 7 bits | Cathodes `{g,f,e,d,c,b,a}` — active-low |
| `dp` | Output | 1 bit | Decimal point — always OFF (tied HIGH) |
| `an` | Output | 4 bits | Anodes `{AN3,AN2,AN1,AN0}` — active-low |

---

## Display Modes

| `display_mode` | Name | Display | When Used |
|---|---|---|---|
| `3'd0` | **HEX** | Shows `display_value` as 4 hex digits | IDLE (switch preview), AUTH (NID), RESULT (vote counts) |
| `3'd1` | **donE** | Shows "donE" | (Available, currently unused) |
| `3'd2` | **Err** | Shows "Err " | ERROR state — invalid NID or duplicate vote |
| `3'd3` | **uotE** | Shows "uotE" (vote) | VOTE_ACTIVE — waiting for candidate selection |
| `3'd4` | **PASS** | Shows "PASS" | CONFIRM — vote successfully recorded |

---

## How It Works

### Step 1: Refresh Counter — Digit Multiplexing

```verilog
reg [19:0] refresh_counter;
wire [1:0] digit_select = refresh_counter[19:18];
```

A 20-bit free-running counter cycles through its full range. The **top 2 bits** select which of the 4 digits is active:

- Each digit is active for `2^18 × 10 ns = 2.62 ms`
- Refresh rate: **~381 Hz per digit** — no visible flicker

### Step 2: Hex Digit Extraction

```verilog
case (digit_select)
    2'b00: hex_digit = display_value[3:0];    // AN0 (rightmost)
    2'b01: hex_digit = display_value[7:4];    // AN1
    2'b10: hex_digit = display_value[11:8];   // AN2
    2'b11: hex_digit = display_value[15:12];  // AN3 (leftmost)
endcase
```

Each 4-bit nibble of `display_value` maps to one display position.

### Step 3: Hex-to-Segment Decoder

Standard lookup table converting 4-bit hex (0–F) to the 7-segment pattern. For example:
- `4'h0` → `7'b1000000` (segments a,b,c,d,e,f ON, g OFF)
- `4'h1` → `7'b1111001` (segments b,c ON only)

### Step 4: Text Mode Characters

Custom character definitions using segment patterns:

| Character | Pattern | Segments ON |
|---|---|---|
| `d` | `7'b0100001` | b, c, d, e, g |
| `o` | `7'b0100011` | c, d, e, g |
| `n` | `7'b0101011` | c, e, g |
| `E` | `7'b0000110` | a, d, e, f, g |
| `r` | `7'b0101111` | e, g |
| `u` | `7'b1100011` | b, c, d, e |
| `t` | `7'b0000111` | d, e, f, g |
| `P` | `7'b0001100` | a, b, e, f, g |
| `A` | `7'b0001000` | a, b, c, e, f, g |
| `S` | `7'b0010010` | a, c, d, f, g |

### Step 5: Output Multiplexer

```verilog
if (display_mode == 3'd0)
    seg = hex_seg;      // Hex mode
else
    seg = text_seg;     // Text mode
```

---

## Connection to Other Modules

```
controlUnit
┌──────────────────┐
│ display_value ───┤────► sevenSegDisplay ────► seg[6:0]  → Board cathodes
│  [15:0]          │                      ────► dp        → Decimal point
│ display_mode ────┤                      ────► an[3:0]   → Board anodes
│  [2:0]           │
└──────────────────┘
```

- **Input from**: Control Unit (`display_value` and `display_mode` — both driven combinationally based on FSM state)
- **Output to**: FPGA pins → physical 7-segment display on Basys 3

### What the Display Shows Per FSM State

| FSM State | Display Mode | What You See |
|---|---|---|
| `S_IDLE` | HEX | Live switch value (NID preview) |
| `S_VOTER_AUTH`, `S_WAIT_FE` | HEX | Saved NID value |
| `S_VOTE_ACTIVE` | uotE | "uotE" — prompting candidate selection |
| `S_RV_*` (recording) | uotE | "uotE" — vote being recorded |
| `S_CONFIRM` | PASS | "PASS" — vote confirmed |
| `S_ERROR` | Err | "Err " — authentication failed |
| `S_RESULT_DISPLAY` | HEX | Vote count for viewed candidate |
| `S_ADMIN_LOGIN` | HEX | `0xAAAA` pattern |
