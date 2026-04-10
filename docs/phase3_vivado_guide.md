# Phase 3 — Vivado Build & Test Guide

## Prerequisites

- Xilinx Vivado ML Edition installed
- Basys 3 board connected via USB (for programming)
- Project file: `FPGA_Voting_machine.xpr`

---

## Step 1: Open Project & Add New Files

1. Open Vivado → **File → Open Project** → select `FPGA_Voting_machine.xpr`
2. If Vivado prompts about changed files → click **Yes** to refresh

### Add New Design Sources

3. **File → Add Sources** → select **"Add or create design sources"** → Next
4. Click **"Add Files"**
5. Navigate to `FPGA_Voting_machine.srcs/sources_1/new/`
6. **IMPORTANT**: Change the file type filter (bottom-right dropdown) from `Verilog Files (*.v)` to `All Files (*.*)`
7. Select these 5 files (Ctrl+click to multi-select):
   - `votingTimer.v`
   - `comparator.v`
   - `fetchExecuteUnit.v`
   - `controlUnit.v`
   - `nid_table.hex`
8. Click **OK** → **Finish**

### Remove Old File

9. In the **Sources** panel (left side), expand **Design Sources**
10. Right-click `voteLogger.v` → **Remove File from Project** → confirm
    - (This module was replaced by the Fetch-Execute Unit + Memory)

### Verify Source Tree

After adding, your **Design Sources** panel should show:

```
Design Sources
├── votingMachine (votingMachine.v)        ← TOP MODULE
│   ├── buttonControl (buttonControl.v)     × 4 instances
│   ├── votingTimer (votingTimer.v)
│   ├── memoryUnit (memoryUnit.v)
│   ├── ALU (ALU.v)
│   ├── fetchExecuteUnit (fetchExecuteUnit.v)
│   │   └── comparator (comparator.v)       ← instantiated inside FEU
│   ├── controlUnit (controlUnit.v)
│   │   └── comparator (comparator.v)       ← 2nd instance for admin pw
│   └── sevenSegDisplay (sevenSegDisplay.v)
├── nid_table.hex                           ← memory init file
```

If `votingMachine` is not shown as the top module:
- Right-click `votingMachine` → **Set as Top**

---

## Step 2: Run Behavioral Simulation

This is the most important step — verify logic before touching hardware.

1. In the **Flow Navigator** (left panel), click **Run Simulation → Run Behavioral Simulation**
2. Vivado will compile all sources and open the waveform viewer

### Check the Tcl Console Output

Scroll through the **Tcl Console** (bottom panel) and look for the test output:

```
==============================================
  FPGA Voting Machine — Phase 3 Testbench
==============================================
[XXX] POR complete. CU state=0, voting_active=0

--- TEST 1: Admin login (pw=2580) ---
  PASS: Admin logged in → RESULT_DISPLAY

--- TEST 2: Admin starts election ---
  voting_active=1 (expected 1)
  PASS: Election started.

--- TEST 3: Voter NID=0037 → Candidate 1 ---
  NID verified. fe_match=1, addr=010
  Vote recorded. In CONFIRM.
  PASS: Back in IDLE. MEM[0]=1 (expected 1)

--- TEST 4: Voter NID=0097 → Candidate 2 ---
  PASS: MEM[1]=1 (expected 1)

--- TEST 5: Voter NID=0106 → Candidate 1 ---
  PASS: MEM[0]=2 (expected 2)

--- TEST 6: Duplicate vote (NID=0037) ---
  PASS: Duplicate rejected → ERROR state.

--- TEST 7: Invalid NID (9999) ---
  PASS: Invalid NID rejected → ERROR state.

--- TEST 8: Admin views results ---
  Candidate 1 count: ACC=2 (expected 2)
  Candidate 2 count: ACC=1 (expected 1)

--- TEST 9: Wrong admin password (1111) ---
  PASS: Wrong password rejected → ERROR state.

  FINAL MEMORY STATE:
    MEM[0] Cand1 votes: 2 (expected 2)
    MEM[1] Cand2 votes: 1 (expected 1)
    MEM[2] Cand3 votes: 0 (expected 0)
    MEM[3] Cand4 votes: 0 (expected 0)
    ...
  ALL TESTS COMPLETE
```

