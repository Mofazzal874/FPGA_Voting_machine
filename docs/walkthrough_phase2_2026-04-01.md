# FPGA Voting Machine — Phase 2 Walkthrough (2026-04-01)

## Summary

Added **3 new hardware modules** (7-Segment Display Driver, ALU, Memory Unit) and integrated them into the top module. Updated constraints and testbench.

## New Modules

| File | Module | Report Chapter |
|---|---|---|
| [sevenSegDisplay.v](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/sources_1/new/sevenSegDisplay.v) | 4-digit multiplexed 7-seg driver | Ch. 2 |
| [ALU.v](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/sources_1/new/ALU.v) | INC/SUM/COMPARE/NOP with overflow | Ch. 4 |
| [memoryUnit.v](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/sources_1/new/memoryUnit.v) | BRAM 64×32-bit storage | Ch. 3 |

## Modified Files

| File | Changes |
|---|---|
| [votingMachine.v](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/sources_1/new/votingMachine.v) | Added `seg`, `dp`, `an` ports; instantiated all new modules; added memory write controller and ALU operation control |
| [Basys3_constraints.xdc](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/constrs_1/new/Basys3_constraints.xdc) | Added 7-seg pins: `seg[6:0]`, `dp`, `an[3:0]` |
| [votingMachine_tb.v](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/sim_1/new/votingMachine_tb.v) | 7 test cases including memory and display verification |
| [FPGA_Voting_machine.xpr](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.xpr) | Added 3 new source file references |

## Architecture

```
Button Presses (BTNU/L/R/D) → buttonControl ×4 → valid_vote pulses → voteLogger → vote counts
                                                                                       ↓
                                                                          ┌──────────────┼──────────────┐
                                                                          ↓              ↓              ↓
                                                                   sevenSegDisplay   memoryUnit     LED display
                                                                   (4 hex digits)    (BRAM shadow)  (binary mode)
                                                                          
                                                              ALU (connected, driven by valid_vote events)
```

## How to Test

### Step 1: Open in Vivado
1. Open `FPGA_Voting_machine.xpr` in Vivado
2. If Vivado prompts about changed files → click "Yes" to refresh
3. Verify all 6 source files appear under "Design Sources"

### Step 2: Run Simulation
1. Click **Run Simulation → Run Behavioral Simulation**
2. Check the **Tcl Console** output — you should see:
   - `Cand1 votes: 3`, `Cand2 votes: 2`, `Cand3 votes: 1`, `Cand4 votes: 4`
   - `MEM[0]: 3`, `MEM[1]: 2`, `MEM[2]: 1`, `MEM[3]: 4`
   - `ALU overflow: 0`
   - After reset: all votes = 0
3. In the waveform viewer, verify `seg`, `an`, `dp` signals are toggling

### Step 3: Run Synthesis
1. Click **Run Synthesis** → should complete with **0 errors**
2. Check warnings — some about unconnected pins are normal

### Step 4: Run Implementation + Generate Bitstream
1. Click **Run Implementation** → should complete successfully
2. Click **Generate Bitstream**

### Step 5: Program the FPGA Board
1. Connect Basys 3 via USB
2. **Open Hardware Manager → Auto Connect → Program Device**
3. Select the `.bit` file from `impl_1` folder

### Step 6: Test on Board

| Test | How | Expected Result |
|---|---|---|
| **Reset** | Press BTNC | All 7-seg digits show `0`, LEDs off |
| **Vote for Cand 1** | Hold BTNU for 1 second | Leftmost 7-seg digit changes from `0` → `1` |
| **Vote again for Cand 1** | Hold BTNU for 1 second | Leftmost digit: `1` → `2` |
| **Vote for Cand 2** | Hold BTNL for 1 second | 2nd digit: `0` → `1` |
| **Vote for Cand 3** | Hold BTNR for 1 second | 3rd digit: `0` → `1` |
| **Vote for Cand 4** | Hold BTND for 1 second | Rightmost digit: `0` → `1` |
| **LED result mode** | Flip SW0 ON, press BTNU | LEDs show binary count of Cand 1 votes |
| **LED result mode** | Flip SW0 ON, press BTNL | LEDs show binary count of Cand 2 votes |
| **Full reset** | Press BTNC | Everything resets to 0 |

### 7-Segment Digit Layout

```
  ┌───────┬───────┬───────┬───────┐
  │ Cand1 │ Cand2 │ Cand3 │ Cand4 │
  │  (AN3)│  (AN2)│  (AN1)│  (AN0)│
  └───────┴───────┴───────┴───────┘
```

Vote counts display as hex (0–F). Values above F wrap around.

## Documentation Created

| File | Purpose |
|---|---|
| [future_modules.md](file:///d:/Academics/DSD/FPGA_Voting_machine/docs/future_modules.md) | Specs for Control Unit FSM, Authentication, Secure Voter ID, Keypad Scanner |
