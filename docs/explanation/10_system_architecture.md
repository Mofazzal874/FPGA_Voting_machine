# 10: System Architecture — How Everything Connects

---

## Reading Order

This is the recommended reading order for all documentation:

| # | Document | Module | Why Read It |
|---|---|---|---|
| 01 | `01_buttonControl.md` | buttonControl | Simple building block — understand hold-to-vote input |
| 02 | `02_votingTimer.md` | votingTimer | Simple — timer that gates the voting window |
| 03 | `03_comparator.md` | comparator | Simple combinational block used by FEU and CU |
| 04 | `04_ALU.md` | ALU | Core compute unit — 6 operations, accumulator |
| 05 | `05_memoryUnit.md` | memoryUnit | Storage — BRAM, memory map, NID table format |
| 06 | `06_sevenSegDisplay.md` | sevenSegDisplay | Output — display driver, hex & text modes |
| 07 | `07_fetchExecuteUnit.md` | fetchExecuteUnit | **Key** — fetch-execute cycle, PC/MAR/MBR |
| 08 | `08_controlUnit.md` | controlUnit | **Key** — 23-state FSM, the "brain" |
| 09 | `09_votingMachine_top.md` | votingMachine | Top module — POR, debounce, all wiring |
| **10** | **This document** | — | **How it all fits together** |

Read 01–06 first (independent building blocks), then 07–08 (the core pipeline), then 09 (integration), then this document for the full picture.

---

## Complete Module Hierarchy

```
votingMachine (Top Module — 09_votingMachine_top.md)
│
├── [POR Generator]           inline — 15-cycle power-on reset
├── [BTNC Debounce]           inline — 20ms debounce + edge detect
│
├── buttonControl bc1         01_buttonControl.md — Candidate 1 (BTNU)
├── buttonControl bc2         01_buttonControl.md — Candidate 2 (BTNL)
├── buttonControl bc3         01_buttonControl.md — Candidate 3 (BTNR)
├── buttonControl bc4         01_buttonControl.md — Candidate 4 (BTND)
│
├── votingTimer TIMER         02_votingTimer.md  — 10-min countdown
│
├── memoryUnit MEM            05_memoryUnit.md   — 512×32 BRAM
│
├── ALU ALU_INST              04_ALU.md          — 32-bit accumulator
│
├── fetchExecuteUnit FEU      07_fetchExecuteUnit.md — fetch-execute engine
│   └── comparator scan_cmp   03_comparator.md   — NID match
│
├── controlUnit CU            08_controlUnit.md  — 23-state FSM
│   └── comparator admin_cmp  03_comparator.md   — password match
│
└── sevenSegDisplay SSD       06_sevenSegDisplay.md — display driver
```

---

## The Three Layers

The system has a clear three-layer architecture:

```
┌─────────────────────────────────────────────────┐
│            LAYER 3: USER INTERFACE              │
│  buttonControl (×4)  │  sevenSegDisplay  │ LEDs │
│  votingTimer         │                   │      │
└─────────┬────────────┴──────▲────────────┴──▲───┘
          │                   │               │
          │  valid_vote_1–4   │ display_value │ led_out
          │  voting_active    │ display_mode  │
          ▼                   │               │
┌─────────────────────────────┴───────────────┴───┐
│            LAYER 2: CONTROL                     │
│                  controlUnit                     │
│  (23-state FSM — decides WHAT to do)            │
└─────────┬───────────────────────────────────────┘
          │  fe_start, fe_op, fe_addr, etc.
          │  fe_done, fe_match, fe_ac
          ▼
┌─────────────────────────────────────────────────┐
│            LAYER 1: DATAPATH                    │
│  fetchExecuteUnit  ←→  memoryUnit  ←→  ALU     │
│  (PC, MAR, MBR)       (512×32 BRAM)   (32-bit  │
│  comparator            nid_table.hex    accumulator)
│                                                  │
│  (Executes HOW to do it — fetch-execute cycles) │
└─────────────────────────────────────────────────┘
```

**Layer 1 (Datapath)**: The FEU, Memory, and ALU form the compute pipeline. The FEU orchestrates multi-cycle fetch-execute operations. It's the only module that directly talks to Memory and ALU.

**Layer 2 (Control)**: The Control Unit FSM decides *what* operation to perform based on inputs and current state. It issues high-level commands to the FEU (READ, WRITE, SCAN, INC, etc.) and never touches memory or ALU directly.

**Layer 3 (User Interface)**: Button controllers, timer, display, and LEDs handle physical I/O. They communicate with the Control Unit through simple signals.

---

## Complete Data Flow: A Vote From Start to Finish

Here is the **exact sequence of events** when voter NID=0037 votes for Candidate 1:

### Phase 1: Voter Enters NID (Human Time)

1. Voter sets switches to `0x0037`
2. Display shows `0037` (live hex preview in `S_IDLE`)
3. Voter presses BTNC

### Phase 2: Authentication (~10 clock cycles)

