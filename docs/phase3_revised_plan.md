# Phase 3 — Revised Plan (2026-04-10)

## Summary of Changes from Original Plan

| Original Plan | Revised Plan |
|---|---|
| 13-digit National ID | **4-digit NID** (16-bit BCD) |
| HMAC-SHA256 authentication | **Subtractor-based comparison** (NID match) |
| Ballot display state | **No ballot display** — direct candidate button voting |
| No time limit | **10-minute voting window** — hardware timer |
| No admin mode | **Admin login with password** to view results + reset timer |
| Simple BRAM read/write | **Fetch-Execute memory unit** with PC, MAR, MBR, IR |
| Vivado-inferred BRAM access | **Manual fetch-execute cycle** for all memory operations |
| 64-word BRAM | **512x32-bit BRAM**, pre-loaded from `nid_table.hex` file |
| 64 voters max | **256 voters** in NID table |

---

## Architecture Overview

```
                        ┌──────────────────────────────────────────────┐
                        │            votingMachine (Top)               │
                        │                                              │
  Buttons ──►buttonControl(x4)──► valid_vote pulses                   │
                        │              │                               │
  SW[15:0] ─────────────┤              ▼                               │
                        │     ┌─────────────────┐                      │
                        │     │  Control Unit    │ (Main FSM)          │
                        │     │  (8-state Moore) │                     │
                        │     └──────┬──────────┘                      │
                        │            │ drives                          │
                        │     ┌──────┴──────────────────────┐          │
                        │     │                             │          │
                        │     ▼                             ▼          │
                        │  ┌──────────────┐     ┌───────────────────┐  │
                        │  │  Fetch-Exec  │────►│   Memory Unit     │  │
                        │  │  Unit (FEU)  │◄────│  (BRAM 512x32)    │  │
                        │  │ PC,MAR,MBR,IR│     │ loaded from .hex  │  │
                        │  └──────┬───────┘     └───────────────────┘  │
                        │         │                                    │
                        │         ▼                                    │
                        │  ┌──────────────┐     ┌───────────────────┐  │
                        │  │     ALU      │────►│  Comparator       │  │
                        │  │ (ADD/SUB/INC)│     │  (NID/Password    │  │
                        │  └──────────────┘     │   match check)    │  │
                        │                       └───────────────────┘  │
                        │                                              │
                        │  ┌──────────────┐     ┌───────────────────┐  │
                        │  │  10-min Timer│     │  sevenSegDisplay   │  │
                        │  │ (admin can   │     └───────────────────┘  │
                        │  │  reset)      │                            │
                        │  └──────────────┘                            │
                        └──────────────────────────────────────────────┘
```

---

## Module Details

### 1. Voting Timer (NEW)

**Purpose**: Enforces a 10-minute voting window. After 10 minutes, no more votes are accepted. Admin can reset the timer to start a new election.

```
Parameters:
  TIMER_MAX = 60_000_000_000  (10 min at 100 MHz)
  Uses a 36-bit counter

Ports:
  input  clk, reset
  input  timer_start       // Asserted when admin starts the election
  input  timer_reset       // Admin can reset timer (after authentication)
  output reg voting_active  // HIGH during the 10-min window
  output reg [3:0] mins_remaining  // Countdown 10→0 for 7-seg display
```

**Behavior**:
- On `reset` or power-on: `voting_active = 0` (election not started)
- Admin starts election → `voting_active = 1`, counter begins counting up
- When counter reaches `TIMER_MAX`: `voting_active = 0` (voting closed)
- Admin can assert `timer_reset` (only after authentication) → counter resets to 0, `voting_active = 0`, ready for a new election
- The Control Unit FSM checks `voting_active` before allowing any vote
- `mins_remaining` counts down 10 → 0 for optional display on 7-seg

---

### 2. Fetch-Execute Unit (NEW — replaces current rotating write controller)

**Purpose**: Implements a manual fetch-execute cycle for all memory operations, mimicking a basic CPU's memory access pattern (Mano's basic computer model).

#### Registers

