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
## Module Hierarchy (Phase 3)

```
votingMachine.v              (Top module — POR generator, BTNC debounce)
  ├── buttonControl.v        (×4: bc1-bc4, parameterized 1-sec hold)
  ├── votingTimer.v          (10-minute election countdown)
  ├── memoryUnit.v           (512×32 BRAM, loaded from nid_table.hex)
  ├── ALU.v                  (32-bit accumulator, 6 ops: NOP/INC/ADD/SUB/LOAD/OR)
  ├── fetchExecuteUnit.v     (Fetch-execute cycle: PC/MAR/MBR, SCAN)
  │   └── comparator.v       (NID match — subtractor-based)
  ├── controlUnit.v          (23-state Moore FSM — voting lifecycle)
  │   └── comparator.v       (Admin password match)
  └── sevenSegDisplay.v      (Multiplexed 4-digit driver, hex + text modes)
```

## Source File Locations

- **RTL**: `FPGA_Voting_machine.srcs/sources_1/new/`
- **Testbench**: `FPGA_Voting_machine.srcs/sim_1/new/votingMachine_tb.v`
- **Constraints**: `FPGA_Voting_machine.srcs/constrs_1/new/Basys3_constraints.xdc`
- **Docs**: `docs/explanation/` (numbered module explanations 01–10)

## Pin Mapping (Basys 3)

### Inputs
| Signal       | Pin | Board Label | Function               |
|--------------|-----|-------------|------------------------|
| `clock`      | W5  | CLK         | 100 MHz system clock   |
| `button1`    | T18 | BTNU        | Candidate 1 vote       |
| `button2`    | W19 | BTNL        | Candidate 2 vote       |
| `button3`    | T17 | BTNR        | Candidate 3 vote       |
| `button4`    | U17 | BTND        | Candidate 4 vote       |
| `btnc`       | U18 | BTNC        | Submit / Confirm       |
| `switches`   | V17–R2 | SW15–SW0 | NID / password entry  |

### Outputs
| Signal      | Pins                                | Function                    |
|-------------|-------------------------------------|-----------------------------|
| `led[15:0]` | U16..V14                            | Status/result LEDs          |
| `seg[6:0]`  | W7,W6,U8,V8,U5,V5,U7               | 7-seg cathodes (active-low) |
| `dp`        | V7                                  | Decimal point (active-low)  |
| `an[3:0]`   | W4,V4,U4,U2                        | 7-seg anodes (active-low)   |

## ALU Operation Codes (3-bit)
| Code     | Op       | Behavior                  |
|----------|----------|---------------------------|
| `3'b000` | NOP      | No change                 |
| `3'b001` | INC      | acc += 1                  |
| `3'b010` | ADD      | acc += operand            |
| `3'b011` | SUB      | acc -= operand            |
| `3'b100` | LOAD     | acc = operand             |
| `3'b101` | OR       | acc \|= operand           |

## Memory Map (512 × 32-bit BRAM)
| Address     | Content                                       |
|-------------|-----------------------------------------------|
| 0x000–0x003 | Candidate 1–4 vote counts                     |
| 0x004       | Admin password (BCD in [15:0])                |
| 0x005–0x00F | Reserved                                      |
| 0x010–0x10F | NID table (256 entries, [16]=voted flag, [15:0]=NID) |
| 0x110–0x1FF | Reserved                                      |

## Build & Test Instructions

1. Open `FPGA_Voting_machine.xpr` in Vivado
2. **Simulate**: Run Behavioral Simulation (`votingMachine_tb.v`)
3. **Synthesize**: Run Synthesis, check for warnings (especially latches or undriven nets)
4. **Implement**: Run Implementation, verify timing is met
5. **Program**: Generate Bitstream, open Hardware Manager, program the Basys 3 via USB

## Coding Rules for This Project

- **Language**: Verilog (`.v` files only). Do not introduce SystemVerilog or VHDL.
- **Naming**: camelCase for signals and modules (e.g., `controlUnit`, `valid_vote`). Follow existing style.
- **No latches**: Always assign all outputs in all branches of combinational logic. Use `default` in `case` statements.
- **Synchronous design**: All flip-flops clocked on `posedge clock` (or `posedge clk`). No `negedge` clocking. No async resets.
- **Active-high reset**: `system_reset` signal is active-high throughout the design (generated by POR).
- **Active-low display**: 7-segment cathodes (`seg`) and anodes (`an`) are active-low.
- **Parameterize thresholds**: Use `parameter` or `localparam` for magic numbers.
- **No blocking assignments in sequential blocks**: Use `<=` (non-blocking) inside `always @(posedge clk)`.
- **No non-blocking assignments in combinational blocks**: Use `=` (blocking) inside `always @(*)`.
- **Test changes**: Update `votingMachine_tb.v` for any new functionality. Run simulation before synthesis.
- **Constraints**: Any new I/O must be mapped in `Basys3_constraints.xdc` with correct pin and IOSTANDARD.

## Current Features (Phase 3)

- **Voter authentication**: NID lookup via FEU SCAN of NID table in BRAM
- **Double-vote prevention**: Bit 16 "voted" flag in NID entries
- **Admin login**: Password stored at `mem[0x004]`, verified via comparator
- **Result viewing**: Admin presses candidate buttons to see individual vote counts
- **Election reset**: Admin clears all vote counts and voted flags, starts new 10-minute election
- **10-minute election timer**: Cascaded counter (no division), auto-expires

## Known Limitations

- BRAM is **volatile** — votes are lost on power cycle. No SPI Flash persistence.
- NID table is limited to 256 entries (addresses 0x010–0x10F).
- No encryption or hash-based authentication — NIDs stored in plaintext BCD.
- 7-segment display shows hex; counts above 0xFFFF require LED result mode.