### What to Look For

| Check | Expected | If Wrong |
|---|---|---|
| All tests say PASS | Yes | Read the specific FAIL message — it tells you which state the FSM got stuck in |
| No TIMEOUT messages | No timeouts | A state machine is stuck — check the waveform at the timeout time |
| MEM[0]=2, MEM[1]=1 | Correct vote counts | Vote recording path (RV_READ→INC→WRITE) has a bug |
| MEM[16] bit 16 = 1 | Voted flag set | Flag OR/WRITE path broken |
| No `*** WATCHDOG ***` | Simulation completes | Infinite loop somewhere — check admin reset or NID scan |

### Examine the Waveform

Key signals to add to the waveform viewer (right-click → Add to Wave Window):

| Signal Path | What It Shows |
|---|---|
| `DUT/CU/state` | Control Unit FSM state (0=IDLE, 4=VOTE_ACTIVE, etc.) |
| `DUT/FEU/state` | Fetch-Execute Unit state (0=IDLE, 1=FETCH1, etc.) |
| `DUT/FEU/pc` | Program Counter — watch it increment during fetch cycles |
| `DUT/FEU/mar` | Memory Address Register |
| `DUT/FEU/mbr` | Memory Buffer Register — data read from BRAM |
| `DUT/alu_acc` | ALU accumulator — shows vote counts, comparison results |
| `DUT/voting_active` | Timer status |
| `DUT/fe_done` | FEU completion signal |
| `DUT/fe_match` | NID scan match result |
| `DUT/MEM/addr` | Memory address bus |
| `DUT/MEM/wr_en` | Memory write enable |
| `DUT/MEM/data_in` | Data being written to memory |
| `DUT/MEM/data_out` | Data read from memory |
| `DUT/led` | LED output pattern |
| `DUT/switches` | Switch input |

**Tip**: Set the radix of `state` signals to **Unsigned Decimal** so you can match them to the state numbers in the code. Set `switches`, `mbr`, `alu_acc` to **Hexadecimal**.

---

## Step 3: Run Synthesis

1. In the Flow Navigator, click **Run Synthesis**
2. Wait for completion (typically 1-3 minutes)

### Check Synthesis Results

3. When done, click **Open Synthesized Design** (or view the log)

### Expected Warnings (Safe to Ignore)

| Warning | Reason |
|---|---|
| `[Synth 8-3331] design memoryUnit has port reset driven by constant 0` | memoryUnit.v declares `reset` but doesn't use it internally — BRAM is initialized from hex file |
| `[Synth 8-3295] tying undriven pin ... to constant 0` | Unused debug outputs (`debug_pc`, `debug_mar`, etc.) |
| `[Synth 8-3917] design has unconnected port` | `mins_remaining`, `alu_overflow`, `alu_zero_flag` — connected but unused downstream |

### Warnings That Indicate Real Problems

| Warning | What's Wrong |
|---|---|
| `[Synth 8-327] inferring latch` | A combinational `always @(*)` block doesn't assign all outputs in all branches — FIX THIS |
| `[Synth 8-3352] multi-driven net` | Two modules driving the same wire — wiring bug in top module |
| `[Synth 8-87] port ... is not connected` | A required port was left unconnected — check votingMachine.v |
| `[DRC NSTD-1] Unspecified I/O standard` | Missing pin constraint in .xdc file |

### Resource Usage

Expected approximate utilization on XC7A35T:

| Resource | Used | Available | % |
|---|---|---|---|
| LUTs | ~400-600 | 20,800 | ~2-3% |
| Flip-Flops | ~200-400 | 41,600 | ~1% |
| BRAM | 1 tile | 50 | 2% |
| IO | 44 | 106 | 42% |

If LUT usage is over 5,000 or BRAM is more than 2, something is wrong.