| Register | Width | Purpose |
|---|---|---|
| **PC** (Program Counter) | 9 bits | Points to next memory address to access (0–511) |
| **MAR** (Memory Address Register) | 9 bits | Holds the address currently being accessed in memory |
| **MBR** (Memory Buffer Register) | 32 bits | Holds data read from or to be written to memory |
| **IR** (Instruction Register) | 4 bits | Holds the current operation code |
| **AC** (Accumulator) | 32 bits | Holds intermediate results from ALU |

> Note: Registers are 9-bit wide for addressing because 512 words needs 9 address bits.

#### Fetch-Execute Cycle FSM

```
States:
  FE_IDLE    — Waiting for a memory operation request from Control Unit
  FE_FETCH_1 — t0: MAR <- PC (load address from PC into MAR)
  FE_FETCH_2 — t1: MBR <- M[MAR], PC <- PC + 1 (read memory, increment PC)
  FE_DECODE  — t2: IR <- MBR[31:28] (opcode), rest is data
  FE_EXEC    — t3: Execute based on IR (read/write/compare)
  FE_DONE    — Signal completion to Control Unit
```

#### Micro-Operations Detail

**Fetch Phase (reading data from memory):**
```
t0 (FE_FETCH_1):
    MAR <= PC;                    // Load PC value into MAR
    
t1 (FE_FETCH_2):
    MBR <= M[MAR];               // Read memory at MAR into MBR
    PC  <= PC + 1;               // Increment PC for next access
    // NOTE: BRAM has 1-cycle read latency, so data appears next cycle

t2 (FE_DECODE):
    IR  <= MBR[31:28];           // Extract operation code
    // Remaining bits are data
```

**Execute Phase (depends on operation requested by Control Unit):**

| IR Code | Operation | Micro-op |
|---|---|---|
| `4'b0001` | **LOAD** | AC <= M[MAR] — Read data from memory into accumulator |
| `4'b0010` | **STORE** | M[MAR] <= AC — Write accumulator value to memory |
| `4'b0011` | **INC** | AC <= AC + 1 — Increment accumulator |
| `4'b0100` | **COMPARE** | flags <= (AC == MBR) ? match : no_match |
| `4'b0101` | **SUB** | AC <= AC - MBR — Subtract for comparison |
| `4'b0000` | **NOP** | No operation |

#### How the Control Unit Uses the FEU

The Control Unit doesn't directly read/write memory. Instead, it:
1. Sets the PC to the desired base address
2. Tells the FEU what operation to perform
3. Triggers the FEU (`fe_start = 1`)
4. Waits for `fe_done` signal
5. Reads the result from AC or flags

**Example — Reading Candidate 1's vote count:**
```
Control Unit sets: PC = 0 (addr of cand1 votes)
Control Unit sets: fe_op = LOAD
Control Unit asserts: fe_start = 1

FEU executes:
  t0: MAR <= 0          (from PC)
  t1: MBR <= M[0]       (read vote count from BRAM)
      PC  <= 1           (auto-increment)
  t2: IR  <= LOAD
  t3: AC  <= MBR         (vote count now in accumulator)
  → fe_done = 1

Control Unit reads AC → displays on 7-seg/LEDs
```

**Example — NID Lookup (checking if voter already voted):**
```
Control Unit sets: PC = 0x010 (start of NID table)
Control Unit sets: fe_op = COMPARE
Control Unit loads: input_nid into comparison register

FEU iterates through NID table (up to 256 entries):
  For each entry at addr 0x010, 0x011, 0x012, ..., 0x10F:
    t0: MAR <= PC
    t1: MBR <= M[MAR], PC <= PC + 1
    t2: Compare MBR[15:0] with input_nid (using subtractor)
    t3: If (MBR[15:0] - input_nid == 0) → match_found = 1, stop
        If (MBR == 0) → end of table, no match, stop
        Else → loop back to t0 for next entry
  
  If match found, also check MBR[16] (voted flag):
    If MBR[16] == 1 → already voted, reject
    If MBR[16] == 0 → proceed to voting
```

---

### 3. Memory Map (Revised — 512x32-bit BRAM)

Expanding to 512 words to accommodate 256 NID entries, admin data, and vote counts.

