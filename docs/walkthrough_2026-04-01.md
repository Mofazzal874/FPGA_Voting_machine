# FPGA Voting Machine — Integration Walkthrough

## What Was Done

Integrated and fixed the provided `buttonControl`, `voteLogger`, and `votingMachine` Verilog modules into the empty Vivado project, added Basys 3 constraints, a simulation testbench, and corrected the FPGA part number.

## Files Created

| File | Purpose |
|---|---|
| [buttonControl.v](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/sources_1/new/buttonControl.v) | Button hold detection (1s at 100 MHz) |
| [voteLogger.v](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/sources_1/new/voteLogger.v) | 4-candidate vote counter (8-bit each) |
| [votingMachine.v](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/sources_1/new/votingMachine.v) | Top module connecting everything |
| [votingMachine_tb.v](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/sim_1/new/votingMachine_tb.v) | Simulation testbench |
| [Basys3_constraints.xdc](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.srcs/constrs_1/new/Basys3_constraints.xdc) | Pin mappings for Basys 3 |

## File Modified

| File | Changes |
|---|---|
| [FPGA_Voting_machine.xpr](file:///d:/Academics/DSD/FPGA_Voting_machine/FPGA_Voting_machine.xpr) | FPGA part → `xc7a35tcpg236-1`, added all file references, set top modules |

## Bugs Fixed

| # | Bug | Fix |
|---|---|---|
| 1 | `button @ counter` — invalid operator | Changed `@` → `&&` |
| 2 | `voteLogger` missing `reset` input | Added `input reset` to port list |
| 3 | `voteLogger` unused `button` input | Removed it |
| 4 | `.reset(reset)` missing dot | Fixed to `.reset(reset)` |
| 5 | All `buttonControl` wired to same `button` | Mapped to `button1`–`button4` |
| 6 | `voteLogger` `.button(reset)` wrong port | Changed to `.reset(reset)` |
| 7 | LED outputs unconnected | Connected with mode-based display logic |

## Basys 3 Pin Assignments

| Signal | Pin | Component |
|---|---|---|
| `clock` | W5 | 100 MHz oscillator |
| `reset` | U18 | BTNC (Center button) |
| `button1` | T18 | BTNU (Up) — Candidate 1 |
| `button2` | W19 | BTNL (Left) — Candidate 2 |
| `button3` | T17 | BTNR (Right) — Candidate 3 |
| `button4` | U17 | BTND (Down) — Candidate 4 |
| `mode` | V17 | SW0 (Slide switch) |
| `led[7:0]` | U16..V14 | LED0–LED7 |

## How to Use on the Board

1. **SW0 = OFF (voting mode)**: LEDs show which buttons are being pressed
2. **Hold a button for 1 second** to cast a vote for that candidate
3. **SW0 = ON (result mode)**: Press a button to see that candidate's vote count (binary on LEDs)
4. **Press BTNC** to reset all vote counts to zero

## Next Steps (User)

1. Open project in Vivado → verify files appear in Sources panel
2. Run **Synthesis** → should complete with 0 errors
3. Run **Behavioral Simulation** → verify vote counting logic
4. Run **Implementation** → **Generate Bitstream** → **Program Device**
