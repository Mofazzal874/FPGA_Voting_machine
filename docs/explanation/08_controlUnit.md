# Module 8: controlUnit — Main FSM (Finite State Machine)

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/controlUnit.v`

---

## Purpose

The Control Unit is the **brain** of the voting machine — a **Moore-type Finite State Machine** with 23 states that orchestrates the entire voting lifecycle. It handles:

- **Voter authentication**: NID lookup via FEU SCAN, duplicate vote detection
- **Vote recording**: Read-modify-write cycle via FEU → ALU → Memory
- **Admin login**: Password verification via memory read + comparator
- **Result display**: Reading vote counts per candidate
- **Election management**: Resetting vote counts, clearing voted flags, starting the timer

---

## Port Description

### Inputs

| Port | Width | Description |
|---|---|---|
| `clk` | 1 | System clock |
| `reset` | 1 | POR reset |
| `switches[15:0]` | 16 | Switch input (NID or admin password) |
| `btnc_pulse` | 1 | Single-cycle debounced BTNC pulse |
| `valid_vote_1–4` | 1 each | From buttonControl — 1-sec hold vote pulses |
| `button1–4_raw` | 1 each | Raw button inputs (for result viewing, no hold needed) |
| `voting_active` | 1 | From votingTimer — election in progress |
| `fe_done` | 1 | From FEU — operation complete |
| `fe_match` | 1 | From FEU — SCAN found match |
| `fe_match_addr[8:0]` | 9 | From FEU — address of matched NID |
| `fe_ac[31:0]` | 32 | ALU accumulator (via FEU) |

### Outputs

| Port | Width | Description |
|---|---|---|
| `timer_start`, `timer_reset` | 1 each | Controls for votingTimer |
| `fe_start`, `fe_op`, `fe_addr`, `fe_write_data`, `fe_scan_target`, `fe_scan_end` | various | FEU command interface |
| `display_value[15:0]` | 16 | Value for 7-segment display |
| `display_mode[2:0]` | 3 | Display mode (hex/donE/Err/uotE/PASS) |
| `led_out[15:0]` | 16 | LED pattern |
| `vote_enable` | 1 | Enables buttonControl modules |

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `CONFIRM_CYCLES` | 100,000,000 | Duration for vote confirmation display (1 sec) |
| `ERROR_CYCLES` | 200,000,000 | Duration for error display (2 sec) |

---

## Memory Addresses (Constants)

| Name | Address | Purpose |
|---|---|---|
| `ADDR_CAND1` | `0x000` | Candidate 1 vote count |
| `ADDR_CAND4` | `0x003` | Candidate 4 vote count |
| `ADDR_ADMIN_PW` | `0x004` | Admin password |
| `ADDR_NID_START` | `0x010` | First NID table entry |
| `ADDR_NID_END` | `0x10F` | Last NID table entry |

---

## FSM State Map (23 States)

### Voter Path

```
S_IDLE ──(btnc + voting_active)──► S_VOTER_AUTH ──► S_WAIT_FE ──► S_AUTH_RESULT
                                                                      │
                                        ┌──── (NID not found) ────────┤
                                        ▼                             │
                                    S_ERROR ──(2s)──► S_IDLE    (already voted)──► S_ERROR
                                                                      │
                                                               (valid voter) ──► S_VOTE_ACTIVE
                                                                                     │
                                                                            (button held 1s)
                                                                                     ▼
                                      S_RV_READ ──► S_RV_INC ──► S_RV_WRITE
                                                                      │
                                      S_RV_FLAG_READ ◄────────────────┘
                                          │
                                      S_RV_FLAG_OR ──► S_RV_FLAG_WRITE ──► S_CONFIRM
                                                                              │
                                                                         (1s) ▼
                                                                          S_IDLE
```

### Admin Path

```
S_IDLE ──(btnc + !voting_active)──► S_ADMIN_LOGIN ──► S_WAIT_FE ──► S_ADMIN_RESULT
                                                                         │
                                              (wrong password) ──► S_ERROR
                                                                         │
                                              (correct) ──► S_RESULT_DISPLAY
                                                                  │        │
                                              (button press) ─────┘        │
                                              S_RESULT_READ ──► S_RESULT_SHOW
                                                                           │
                                              (btnc) ──► S_ADMIN_RESET ───┘
                                                             │
                                              S_ADMIN_RESET_FLAGS ──► S_ADMIN_RESET_FRD
                                                                          │
                                              S_ADMIN_RESET_FWR ◄────────┘
                                                     │
                                              S_TIMER_START ──► S_IDLE