| Address Range | Size | Content | Access Pattern |
|---|---|---|---|
| `0x000 – 0x003` | 4 words | **Candidate 1–4 vote counts** | Read/Write via FEU |
| `0x004` | 1 word | **Admin password** (4-digit BCD, 16-bit) | Read via FEU for comparison |
| `0x005` | 1 word | **Election status flags** (timer, active, etc.) | Read/Write via FEU |
| `0x006 – 0x00F` | 10 words | Reserved | — |
| `0x010 – 0x10F` | 256 words | **NID Table** (4-digit NIDs, one per word) | Sequential scan via FEU |
| `0x110 – 0x1FF` | 240 words | Reserved for future use | — |

**Total BRAM usage**: 512 × 32 = 16,384 bits = 16 Kbit (fits in 1 BRAM tile, uses ~45% of one 36 Kbit tile).

**NID Table Format** (each 32-bit word at addresses 0x010–0x10F):
```
Bits [15:0]  = 4-digit BCD NID (e.g., 1234 stored as 16'h1234)
Bit  [16]    = voted flag (0 = not yet voted, 1 = already voted)
Bits [31:17] = reserved (zeros)
```

#### How NIDs are Pre-Loaded: The `.hex` File

NIDs are stored in a **hex file** (`nid_table.hex`) in the project directory. The memory module loads it at synthesis time using Verilog's `$readmemh`:

```verilog
// In memoryUnit.v:
(* ram_style = "block" *) reg [31:0] mem [0:511];

initial begin
    $readmemh("nid_table.hex", mem);
end
```

**The hex file** (`nid_table.hex`) contains exactly 512 lines — one 8-character hex value per line, no comments, no addresses. Each line corresponds to one 32-bit memory word:

```
00000000        ← addr 0x000: Candidate 1 votes (starts at 0)
00000000        ← addr 0x001: Candidate 2 votes
00000000        ← addr 0x002: Candidate 3 votes
00000000        ← addr 0x003: Candidate 4 votes
00002580        ← addr 0x004: Admin password (BCD "2580")
00000000        ← addr 0x005: Election flags
00000000        ← addr 0x006: Reserved
...             ← (more reserved zeros)
00001234        ← addr 0x010: NID entry 1 (voter NID "1234", not voted)
00005678        ← addr 0x011: NID entry 2 (voter NID "5678", not voted)
00009012        ← addr 0x012: NID entry 3 (voter NID "9012", not voted)
...             ← (256 total NID entries)
00000000        ← addr 0x110: Reserved (padding)
...
00000000        ← addr 0x1FF: Last word
```

**To change the voter list for a new election:**
1. Edit `nid_table.hex` (add/remove/change NID values)
2. Re-run Vivado synthesis + generate bitstream
3. Re-program the FPGA

The file lives at: `FPGA_Voting_machine.srcs/sources_1/new/nid_table.hex`

---

### 4. NID Input via Switches (NEW — No Keypad Needed)

**Purpose**: Allow voter to enter a 4-digit NID using the Basys 3's 16 slide switches.

#### How It Works — Step by Step

The Basys 3 has **16 slide switches** (SW0–SW15). We divide them into 4 groups of 4 switches, where each group represents one BCD digit (0–9):

```
┌─────────────────────────────────────────────────────────────────┐
│                    BASYS 3 SWITCH LAYOUT                        │
│                                                                 │
│   SW15 SW14 SW13 SW12 │ SW11 SW10 SW9  SW8  │ SW7 SW6 SW5 SW4 │ SW3 SW2 SW1 SW0  │
│   ─────────────────── │ ─────────────────── │ ──────────────── │ ──────────────── │
│    Thousands digit    │  Hundreds digit     │   Tens digit     │   Ones digit     │
│    (digit 1)          │  (digit 2)          │   (digit 3)      │   (digit 4)      │
│                       │                     │                  │                  │
│   Value = 8+4+2+1     │  Value = 8+4+2+1    │  Value = 8+4+2+1 │  Value = 8+4+2+1 │
└─────────────────────────────────────────────────────────────────┘
```

