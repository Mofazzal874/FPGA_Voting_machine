# Future Modules — Implementation Reference

Modules from the project report (Chapters 5–6) that are **not yet implemented**. Use these specs when ready to add them.

---

## 1. Control Unit FSM (Chapter 5)

**Type**: Moore finite state machine  
**Purpose**: Orchestrates the entire voting lifecycle

### States

| State | Entry Condition | Active Outputs |
|---|---|---|
| `IDLE` | Power-on / reset | `display_idle` |
| `CREDENTIAL_INPUT` | Voter detected | `keypad_enable` |
| `AUTHENTICATE` | PIN submitted | `auth_start` |
| `DOUBLE_VOTE_CHECK` | `auth_ok = 1` | `mem_rd`, `hash_compare` |
| `BALLOT_DISPLAY` | No prior vote found | `display_ballot` |
| `RECORD_VOTE` | Candidate selected | `alu_inc`, `mem_wr` |
| `CONFIRM_RESET` | Vote committed | `display_confirm`, `rst_delay` |

### FSM Diagram

```
IDLE → CREDENTIAL_INPUT → AUTHENTICATE → DOUBLE_VOTE_CHECK → BALLOT_DISPLAY → RECORD_VOTE → CONFIRM_RESET → IDLE
                                ↓ (fail)
                              IDLE
                                           ↓ (already voted)
                                         IDLE
```

### Implementation Notes
- Replace the current simple memory write controller and ALU op controller in `votingMachine.v` with this FSM
- The FSM drives `alu_op`, `mem_addr`, `mem_wr`, and display control signals
- Currently the `voteLogger` handles counting — the FSM+ALU+Memory should take over that role

---

## 2. Authentication Module (Chapter 6.2)

**Purpose**: Verify voter identity using PIN-based challenge–response

### Protocol
1. Voter enters 13-digit National ID + 8-digit PIN via keypad
2. Compute `H_auth = HMAC-SHA256(voter_id, system_key)`
3. Compare against pre-loaded voter registry
4. If match → assert `auth_ok`; else increment failure counter
5. After 3 consecutive failures → lock terminal for 30 seconds

### Ports
```verilog
module auth_module(
    input clk,
    input reset,
    input [63:0] voter_id,
    input [31:0] voter_pin,
    output reg auth_ok,
    output reg [255:0] id_hash
);
```

### Dependencies
- SHA-256 / HMAC-SHA256 hardware engine
- Voter registry (pre-loaded in BRAM or external memory)
- System key (stored in OTP fuses — can simulate with constants for demo)

---

## 3. Secure Voter ID Storage (Chapter 6.3)

**Purpose**: Prevent double-voting while preserving anonymity

### Mechanism
- On successful vote: compute `R = SHA-256(voter_id || election_salt)`
- Store 256-bit hash `R` in voter registry
- On next auth: compute same hash, search registry — if found, deny ballot

### Write Integrity
- Each write: `T = HMAC-SHA256(R, system_key)`
- On read: recompute `T` and verify — mismatch → halt terminal

### Ports
```verilog
module voter_id_storage(
    input clk,
    input reset,
    input [255:0] id_hash,
    input store_hash,
    input check_hash,
    output reg hash_found,
    output reg integrity_ok
);
```

### Notes
- Salt stored in OTP fuses (simulate with hard-coded 128-bit constant)
- For demo: can use a simplified hash (e.g., XOR-based) instead of full SHA-256
- Binary search on sorted hash table for fast lookup

---

## 4. Keypad Input Module

**Purpose**: Interface a 4×4 matrix keypad for entering voter ID and PIN

### Ports
```verilog
module keypad_scanner(
    input clk,
    input reset,
    input [3:0] col_in,      // Column inputs from keypad
    output reg [3:0] row_out, // Row drive outputs
    output reg [3:0] key_value, // Decoded key (0-F)
    output reg key_pressed   // Key press flag
);
```

### Notes
- Requires GPIO pins for row/column connections
- Needs debouncing (~20ms)
- Add to constraints file when implementing