```

---

## State Descriptions

### IDLE (`S_IDLE = 0`)
- **Display**: Live switch value (hex), LED15 = voting status
- **Behavior**: Waits for BTNC. If `voting_active` → voter auth path. If not → admin path.
- **Latches**: `saved_switches ← switches` on BTNC pulse.

### VOTER_AUTH (`S_VOTER_AUTH = 1`)
- **FEU command**: `SCAN` from `ADDR_NID_START` to `ADDR_NID_END`, target = `saved_switches`
- **Transitions**: → `WAIT_FE` (return to `AUTH_RESULT`)

### WAIT_FE (`S_WAIT_FE = 2`) — Generic Wait State
- A **reusable wait state** that watches for `fe_done`. When done, transitions to whatever `return_state` was set.
- This avoids duplicating wait logic for every FEU operation (there are 12+ different FEU operations).

### AUTH_RESULT (`S_AUTH_RESULT = 3`)
- Checks `fe_match` (NID found?) and `fe_ac[16]` (already voted flag)
- Three outcomes: valid voter → `VOTE_ACTIVE`, already voted → `ERROR`, not found → `ERROR`

### VOTE_ACTIVE (`S_VOTE_ACTIVE = 4`)
- **Display**: "uotE", LEDs show lower 4 on
- **`vote_enable` = 1**: ButtonControl modules are active — candidate buttons count
- **Transitions**: On `valid_vote_1–4` → `S_RV_READ` with `candidate_sel` set

### Vote Recording States (`S_RV_READ` through `S_RV_FLAG_WRITE`, states 5–10)
Six states that execute the read-modify-write pipeline:

| State | FEU Op | Purpose |
|---|---|---|
| `S_RV_READ` | READ addr=candidate | Load current vote count into AC |
| `S_RV_INC` | INC | AC = count + 1 |
| `S_RV_WRITE` | WRITE_AC addr=candidate | Write new count back |
| `S_RV_FLAG_READ` | READ addr=matched_NID | Load voter's NID entry into AC |
| `S_RV_FLAG_OR` | OR_ACC data=0x10000 | Set bit 16 (voted flag) |
| `S_RV_FLAG_WRITE` | WRITE_AC addr=matched_NID | Write marked entry back |

### CONFIRM (`S_CONFIRM = 11`)
- **Display**: "PASS", all LEDs ON
- **Duration**: `CONFIRM_CYCLES` (1 second)
- **Transitions**: → `S_IDLE`

### Admin States (`S_ADMIN_LOGIN` through `S_TIMER_START`, states 12–22)

| State | Purpose |
|---|---|
| `S_ADMIN_LOGIN` | READ `ADDR_ADMIN_PW` to get stored password |
| `S_ADMIN_RESULT` | Compare `saved_switches` vs `fe_ac[15:0]` using comparator |
| `S_RESULT_DISPLAY` | Wait for candidate button or BTNC |
| `S_RESULT_READ` | READ vote count for selected candidate |
| `S_RESULT_SHOW` | Latch `result_value ← fe_ac[15:0]`, display it |
| `S_ADMIN_RESET` | Loop: write 0 to vote count addresses 0–3 |
| `S_ADMIN_RESET_FLAGS` | Loop: read each NID entry |
| `S_ADMIN_RESET_FRD` | Check if NID is non-zero; if empty → done |
| `S_ADMIN_RESET_FWR` | Write back with bit 16 cleared |
| `S_TIMER_START` | Assert `timer_reset` + `timer_start` → `S_IDLE` |

### ERROR (`S_ERROR = 21`)
- **Display**: "Err ", LEDs = `0xF00F` pattern
- **Duration**: `ERROR_CYCLES` (2 seconds)
- **Transitions**: → `S_IDLE`

---

## Key Design Patterns

### 1. Generic Wait State with Return Register

Instead of creating separate wait states for each FEU operation, the CU uses a single `S_WAIT_FE` state plus a `return_state` register:

```verilog
S_RV_READ: begin
    return_state <= S_RV_INC;   // After FEU finishes, go here
    state        <= S_WAIT_FE;  // Wait for fe_done
end
```

This pattern is used **12 times** in the FSM, saving ~12 duplicate states.

### 2. Combinational FEU Command Generation

FEU control signals (`fe_start`, `fe_op`, `fe_addr`, etc.) are driven **combinationally** from the current state, not registered:

```verilog
always @(*) begin
    case (state)
        S_RV_READ: begin
            fe_start = 1'b1;
            fe_op    = FE_OP_READ;
            fe_addr  = {7'd0, candidate_sel};
        end
        ...
    endcase
end
```

This means the FEU sees the command in the **same cycle** the CU enters the state. By the next cycle, the CU moves to `S_WAIT_FE` and the FEU has latched the command.

### 3. Embedded Comparator for Admin Password

The CU instantiates a `comparator` module internally:

```verilog
comparator admin_cmp(
    .input_a(saved_switches),
    .input_b(fe_ac[15:0]),
    .match(admin_pw_match)
);
```

This keeps the password comparison logic self-contained — the result is available combinationally for the `S_ADMIN_RESULT` state decision.

---

## Connection Summary

```
  Switches ──────────►┐
  BTNC pulse ─────────┤
  valid_vote_1–4 ─────┤    controlUnit
  button1–4_raw ──────┤    ┌─────────────────────────┐
  voting_active ──────┤───►│ 23-state Moore FSM       │──► display_value
                      │    │                          │──► display_mode
  fe_done ◄───────────┤◄───│ FEU command generation   │──► led_out
  fe_match ◄──────────┤◄───│                          │──► vote_enable
  fe_match_addr ◄─────┤◄───│ Admin comparator         │──► timer_start
  fe_ac ◄─────────────┤◄───│                          │──► timer_reset
                      │    │                          │──► fe_start, fe_op, etc.
                      │    └─────────────────────────┘
                      │
                      │    The CU is the central coordinator:
                      │    • Reads inputs (buttons, switches, FEU status)
                      │    • Decides what to do (FSM transitions)
                      │    • Issues commands (FEU operations)
                      │    • Drives outputs (display, LEDs)
```