**Example — Entering NID "2580":**

```
  Thousands (2):  SW15=0  SW14=0  SW13=1  SW12=0  → 0010 = 2
  Hundreds  (5):  SW11=0  SW10=1  SW9=0   SW8=1   → 0101 = 5
  Tens      (8):  SW7=1   SW6=0   SW5=0   SW4=0   → 1000 = 8
  Ones      (0):  SW3=0   SW2=0   SW1=0   SW0=0   → 0000 = 0
  
  Result: switches read as 16'h2580 → NID "2580"
```

**Example — Entering NID "0073":**

```
  Thousands (0):  SW15=0  SW14=0  SW13=0  SW12=0  → 0000 = 0
  Hundreds  (0):  SW11=0  SW10=0  SW9=0   SW8=0   → 0000 = 0
  Tens      (7):  SW7=0   SW6=1   SW5=1   SW4=1   → 0111 = 7
  Ones      (3):  SW3=0   SW2=0   SW1=1   SW0=1   → 0011 = 3
  
  Result: switches read as 16'h0073 → NID "0073"
```

**After setting the switches, the voter presses BTNC (center button) to submit.**

#### BCD Validation

Each 4-bit group must be 0–9 (valid BCD). Values A–F (10–15) are invalid. The module rejects submissions where any digit > 9:

```verilog
wire digit1_valid = (switches[15:12] <= 4'd9);
wire digit2_valid = (switches[11:8]  <= 4'd9);
wire digit3_valid = (switches[7:4]   <= 4'd9);
wire digit4_valid = (switches[3:0]   <= 4'd9);
wire all_valid = digit1_valid & digit2_valid & digit3_valid & digit4_valid;
```

#### 7-Segment Feedback During Input

While the voter sets switches, the 7-segment display shows the current switch value in real-time as 4 hex digits — so the voter can see what they're entering before pressing submit.

#### Module Ports

```
Ports:
  input  clk, reset
  input  [15:0] switches     // SW15..SW0 (directly from Basys 3 pins)
  input  submit              // BTNC press (active-high)
  output reg [15:0] nid_value   // Captured 4-digit BCD NID
  output reg nid_ready       // Single-cycle pulse when valid NID submitted
  output reg invalid_input   // Pulse if BCD digit > 9
```

#### Admin Password Entry — Same Mechanism

The admin uses the exact same switches to enter their password. The Control Unit determines whether the input is treated as a voter NID or admin password based on system state:
- If system is in IDLE and voting is active → treat as voter NID
- If system is in IDLE and voting has ended (or not started) → treat as admin password

---

### 5. Comparator Module (NEW — replaces HMAC-SHA256)

**Purpose**: Compare two 16-bit values using subtraction. If the difference is zero, the values match.

```
Ports:
  input  clk, reset
  input  [15:0] input_a     // Value from switches (voter NID or admin pass)
  input  [15:0] input_b     // Value from memory (stored NID or password)
  input  compare_start
  output reg match           // 1 if a == b (difference is zero)
  output reg compare_done
```

**Internal logic**:
```verilog
wire [16:0] diff = {1'b0, input_a} - {1'b0, input_b};
wire zero_flag = (diff == 17'd0);  // If difference is zero → match

always @(posedge clk) begin
    if (reset) begin
        match <= 0;
        compare_done <= 0;
    end else if (compare_start) begin
        match <= zero_flag;
        compare_done <= 1;
    end else begin
        compare_done <= 0;
    end
end
```

This replaces all cryptographic hashing with a simple hardware subtraction — straightforward and synthesizable. The 17-bit width catches the borrow bit for unsigned subtraction.

---

### 6. Control Unit FSM (Revised)