```
Cycle 1:  BTNC debounce → btnc_pulse fires
          CU: S_IDLE → saved_switches = 0x0037
          CU: voting_active is TRUE → S_VOTER_AUTH

Cycle 2:  CU outputs: fe_start=1, fe_op=SCAN, addr=0x010, target=0x0037, end=0x10F
          CU: → S_WAIT_FE (return_state = S_AUTH_RESULT)

Cycle 3:  FEU: latches SCAN, PC=0x010
          FEU: → S_SCAN_ADDR, mem_addr = 0x010

Cycle 4:  FEU: MAR = 0x010, → S_SCAN_READ

Cycle 5:  FEU: MBR = mem[0x010] = 0x00000037, PC = 0x011
          FEU: → S_SCAN_CMP

Cycle 6:  FEU: comparator: MBR[15:0]=0x0037 vs target=0x0037 → MATCH!
          FEU: fe_match=1, fe_match_addr=0x010
          FEU: → S_SCAN_MATCH

Cycle 7:  FEU: ALU LOAD: AC ← 0x00000037 (the full NID entry)
          FEU: → S_DONE

Cycle 8:  FEU: fe_done=1 → CU leaves S_WAIT_FE

Cycle 9:  CU: S_AUTH_RESULT — fe_match=1, fe_ac[16]=0 (not voted)
          CU: saved_match_addr = 0x010 → S_VOTE_ACTIVE
```

### Phase 3: Voting (~1 second human hold + 4 cycles)

```
CU in S_VOTE_ACTIVE: vote_enable=1, display shows "uotE"
Voter holds BTNU for 1 second...
bc1.counter hits HOLD_THRESHOLD → valid_vote_1 pulse!

CU: candidate_sel = 0 → S_RV_READ
```

### Phase 4: Vote Recording (~24 clock cycles)

```
── Step 1: Read current vote count ──
CU: fe_start=1, fe_op=READ, addr=0x000 (Candidate 1)
FEU: FETCH1 → FETCH2 → EXECUTE(ALU LOAD) → DONE
Result: AC = mem[0x000] = 0 (no votes yet)

── Step 2: Increment ──
CU: fe_start=1, fe_op=INC
FEU: skip fetch → EXECUTE(ALU INC) → DONE
Result: AC = 1

── Step 3: Write back ──
CU: fe_start=1, fe_op=WRITE_AC, addr=0x000
FEU: FETCH1 → FETCH2 → EXECUTE(mem write) → DONE
Result: mem[0x000] = 1

── Step 4: Read NID entry ──
CU: fe_start=1, fe_op=READ, addr=0x010 (matched NID)
FEU: fetch cycle → AC = 0x00000037

── Step 5: Set voted flag ──
CU: fe_start=1, fe_op=OR_ACC, data=0x00010000
FEU: skip fetch → EXECUTE(ALU OR) → DONE
Result: AC = 0x00010037 (bit 16 set)

── Step 6: Write back marked NID ──
CU: fe_start=1, fe_op=WRITE_AC, addr=0x010
FEU: fetch cycle → mem[0x010] = 0x00010037
```

### Phase 5: Confirmation (1 second)

```
CU: S_CONFIRM — display shows "PASS", all 16 LEDs on
After CONFIRM_CYCLES: → S_IDLE
```

### Total: ~24 clock cycles of computation (240 ns) + 1 second button hold + 1 second confirmation

---

## How the Admin Starts a New Election

```
1. Election timer expires → voting_active = 0
2. Admin sets switches to password (e.g., 0x2580)
3. Admin presses BTNC

4. CU: S_IDLE → !voting_active → S_ADMIN_LOGIN
5. FEU reads mem[0x004] (admin password) → AC = 0x00002580
6. CU: S_ADMIN_RESULT → comparator matches → S_RESULT_DISPLAY

7. Admin presses candidate buttons to view counts
8. Admin presses BTNC → S_ADMIN_RESET

9. CU: loops through addresses 0–3, writing 0 (clear vote counts)
10. CU: loops through NID entries 0x010–0x10F:
    - Reads each entry
    - If non-zero NID: writes back with bit 16 cleared (reset voted flag)
    - If zero (empty): stops scanning

11. CU: S_TIMER_START → asserts timer_reset + timer_start
12. votingTimer starts 10-min countdown
13. CU: → S_IDLE, voting_active = 1 — new election has begun!
```

---

## Bus Architecture

```
                                    ┌──────────┐
                                    │  Memory  │
                                    │  512×32  │
                                    │  BRAM    │
                                    └────┬─────┘
                                         │ addr[8:0], wr_en,
                                         │ data_in[31:0], data_out[31:0]
                                         │
                                    ┌────┴─────┐
   ┌──────────┐   fe_start,op,addr  │   FEU    │   alu_op[2:0],operand[31:0]   ┌─────┐
   │ Control  │◄════════════════════│  (bus    │═══════════════════════════════►│ ALU │
   │  Unit    │ fe_done,match,      │  master) │   alu_acc[31:0]               │     │
   │  (FSM)   │ fe_ac               │          │◄══════════════════════════════│     │
   └──────────┘                     └──────────┘                               └─────┘

   ═══ = data flows through FEU (FEU is the sole bus master)
```

The FEU acts as a **bus master** — it is the only module that drives the memory address and ALU operation buses. The Control Unit commands the FEU, which translates those commands into the multi-cycle fetch-execute protocol required by synchronous BRAM and the clocked ALU.

---

## Testbench Coverage

The testbench (`votingMachine_tb.v`) covers these scenarios:

| Test | What It Verifies |
|---|---|
| Test 1: Admin login | Correct password → `S_RESULT_DISPLAY` |
| Test 2: Start election | BTNC in result display → timer starts |
| Test 3: Vote NID=0037 → Cand1 | Full auth + vote + confirm cycle |
| Test 4: Vote NID=0097 → Cand2 | Different voter, different candidate |
| Test 5: Vote NID=0106 → Cand1 | Second vote for same candidate |
| Test 6: Duplicate NID=0037 | Already-voted flag detection → ERROR |
| Test 7: Invalid NID=9999 | NID not in table → ERROR |
| Test 8: Admin views results | Read vote counts per candidate |
| Test 9: Wrong admin password | Password mismatch → ERROR |
