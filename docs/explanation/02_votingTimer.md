# Module 2: votingTimer — Election Countdown Timer

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/votingTimer.v`

---

## Purpose

The `votingTimer` module implements a **10-minute election countdown**. Once the admin starts an election, the timer counts down from 10 minutes to 0. While active, `voting_active` is HIGH, allowing voters to authenticate and cast votes. When the timer expires, `voting_active` goes LOW, and the system switches to admin-only mode (result viewing / new election).

This module replaced the old `voteLogger` module, which was removed when vote counting moved into the Control Unit → FEU → Memory pipeline.

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | Input | 1 bit | 100 MHz system clock |
| `reset` | Input | 1 bit | Active-high synchronous reset (POR) |
| `timer_start` | Input | 1 bit | Single-cycle pulse from Control Unit to begin the election |
| `timer_reset` | Input | 1 bit | Single-cycle pulse from Control Unit to reset all counters (new election) |
| `voting_active` | Output | 1 bit | HIGH while election is in progress (countdown > 0) |
| `mins_remaining` | Output | 4 bits | Countdown value: 10 → 0 |

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `ONE_SEC` | 100,000,000 | Clock cycles per second (1 sec at 100 MHz). Override to small value for simulation. |
| `ELECTION_MINS` | 10 | Election duration in minutes |

---

## Internal Registers

| Register | Width | Purpose |
|---|---|---|
| `active` | 1 bit | Whether the timer is currently counting |
| `sec_counter` | 27 bits | Counts clock cycles within 1 second (0 to `ONE_SEC - 1`) |
| `sec_in_min` | 6 bits | Counts seconds within current minute (0–59) |
| `mins_elapsed` | 4 bits | Minutes elapsed since election start (0 to `ELECTION_MINS`) |

---

## How It Works — Step by Step

### Cascaded Counter Architecture

The timer uses **three cascaded counters** — no hardware division is needed:

```
Clock cycles (100 MHz)        Seconds (0–59)         Minutes (0–10)
┌──────────────────┐         ┌──────────────┐        ┌──────────────┐
│ sec_counter      │──roll──►│ sec_in_min   │──roll─►│ mins_elapsed │
│ 0 → ONE_SEC - 1  │ over    │ 0 → 59       │ over   │ 0 → ELECTION │
└──────────────────┘         └──────────────┘        └──────────────┘
```

1. `sec_counter` counts from 0 to `ONE_SEC - 1` (100 million cycles = 1 second)
2. When `sec_counter` rolls over → `sec_in_min` increments
3. When `sec_in_min` reaches 59 and rolls over → `mins_elapsed` increments
4. When `mins_elapsed >= ELECTION_MINS` → timer expires, `active <= 0`

### State Transitions

```
                 timer_start
    INACTIVE ──────────────► COUNTING
        ▲                       │
        │                       │ mins_elapsed >= ELECTION_MINS
        │                       ▼
        └──────────────── EXPIRED (active goes LOW)

                 timer_reset
    ANY STATE ──────────────► INACTIVE (counters zeroed)
                              (if timer_start also asserted, goes to COUNTING)
```

### Timer Start + Reset Combo

When the admin starts a new election, the Control Unit asserts both `timer_reset` and `timer_start` in the same cycle (`S_TIMER_START` state). The timer handles this specially:

```verilog
else if (timer_reset) begin
    sec_counter  <= 0;
    sec_in_min   <= 0;
    mins_elapsed <= 0;
    active       <= timer_start ? 1'b1 : 1'b0;  // Start immediately
end
```

### Minutes Remaining Output

```verilog
assign mins_remaining = (ELECTION_MINS > mins_elapsed) ?
                        (ELECTION_MINS[3:0] - mins_elapsed) : 4'd0;
```

This is a simple subtraction: `10 - elapsed`. Outputs 0 when expired.

---

## Connection to Other Modules

```
controlUnit (S_TIMER_START)
    │
    ├── timer_start ──► votingTimer ──► voting_active ──► controlUnit
    │                                                     (gates S_IDLE branching)
    └── timer_reset ──►             ──► mins_remaining
                                        (available for display)
```

- **Input from**: Control Unit (`timer_start`, `timer_reset` signals from `S_TIMER_START` state)
- **Output to**: Control Unit (`voting_active` determines whether BTNC triggers voter auth or admin login in `S_IDLE`)