**Type**: Moore FSM  
**States**: 8 states

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│   IDLE ──────► VOTER_AUTH ──────► DOUBLE_VOTE_CHK            │
│    ▲               │                    │                    │
│    │          (fail)│              (already voted)            │
│    │               ▼                    │                    │
│    │             IDLE                   ▼                    │
│    │          (show err LED)          IDLE                   │
│    │                               (show err LED)            │
│    │           (pass + not voted)                             │
│    │               │                                         │
│    │               ▼                                         │
│    │          VOTE_ACTIVE ──────► RECORD_VOTE                │
│    │                                   │                     │
│    │                                   ▼                     │
│    └──────────────────────────── CONFIRM_DONE                │
│                                                              │
│   (Separate path — when voting ended or not started)         │
│   IDLE ──────► ADMIN_LOGIN ──────► RESULT_DISPLAY            │
│                    │                    │                     │
│              (fail)│                    │(button press)       │
│                    ▼                    ▼                     │
│                  IDLE              shows candidate count      │
│                                   via fetch-execute           │
│                                                              │
│   (From RESULT_DISPLAY, admin can also reset timer)          │
│   RESULT_DISPLAY ──► ADMIN_RESET ──► IDLE                    │
│                      (timer_reset=1, clears vote counts)     │
└──────────────────────────────────────────────────────────────┘
```

#### State Descriptions

| State | Entry Condition | What Happens | Outputs |
|---|---|---|---|
| **IDLE** | Power-on / reset / done | 7-seg shows current switch value (live preview). Wait for BTNC submit. | `voting_enable=0` |
| **VOTER_AUTH** | BTNC pressed + `voting_active=1` | FEU scans NID table (addr 0x010–0x10F) using fetch-execute cycle. Subtractor compares each stored NID[15:0] with input. | `fe_start=1`, scanning |
| **DOUBLE_VOTE_CHK** | NID found in table | Check matched entry's bit [16] (voted flag). If 1 → already voted → IDLE with error. If 0 → proceed. | `fe_op=LOAD` |
| **VOTE_ACTIVE** | NID valid + not yet voted | Enable candidate buttons. Voter presses one button (1-sec hold). 7-seg shows "uotE" or similar prompt. | `voting_enable=1`, buttons active |
| **RECORD_VOTE** | `valid_vote` pulse received | FEU: (1) LOAD count from addr 0–3, (2) INC via ALU, (3) STORE back. Also STORE voted flag (set bit 16) in NID entry. | `fe_op=LOAD,INC,STORE` |
| **CONFIRM_DONE** | Vote stored | All LEDs flash briefly (1 sec), then return to IDLE. | `led = 16'hFFFF` |
| **ADMIN_LOGIN** | BTNC pressed + `voting_active=0` | FEU loads admin password from addr 0x004. Subtractor compares with switch input. Match → RESULT_DISPLAY. Fail → IDLE. | `fe_op=LOAD,COMPARE` |
| **RESULT_DISPLAY** | Admin authenticated | Press BTNU/L/R/D to see each candidate's count. Each press triggers fetch-execute: `PC←addr → LOAD → display AC`. Admin can press BTNC to reset timer for new election. | `fe_op=LOAD`, display |

#### Admin Result Display Flow

After admin logs in:
1. 7-seg shows candidate 1's vote count by default
2. Admin presses **BTNU** → FEU fetches mem[0x000] → shows Candidate 1 count on 7-seg + LEDs
3. Admin presses **BTNL** → FEU fetches mem[0x001] → shows Candidate 2 count
4. Admin presses **BTNR** → FEU fetches mem[0x002] → shows Candidate 3 count
5. Admin presses **BTND** → FEU fetches mem[0x003] → shows Candidate 4 count
6. Admin presses **BTNC** → Resets timer + clears vote counts → back to IDLE for new election

Each display triggers a full fetch-execute cycle:
```
PC ← 0 (or 1, 2, 3)
FEU: t0: MAR ← PC
     t1: MBR ← M[MAR], PC ← PC + 1
     t2: AC ← MBR
     → Display AC value on 7-seg and LEDs
```

---

### 7. Revised I/O Pin Usage

