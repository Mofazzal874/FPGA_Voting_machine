# Module 2: voteLogger — Vote Counter

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/voteLogger.v`

---

## Purpose

The `voteLogger` module is a **4-channel vote counter**. Each channel corresponds to one candidate. When it receives a `valid_vote` pulse from a `buttonControl` instance, it increments the corresponding candidate's count by 1. All counts are stored in 8-bit registers, supporting 0–255 votes per candidate.

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `clock` | Input | 1 bit | 100 MHz system clock |
| `reset` | Input | 1 bit | Active-high synchronous reset — clears all counts to zero |
| `cand1_vote_valid` | Input | 1 bit | Single-cycle pulse from `buttonControl` bc1 — candidate 1 got a vote |
| `cand2_vote_valid` | Input | 1 bit | Pulse from bc2 — candidate 2 got a vote |
| `cand3_vote_valid` | Input | 1 bit | Pulse from bc3 — candidate 3 got a vote |
| `cand4_vote_valid` | Input | 1 bit | Pulse from bc4 — candidate 4 got a vote |
| `cand1_vote_recvd` | Output | 8 bits | Current total votes for candidate 1 |
| `cand2_vote_recvd` | Output | 8 bits | Current total votes for candidate 2 |
| `cand3_vote_recvd` | Output | 8 bits | Current total votes for candidate 3 |
| `cand4_vote_recvd` | Output | 8 bits | Current total votes for candidate 4 |

---

## How It Works — Step by Step

```verilog
always @(posedge clock) begin
    if (reset) begin
        cand1_vote_recvd <= 8'd0;
        cand2_vote_recvd <= 8'd0;
        cand3_vote_recvd <= 8'd0;
        cand4_vote_recvd <= 8'd0;
    end
    else begin
        if (cand1_vote_valid)
            cand1_vote_recvd <= cand1_vote_recvd + 1;
        if (cand2_vote_valid)
            cand2_vote_recvd <= cand2_vote_recvd + 1;
        if (cand3_vote_valid)
            cand3_vote_recvd <= cand3_vote_recvd + 1;
        if (cand4_vote_valid)
            cand4_vote_recvd <= cand4_vote_recvd + 1;
    end
end
```

**On every rising edge of the clock:**

1. **If `reset` is high**: All four counters are cleared to zero.

2. **If `cand1_vote_valid` is high**: Candidate 1's counter increments by 1.

3. **If `cand2_vote_valid` is high**: Candidate 2's counter increments by 1 (independently).

4. Same for candidates 3 and 4.

### Important Design Decision: Independent `if` Blocks

Notice these are **separate `if` statements**, NOT `else if` chains:

```verilog
if (cand1_vote_valid)    // ← independent if
    ...
if (cand2_vote_valid)    // ← NOT else if
    ...
```

This means **multiple candidates can receive votes on the same clock cycle**. If two voters somehow press their buttons at the exact same 10ns clock edge after holding for 1 second, both votes are counted. With `else if`, only the first matching candidate would get the vote and the other would be silently dropped.

In practice, simultaneous valid_vote pulses are extremely rare since the 1-second hold timing makes exact overlap nearly impossible. But the design is correct regardless.

---

## 8-Bit Counter Range

Each counter is 8 bits wide:
- **Minimum**: 0 (after reset)
- **Maximum**: 255

If a candidate receives more than 255 votes, the counter **wraps around to zero** (8-bit overflow). For a demo or classroom setting, 255 votes is more than sufficient. For a production system, wider counters (32-bit) would be used — the `memoryUnit` already stores 32-bit values for this reason.

---

## Behaviour on the FPGA Board

1. **Power on / Reset**: All 4 counters read zero. The 7-segment display shows `0 0 0 0`.

2. **Voter holds BTNU for 1 second**: `buttonControl` bc1 produces a single `valid_vote_1` pulse. On that clock edge, `cand1_vote_recvd` goes from `0` to `1`. The 7-segment display digit for Candidate 1 updates from `0` to `1`.

3. **Another voter holds BTNU for 1 second**: `cand1_vote_recvd` goes from `1` to `2`. Display shows `2`.

4. **Voter holds BTND for 1 second**: `cand4_vote_recvd` increments. Display shows count for Candidate 4.

5. **Admin presses BTNC**: All counters reset to zero. Display shows `0 0 0 0`.

---

## Timing Example

```
Clock     : _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
cand1_valid: ________|‾‾‾|________________________  (1 cycle pulse)
cand1_count: ===0====|===1========================  (latched on rising edge)
cand2_valid: ________________________|‾‾‾|________  (1 cycle pulse)
cand2_count: ===0====================|===1========
```

Each `valid` pulse is exactly 1 clock cycle wide (10 ns). The counter captures it on the next rising clock edge.

---

## Connection to Other Modules

```
buttonControl bc1 ──valid_vote_1──►┐
buttonControl bc2 ──valid_vote_2──►│
buttonControl bc3 ──valid_vote_3──►│  ┌──────────────┐
buttonControl bc4 ──valid_vote_4──►├─►│  voteLogger   │
                                   │  │              │
       clock ─────────────────────►│  │  counts[7:0] ├──► sevenSegDisplay
       reset ─────────────────────►│  │  per candidate├──► LED display
                                      └──────────────┘    ──► memoryUnit
```

The voteLogger outputs feed three downstream modules:
1. **sevenSegDisplay** — shows hex digit on each of the 4 displays
2. **LED display logic** — shows binary count when in result mode
3. **memoryUnit** — shadow-stores vote counts in BRAM