---

## Step 4: Run Implementation

1. Click **Run Implementation** in the Flow Navigator
2. Wait for completion

### Check Timing

3. Open **Implementation → Open Implemented Design → Timing Summary**
4. Look for **Worst Negative Slack (WNS)**: must be **positive** (e.g., `WNS = 3.2 ns`)
   - Positive = timing met, design runs at 100 MHz
   - Negative = timing violation — design may malfunction on hardware
5. If timing fails, the most likely cause is a long combinational path in the comparator or FEU. Report the failing path.

---

## Step 5: Generate Bitstream

1. Click **Generate Bitstream** in the Flow Navigator
2. Wait for completion (2-5 minutes)
3. The `.bit` file will be in: `FPGA_Voting_machine.runs/impl_1/votingMachine.bit`

---

## Step 6: Program the FPGA

1. Connect Basys 3 board via USB
2. Click **Open Hardware Manager** → **Open Target → Auto Connect**
3. Click **Program Device** → select the `.bit` file → **Program**
4. The board is now running the voting machine

---

## Step 7: Test on Hardware

### Test A: Admin Login & Start Election

| Step | Action | Expected Result |
|---|---|---|
| 1 | Board powers on after programming | 7-seg shows `0000`, LED15 OFF (voting not active) |
| 2 | Set switches to admin password: SW[15:12]=0010, SW[11:8]=0101, SW[7:4]=1000, SW[3:0]=0000 (= "2580") | 7-seg shows `2580` (live preview) |
| 3 | Press BTNC (center button) | LEDs show pattern, then 7-seg shows result display |
| 4 | Press BTNC again in result display | Election starts. LED15 turns ON (voting active). System returns to IDLE showing `0000` |

### Test B: Cast a Vote

| Step | Action | Expected Result |
|---|---|---|
| 1 | Set switches to a valid NID from `nid_table.hex` (e.g., NID "0037": SW[15:12]=0000, SW[11:8]=0000, SW[7:4]=0011, SW[3:0]=0111) | 7-seg shows `0037` |
| 2 | Press BTNC | LEDs show alternating pattern (scanning NID table) |
| 3 | After ~1 microsecond | 7-seg shows "uotE" (vote prompt), lower 4 LEDs on |
| 4 | Hold BTNU for 1 second (Candidate 1) | All LEDs flash ON = vote confirmed |
| 5 | After 1 second | Returns to IDLE, 7-seg shows switch value again |

### Test C: Duplicate Vote Rejection

| Step | Action | Expected Result |
|---|---|---|
| 1 | Set switches to the same NID used in Test B (e.g., "0037") | 7-seg shows `0037` |
| 2 | Press BTNC | 7-seg shows "Err", LEDs show error pattern |
| 3 | After 2 seconds | Returns to IDLE automatically |

### Test D: Invalid NID Rejection

| Step | Action | Expected Result |
|---|---|---|
| 1 | Set switches to a NID NOT in the table (e.g., "9999") | 7-seg shows `9999` |
| 2 | Press BTNC | 7-seg shows "Err", LEDs show error pattern |

### Test E: View Results (After 10 Minutes)

| Step | Action | Expected Result |
|---|---|---|
| 1 | Wait for 10-minute timer to expire | LED15 turns OFF (voting ended) |
| 2 | Set switches to "2580" (admin password) | 7-seg shows `2580` |
| 3 | Press BTNC | Admin logged in, enters result display |
| 4 | Press BTNU | 7-seg + LEDs show Candidate 1 vote count |
| 5 | Press BTNL | 7-seg + LEDs show Candidate 2 vote count |
| 6 | Press BTNR | 7-seg + LEDs show Candidate 3 vote count |
| 7 | Press BTND | 7-seg + LEDs show Candidate 4 vote count |
| 8 | Press BTNC | Resets all counts, clears voted flags, starts new 10-min election |

### Switch Layout Reference