| Signal | Pin(s) | Board Label | Function |
|---|---|---|---|
| `clock` | W5 | CLK | 100 MHz |
| `reset` | — | (combo or unused) | System hard reset (power cycle, or hold BTNC+BTNU together) |
| `button1` (BTNU) | T18 | BTNU | Candidate 1 vote / View Cand 1 results |
| `button2` (BTNL) | W19 | BTNL | Candidate 2 vote / View Cand 2 results |
| `button3` (BTNR) | T17 | BTNR | Candidate 3 vote / View Cand 3 results |
| `button4` (BTND) | U17 | BTND | Candidate 4 vote / View Cand 4 results |
| `btnc` (BTNC) | U18 | BTNC | Submit NID / Submit admin password / Reset timer |
| `SW[15:0]` | V17,V16,W16,W17,W15,V15,W14,W13,V2,T3,T2,R3,W2,U1,T1,R2 | SW0–SW15 | NID entry (BCD) / Admin password entry |
| `led[15:0]` | U16..L1 | LED0–LED15 | Status + vote count display (binary) |
| `seg[6:0]` | W7,W6,U8,V8,U5,V5,U7 | CA–CG | 7-seg cathodes (active-low) |
| `dp` | V7 | DP | Decimal point (active-low) |
| `an[3:0]` | W4,V4,U4,U2 | AN0–AN3 | 7-seg anodes (active-low) |

**How mode is determined** (no dedicated mode switch needed):
- The **Control Unit FSM state** determines what happens when BTNC is pressed:
  - If `voting_active = 1` and system is IDLE → BTNC submits as **voter NID**
  - If `voting_active = 0` and system is IDLE → BTNC submits as **admin password**
- This means all 16 switches are available for NID/password input (no switch wasted on mode)

---

## Complete Voting Flow (User Perspective)

### Setup (Before Election)

1. **Edit `nid_table.hex`** in the project directory:
   - Set admin password at line 5 (addr 0x004), e.g., `00002580` for password "2580"
   - Add voter NIDs starting at line 17 (addr 0x010), one per line, e.g., `00001234`
   - Fill unused NID slots with `00000000`
2. **Synthesize and program** the FPGA in Vivado (the hex file gets baked into the bitstream)
3. On the board: **Admin enters password on switches + presses BTNC** → system authenticates
4. Admin presses **BTNC again in RESULT_DISPLAY** → starts 10-minute timer → voting begins

### Voter Flow (During 10-minute Window)

1. **Voter sets their 4-digit NID on switches:**
   ```
   Example NID "3456":
     SW[15:12] = 0011  (3)
     SW[11:8]  = 0100  (4)
     SW[7:4]   = 0101  (5)
     SW[3:0]   = 0110  (6)
   ```
   The 7-segment display shows "3456" as live preview so the voter can verify.

2. **Voter presses BTNC** to submit.

3. **System authenticates** (fetch-execute cycle scans NID table):
   ```
   FEU: PC ← 0x010
   Loop:
     t0: MAR ← PC
     t1: MBR ← M[MAR], PC ← PC+1
     t2: Subtract MBR[15:0] from input_nid
     t3: If difference = 0 → MATCH! Check voted flag.
         If MBR = 0 → end of table, no match → REJECT
         Else → next entry (loop to t0)
   ```
   - **If NID not found**: LEDs show error pattern (e.g., alternating), return to IDLE after 2 sec
   - **If NID found but already voted**: Different error pattern, return to IDLE
   - **If NID valid and not voted**: Proceed to step 4

4. **Voter presses one candidate button** (hold for 1 second):
   - BTNU = Candidate 1
   - BTNL = Candidate 2
   - BTNR = Candidate 3
   - BTND = Candidate 4

5. **System records vote** (fetch-execute cycle):
   ```
   Step 1 — Increment vote count:
     FEU: PC ← candidate_addr (0–3)
     t0: MAR ← PC
     t1: MBR ← M[MAR] (current count)
     t2: AC ← MBR
     t3: AC ← AC + 1 (INC)
     t4: M[MAR] ← AC (STORE back)
   
   Step 2 — Mark voter as "already voted":
     FEU: PC ← matched_nid_addr
     t0: MAR ← PC
     t1: MBR ← M[MAR]
     t2: AC ← MBR | 0x00010000  (set bit 16)
     t3: M[MAR] ← AC (STORE back)
   ```

6. **All LEDs flash** for ~1 second as confirmation, then system returns to IDLE for next voter.

