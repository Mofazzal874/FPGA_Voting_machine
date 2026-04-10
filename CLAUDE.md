# CLAUDE.md - FPGA Voting Machine

## Project Overview

Hardware-based electronic voting machine for **Basys 3 FPGA board** (Xilinx Artix-7 XC7A35T-1CPG236-1L). Supports 4 candidates with dedicated push buttons, 1-second hold-to-vote debouncing, 7-segment hex display, and binary LED result viewing.

## Target Hardware

- **Board**: Digilent Basys 3
- **FPGA**: Xilinx Artix-7 XC7A35T-1CPG236-1L
- **Clock**: 100 MHz onboard oscillator (pin W5)
- **I/O Standard**: LVCMOS33 (3.3V) for all pins
- **Tool**: Xilinx Vivado (project file: `FPGA_Voting_machine.xpr`)

## Critical Constraints

- All timing is based on **100 MHz clock** (10 ns period). Never change the clock frequency without recalculating all counter thresholds.
- Button hold threshold is `100_000_000` cycles (1 second). This value appears in `buttonControl.v`.
- 7-segment refresh counter uses bits `[19:18]` of a free-running counter (~381 Hz per digit). Do not reduce this — lower rates cause visible flicker on the physical board.
- Vote counters are **8-bit** (`[7:0]`). Max 255 votes per candidate before rollover. Sufficient for classroom demos.
- Memory unit uses `(* ram_style = "block" *)` to infer BRAM. Do not change to distributed RAM without reason.
- All resets are **synchronous** and **active-high** (BTNC / pin U18).

## Module Hierarchy

```
votingMachine.v          (Top module)
  +-- buttonControl.v    (x4 instances: bc1-bc4, 1-sec hold debounce)
  +-- voteLogger.v       (Counts votes per candidate, 8-bit each)
  +-- sevenSegDisplay.v  (Multiplexed 4-digit 7-seg driver)
  +-- ALU.v              (32-bit: INC/SUM/COMPARE/NOP)
  +-- memoryUnit.v       (64x32-bit BRAM, addresses 0-3 = candidate counts)
```

## Source File Locations

- **RTL**: `FPGA_Voting_machine.srcs/sources_1/new/`
- **Testbench**: `FPGA_Voting_machine.srcs/sim_1/new/votingMachine_tb.v`
- **Constraints**: `FPGA_Voting_machine.srcs/constrs_1/new/Basys3_constraints.xdc`
- **Docs**: `docs/` (walkthroughs, module explanations, future specs)

## Pin Mapping (Basys 3)

### Inputs
| Signal    | Pin | Board Label | Function              |
|-----------|-----|-------------|-----------------------|
| `clock`   | W5  | CLK         | 100 MHz system clock  |
| `reset`   | U18 | BTNC        | Center button (reset)  |
| `mode`    | V17 | SW0         | 0=voting, 1=results   |
| `button1` | T18 | BTNU        | Candidate 1 vote      |
| `button2` | W19 | BTNL        | Candidate 2 vote      |
| `button3` | T17 | BTNR        | Candidate 3 vote      |
| `button4` | U17 | BTND        | Candidate 4 vote      |

### Outputs
| Signal     | Pins                          | Function                    |
|------------|-------------------------------|-----------------------------|
| `led[7:0]` | U16,E19,U19,V19,W18,U15,U14,V14 | Status/result LEDs     |
| `seg[6:0]` | W7,W6,U8,V8,U5,V5,U7        | 7-seg cathodes (active-low) |
| `dp`       | V7                            | Decimal point (active-low)  |
| `an[3:0]`  | W4,V4,U4,U2                  | 7-seg anodes (active-low)   |

## ALU Operation Codes
| Code   | Op      | Behavior                |
|--------|---------|-------------------------|
| `2'b00`| NOP     | No change               |
| `2'b01`| INC     | Accumulator += 1        |
| `2'b10`| SUM     | Accumulator += operand  |
| `2'b11`| COMPARE | Result = operand        |

## Memory Map
| Address | Content             |
|---------|---------------------|
| 0       | Candidate 1 votes   |
| 1       | Candidate 2 votes   |
| 2       | Candidate 3 votes   |
| 3       | Candidate 4 votes   |
| 4-63    | Reserved (future)   |

## Build & Test Instructions

1. Open `FPGA_Voting_machine.xpr` in Vivado
2. **Simulate**: Run Behavioral Simulation (`votingMachine_tb.v`)
3. **Synthesize**: Run Synthesis, check for warnings (especially latches or undriven nets)
4. **Implement**: Run Implementation, verify timing is met
5. **Program**: Generate Bitstream, open Hardware Manager, program the Basys 3 via USB

## Coding Rules for This Project

- **Language**: Verilog (`.v` files only). Do not introduce SystemVerilog or VHDL.
- **Naming**: camelCase for signals and modules (e.g., `voteLogger`, `valid_vote`). Follow existing style.
- **No latches**: Always assign all outputs in all branches of combinational logic. Use `default` in `case` statements.
- **Synchronous design**: All flip-flops clocked on `posedge clock` (or `posedge clk`). No `negedge` clocking. No async resets.
- **Active-high reset**: `reset` signal is active-high throughout the design.
- **Active-low display**: 7-segment cathodes (`seg`) and anodes (`an`) are active-low. A segment lights when its cathode is `0` and its anode is `0`.
- **Parameterize thresholds**: Use `parameter` or `localparam` for magic numbers (counter limits, widths).
- **No blocking assignments in sequential blocks**: Use `<=` (non-blocking) inside `always @(posedge clk)`.
- **No non-blocking assignments in combinational blocks**: Use `=` (blocking) inside `always @(*)`.
- **Test changes**: Update `votingMachine_tb.v` for any new functionality. Run simulation before synthesis.
- **Constraints**: Any new I/O must be mapped in `Basys3_constraints.xdc` with correct pin and IOSTANDARD.

## Known Limitations

- 7-segment display shows hex (0-F), so counts above 15 wrap visually. Use result mode (SW0=ON) + button press to see full 8-bit count on LEDs.
- No voter authentication or double-vote prevention yet (planned for Phase 3).
- No persistent storage — votes are lost on power cycle or reset.
- ALU and memory are integrated but lightly used; the FSM control unit (Phase 3) will fully utilize them.

## Planned Future Work (Not Yet Implemented)

- **Control Unit FSM**: 7-state Moore machine for full voting lifecycle (docs/future_modules.md)
- **Authentication Module**: PIN-based voter verification with HMAC-SHA256
- **Voter ID Registry**: SHA-256 hash storage in BRAM for double-vote prevention
- **4x4 Keypad Scanner**: Matrix keypad input for voter credentials
