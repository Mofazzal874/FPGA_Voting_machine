# Module 1: buttonControl — Button Hold Detection

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/buttonControl.v`

---

## Purpose

The `buttonControl` module prevents accidental or spurious votes by requiring the voter to **hold a physical push button for exactly 1 second** before a vote is registered. It acts as a debouncer and intentional-press filter combined. It also has an `enable` input so the Control Unit can gate when voting is allowed.

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `clock` | Input | 1 bit | 100 MHz system clock from Basys 3 oscillator (pin W5) |
| `reset` | Input | 1 bit | Active-high synchronous reset (from POR generator) |
| `enable` | Input | 1 bit | Must be HIGH for the button hold to register — controlled by the Control Unit's `vote_enable` signal |
| `button` | Input | 1 bit | Raw push button input from one of the directional buttons |
| `valid_vote` | Output | 1 bit | Single-cycle pulse when button has been held for exactly `HOLD_THRESHOLD` cycles |

---

## Parameters

| Parameter | Default Value | Description |
|---|---|---|
| `HOLD_THRESHOLD` | 100,000,000 | Number of clock cycles the button must be held (1 sec at 100 MHz). Overridden to small values (e.g. 10) in testbench for fast simulation |

---

## Internal Registers

| Register | Width | Purpose |
|---|---|---|
| `counter` | 31 bits | Counts consecutive clock cycles the button has been held while `enable` is HIGH |

---

## How It Works — Step by Step

### Counter Logic

```verilog
always @(posedge clock) begin
    if (reset)
        counter <= 0;
    else begin
        if (enable && button && counter < HOLD_THRESHOLD + 1)
            counter <= counter + 1;
        else if (!button)
            counter <= 0;
    end
end
```

**On every rising edge of the 100 MHz clock:**

1. **If `reset` is high**: Counter resets to zero immediately.

2. **If `enable` AND `button` are both HIGH and counter hasn't exceeded threshold + 1**: Counter increments by 1. Both conditions must be true — the Control Unit must have activated `vote_enable` AND the voter must be holding the button.

3. **If `button` is released** (goes low): Counter resets to zero regardless of `enable`. The voter must start over.

4. **If `enable` is LOW**: Counter does not increment even if the button is held. This prevents voting outside of the `S_VOTE_ACTIVE` state.

5. **If counter reaches `HOLD_THRESHOLD + 1`**: Counter stops incrementing (prevents overflow and ensures `valid_vote` fires only once).

### Vote Validation Logic

```verilog
always @(posedge clock) begin
    if (reset)
        valid_vote <= 1'b0;
    else begin
        if (counter == HOLD_THRESHOLD)
            valid_vote <= 1'b1;
        else
            valid_vote <= 1'b0;
    end
end
```

**On every rising edge:**

1. **If counter equals exactly `HOLD_THRESHOLD`**: `valid_vote` goes HIGH for **exactly one clock cycle** (10 ns). This is the moment the vote triggers.

2. **Next cycle**: Counter becomes `HOLD_THRESHOLD + 1`, so the `== HOLD_THRESHOLD` condition is no longer true, and `valid_vote` drops back LOW. This guarantees a **single-pulse output**.

---

## Timing Diagram

```
Time       : |--- 0.0s ---|--- 0.5s ---|--- 1.0s ---|--- 1.5s ---|
enable     : ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
button     : ____________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\___
counter    : 0000000000000 → incrementing → THRESHOLD → THRESHOLD+1 (stops)
valid_vote : ___________________________|‾|_____________________________
                                        ^ ONE clock cycle pulse
```

---

## Connection to Other Modules

```
Physical Button (e.g., BTNU pin T18)
         │
         ▼
   ┌─────────────────┐        controlUnit
   │  buttonControl   │        ┌─────────┐
   │                  │◄───────┤vote_enable (enable)
   │  button ──► counter ──► valid_vote──────────►controlUnit
   │  clock  ──►              │           (S_VOTE_ACTIVE)
   │  reset  ──►              │
   └──────────────────┘
```

**Four instances** of `buttonControl` exist in the top module (`bc1`–`bc4`), one per candidate button (BTNU, BTNL, BTNR, BTND). The `enable` input on all four is driven by the Control Unit's `vote_enable` signal, which is only HIGH in the `S_VOTE_ACTIVE` FSM state.