### After 10 Minutes

1. Timer expires → `voting_active = 0`
2. No more votes accepted — BTNC now triggers admin login path
3. 7-seg shows "donE" or similar indicator

### Admin Result Viewing (After Voting Ends)

1. **Admin sets password on switches** (e.g., "2580" → same switch pattern as NID entry)
2. **Admin presses BTNC** → system fetches password from mem[0x004] via FEU → subtractor compares
3. **If password matches** → enter RESULT_DISPLAY state:
   - Press **BTNU**: FEU fetches mem[0x000] → Candidate 1 count shown on 7-seg + LEDs
   - Press **BTNL**: FEU fetches mem[0x001] → Candidate 2 count
   - Press **BTNR**: FEU fetches mem[0x002] → Candidate 3 count
   - Press **BTND**: FEU fetches mem[0x003] → Candidate 4 count
   - Press **BTNC**: Reset timer + clear vote counts → ready for new election
4. **If password wrong** → LEDs show error, return to IDLE

---

## Module Hierarchy (Revised)

```
votingMachine.v              (Top module)
  +-- buttonControl.v        (x4 instances, 1-sec hold — EXISTING, keep as-is)
  +-- votingTimer.v           (NEW: 10-minute countdown, admin-resettable)
  +-- fetchExecuteUnit.v      (NEW: PC/MAR/MBR/IR/AC FSM for memory access)
  +-- memoryUnit.v            (MODIFIED: expand to 512x32, load from nid_table.hex)
  +-- ALU.v                   (MODIFIED: add SUB operation)
  +-- comparator.v            (NEW: subtractor-based equality check)
  +-- controlUnit.v           (NEW: 8-state Moore FSM)
  +-- sevenSegDisplay.v       (MODIFIED: support text patterns like "donE", live switch preview)
  +-- voteLogger.v            (REMOVED — replaced by FEU + memory read-modify-write)
```

---

## Implementation Order

1. **votingTimer.v** — Simple counter, easy to test independently
2. **Create `nid_table.hex`** — Generate 256 sample NIDs + admin password
3. **Expand memoryUnit.v** — 512x32, replace `initial` loop with `$readmemh("nid_table.hex", mem)`
4. **Modify ALU.v** — Add SUB operation (new opcode)
5. **comparator.v** — Thin wrapper around subtractor, checks zero flag
6. **fetchExecuteUnit.v** — Core new module: PC, MAR, MBR, IR, AC registers + 6-state FSM
7. **controlUnit.v** — Main 8-state FSM orchestrating everything
8. **Modify sevenSegDisplay.v** — Add text display capability + live switch preview
9. **Update votingMachine.v** — Rewire top module with new hierarchy, use all 16 switches
10. **Update constraints (.xdc)** — Map SW[15:0], LED[15:0], remap BTNC as submit
11. **Update testbench** — Comprehensive simulation covering NID auth, voting, admin, timer

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| 4-digit BCD NID (not binary) | Easier for voters to understand; maps naturally to 4 groups of 4 switches |
| 256 voters in NID table | 256 × 32 bits = 8 Kbit; Basys 3 has 1,800 Kbit BRAM — uses < 0.5% |
| 512x32 BRAM (9-bit address) | Fits all data (votes + admin + 256 NIDs + reserved) in 1 BRAM tile |
| `$readmemh` from `.hex` file | Standard Verilog approach; edit the text file, re-synthesize to change voter list |
| Subtractor instead of SHA-256 | Dramatically simpler; SHA-256 would consume most of the Artix-7's LUTs |
| No dedicated mode switch | FSM state + `voting_active` flag determines if input is NID or password — all 16 switches free for data |
| Sequential NID scan | 256 entries × ~3 cycles each = ~768 cycles (7.68 us) — imperceptible to humans |
| Admin-resettable timer | Allows running multiple elections without reprogramming the FPGA |
| Pre-loaded NID table via `.hex` | Avoids runtime enrollment complexity; just edit file and re-synthesize |
| FEU operates on request | Control Unit triggers FEU when needed, unlike current always-writing controller |
