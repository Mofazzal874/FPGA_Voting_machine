# Module 1: buttonControl — Button Hold Detection

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/buttonControl.v`

---

## Purpose

The `buttonControl` module prevents accidental or spurious votes by requiring the voter to **hold a physical push button for exactly 1 second** before a vote is registered. It acts as a debouncer and intentional-press filter combined.

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `clock` | Input | 1 bit | 100 MHz system clock from Basys 3 oscillator (pin W5) |
| `reset` | Input | 1 bit | Active-high synchronous reset (BTNC, pin U18) |
| `button` | Input | 1 bit | Raw push button input from one of the directional buttons |
| `valid_vote` | Output | 1 bit | Single-cycle pulse when button has been held for exactly 1 second |

---

## Internal Registers

| Register | Width | Purpose |
|---|---|---|
| `counter` | 31 bits | Counts the number of consecutive clock cycles the button has been held down |

A 31-bit counter can count up to 2^31 − 1 = 2,147,483,647 — more than enough for 100,000,000 (the target).

---

## How It Works — Step by Step

### Counter Logic (Lines 15–24)

```verilog
always @(posedge clock) begin
    if (reset)
        counter <= 0;
    else begin
        if (button && counter < 100000001)
            counter <= counter + 1;
        else if (!button)
            counter <= 0;
    end
end
```

**On every rising edge of the 100 MHz clock:**

1. **If `reset` is high**: Counter resets to zero immediately. This happens when the user presses the center button (BTNC).

2. **If `button` is pressed AND counter hasn't exceeded 100,000,001**: Counter increments by 1 each clock cycle. This means the counter steadily climbs as long as the user keeps holding the button.

3. **If `button` is released** (goes low): Counter resets to zero. The user must start over if they release the button early.

4. **If counter reaches 100,000,001**: Counter stops incrementing (the `< 100000001` condition prevents further counting). This prevents overflow and ensures `valid_vote` fires only once.

### Vote Validation Logic (Lines 26–35)

```verilog
always @(posedge clock) begin
    if (reset)
        valid_vote <= 1'b0;
    else begin
        if (counter == 100000000)
            valid_vote <= 1'b1;
        else
            valid_vote <= 1'b0;
    end
end
```

**On every rising edge of the clock:**

1. **If `reset` is high**: `valid_vote` is driven low.

2. **If `counter` equals exactly 100,000,000**: `valid_vote` goes high for **exactly one clock cycle** (10 nanoseconds at 100 MHz). This is the moment the vote is registered.

3. **On the very next cycle**: Counter becomes 100,000,001, which no longer matches the `== 100000000` condition, so `valid_vote` drops back to low. This guarantees a **single-pulse output**.

---

## Timing Diagram

```
Time     : |--- 0.0s ---|--- 0.5s ---|--- 1.0s ---|--- 1.5s ---|
button   : ____________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\___
counter  : 0000000000000 → incrementing → 100000000 → 100000001 (stops)
valid_vote: ___________________________|‾|_____________________________
                                       ^ ONE clock cycle pulse
```

---

## Behaviour on the FPGA Board

1. **User presses BTNU** (for Candidate 1): Nothing happens immediately. The counter starts incrementing internally.

2. **User holds for less than 1 second, then releases**: Counter resets. No vote counted. Nothing visible changes.

3. **User holds for exactly 1 second**: A single `valid_vote` pulse is generated. This pulse travels to the `voteLogger` module, which increments the candidate's count. The 7-segment display updates the corresponding digit.

4. **User keeps holding beyond 1 second**: No additional votes — the counter is stuck at 100,000,001 and the `== 100000000` condition can never trigger again until the button is released and pressed again.

5. **User releases and presses again**: Counter starts from zero, and after another 1 second of holding, another single vote pulse is generated.

---

## Why 100,000,000?

The Basys 3 board has a 100 MHz clock. This means:
- 1 clock cycle = 1 / 100,000,000 Hz = **10 nanoseconds**
- 100,000,000 cycles × 10 ns = **1,000,000,000 ns = 1 second**

So the module counts exactly 100 million clock edges, corresponding to exactly 1 second of real time.

---

## Connection to Other Modules

```
Physical Button (e.g., BTNU pin T18)
         │
         ▼
   ┌─────────────────┐
   │  buttonControl   │
   │                  │
   │  button ──► counter ──► valid_vote
   │  clock  ──►              │
   │  reset  ──►              │
   └──────────────────┘       │
                              ▼
                        voteLogger
                   (increments candidate count)
```

Four instances of `buttonControl` exist in the top module (bc1–bc4), one per candidate button.