```
Physical switch positions on Basys 3 (left to right):

  SW15 SW14 SW13 SW12 | SW11 SW10 SW9 SW8 | SW7 SW6 SW5 SW4 | SW3 SW2 SW1 SW0
  ──────────────────── | ────────────────── | ──────────────── | ────────────────
   Thousands (digit 1) | Hundreds (digit 2) | Tens (digit 3)   | Ones (digit 4)
   8    4    2    1    | 8    4    2   1    | 8   4   2   1   | 8   4   2   1

Examples:
  NID "2580" → 0010 | 0101 | 1000 | 0000
  NID "1234" → 0001 | 0010 | 0011 | 0100
  NID "0037" → 0000 | 0000 | 0011 | 0111
  NID "9012" → 1001 | 0000 | 0001 | 0010
```

Each group of 4 switches encodes one BCD digit (0-9). Values above 9 (like 1010=A) are invalid and will be rejected.

---

## Troubleshooting

### Simulation Issues

| Problem | Cause | Fix |
|---|---|---|
| `$readmemh: Cannot open file "nid_table.hex"` | Vivado can't find the hex file | Make sure `nid_table.hex` is added as a design source. Also try setting the simulation working directory: right-click Simulation Sources → Properties → set working directory to where the hex file is |
| `TIMEOUT waiting for state X` | FSM is stuck | Add the CU and FEU `state` signals to the waveform. Check what state it's stuck in and trace the transition conditions |
| Wrong vote counts | FEU READ/INC/WRITE sequence has a timing issue | Check the waveform around vote recording — verify MBR gets the correct value before INC |

### Synthesis Issues

| Problem | Cause | Fix |
|---|---|---|
| `inferring latch for ...` | Missing `default` in `case` or incomplete `if/else` | Find the signal name in the warning and add the missing branch |
| `port X not found in module Y` | Port name mismatch | Compare the instantiation in `votingMachine.v` with the module declaration |
| Very high LUT usage (>2000) | Combinational loop or unintended logic | Check for circular assignments in the combinational `always @(*)` blocks |

### Hardware Issues

| Problem | Cause | Fix |
|---|---|---|
| 7-seg shows garbage | Display refresh issue or wrong segment encoding | Check if `seg` and `an` pins are correctly mapped in the `.xdc` file |
| Buttons don't respond | Debounce issue or wrong pin mapping | Verify button pin assignments match the physical board labels |
| BTNC doesn't work | Debounce counter too high for testing | The debouncer requires ~20ms of stable press — press firmly |
| Voting doesn't start | Timer was never started | Must do admin login → BTNC in result display first |
| All LEDs stay off | POR (power-on reset) stuck | Check if `por_counter` reaches `4'hF` — should happen in 15 clock cycles |

---

## Quick Reference: System States

| State # | Name | 7-Seg Shows | LEDs Show |
|---|---|---|---|
| 0 | IDLE | Switch value (live) | LED15 = voting_active |
| 1 | VOTER_AUTH | NID value | Alternating (scanning) |
| 4 | VOTE_ACTIVE | "uotE" | Lower 4 on |
| 11 | CONFIRM | "PASS" | All 16 ON |
| 14 | RESULT_DISPLAY | Vote count | Vote count (binary) |
| 21 | ERROR | "Err" | Error pattern |

---

## Sample Valid NIDs for Testing

First 10 NIDs from `nid_table.hex` (enter on switches, press BTNC):

| NID | Switch Pattern (SW15→SW0) |
|---|---|
| 0037 | 0000 0000 0011 0111 |
| 0097 | 0000 0000 1001 0111 |
| 0106 | 0000 0001 0000 0110 |
| 0112 | 0000 0001 0001 0010 |
| 0133 | 0000 0001 0011 0011 |
| 0184 | 0000 0001 1000 0100 |
| 0260 | 0000 0010 0110 0000 |
| 0341 | 0000 0011 0100 0001 |
| 0344 | 0000 0011 0100 0100 |
| 0450 | 0000 0100 0101 0000 |

Admin password: **2580** → `0010 0101 1000 0000`
