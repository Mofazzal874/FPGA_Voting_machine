# Module 9: votingMachine — Top Module Integration

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/votingMachine.v`

---

## Purpose

The `votingMachine` module is the **top-level module** that instantiates and connects all sub-modules. It also contains two pieces of inline logic that don't warrant separate modules:

1. **Power-On Reset (POR) generator** — produces a synchronous reset for the first 15 clock cycles
2. **BTNC debounce + edge detector** — converts the raw center button into a clean single-cycle pulse

---

## Port Description (Board I/O)

| Port | Direction | Width | FPGA Pin(s) | Description |
|---|---|---|---|---|
| `clock` | Input | 1 | W5 | 100 MHz oscillator |
| `button1` | Input | 1 | T18 (BTNU) | Candidate 1 vote |
| `button2` | Input | 1 | W19 (BTNL) | Candidate 2 vote |
| `button3` | Input | 1 | T17 (BTNR) | Candidate 3 vote |
| `button4` | Input | 1 | U17 (BTND) | Candidate 4 vote |
| `btnc` | Input | 1 | U18 (BTNC) | Submit / Confirm |
| `switches[15:0]` | Input | 16 | V17–R2 | NID / password entry |
| `led[15:0]` | Output | 16 | U16–V14 | Status/result LEDs |
| `seg[6:0]` | Output | 7 | W7–U7 | 7-segment cathodes |
| `dp` | Output | 1 | V7 | Decimal point |
| `an[3:0]` | Output | 4 | W4–U2 | 7-segment anodes |

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `HOLD_THRESHOLD` | 100,000,000 | Button hold time (1 sec) — passed to buttonControl |
| `ONE_SEC` | 100,000,000 | Timer tick (1 sec) — passed to votingTimer |
| `CONFIRM_CYCLES` | 100,000,000 | Confirmation display duration (1 sec) — passed to controlUnit |
| `ERROR_CYCLES` | 200,000,000 | Error display duration (2 sec) — passed to controlUnit |

All parameters are overridden in the testbench to small values (10–30) for fast simulation.

---

## Inline Logic

### Power-On Reset (POR) Generator

```verilog
reg [3:0] por_counter = 4'd0;
wire system_reset = (por_counter != 4'hF);

always @(posedge clock) begin
    if (por_counter != 4'hF)
        por_counter <= por_counter + 1;
end
```

- Counts from 0 to 15 over the first 15 clock cycles (150 ns)
- `system_reset` is HIGH during this time, resetting all modules
- After reaching 15, `system_reset` goes LOW permanently
- **No external reset button** — the system auto-resets on power-up. The admin uses the election management flow (BTNC → admin login → BTNC → reset) for runtime resets.

### BTNC Debounce + Edge Detect

```verilog
reg [20:0] btnc_db_counter;
reg        btnc_stable, btnc_prev;
wire       btnc_pulse = btnc_stable & ~btnc_prev;
```

- **Debounce**: Requires BTNC to be stable for ~20 ms (`2,000,000` cycles) before accepting the new state
- **Edge detect**: `btnc_pulse` produces a single-cycle pulse on the rising edge of the debounced signal
- This is critical because the Control Unit expects exactly 1 pulse per button press. Without debouncing, mechanical bounce could produce multiple false pulses.

---

## Module Instances

| Instance | Module | Count | Description |
|---|---|---|---|
| `bc1–bc4` | `buttonControl` | 4 | One per candidate button |
| `TIMER` | `votingTimer` | 1 | 10-minute election countdown |
| `MEM` | `memoryUnit` | 1 | 512×32 BRAM storage |
| `ALU_INST` | `ALU` | 1 | 32-bit accumulator + arithmetic |
| `FEU` | `fetchExecuteUnit` | 1 | Fetch-execute cycle engine |
| `CU` | `controlUnit` | 1 | 23-state main FSM |
| `SSD` | `sevenSegDisplay` | 1 | Display driver |

---

## Internal Signal Groups

### Button → Control Unit
```
button1 → bc1.button → bc1.valid_vote → CU.valid_vote_1
button2 → bc2.button → bc2.valid_vote → CU.valid_vote_2
(same for bc3, bc4)
btnc    → debounce → btnc_pulse       → CU.btnc_pulse
```

### Control Unit ↔ FEU ↔ Memory ↔ ALU
```
CU.fe_* → FEU.fe_*           (CU commands FEU)
FEU.mem_* → MEM.addr/wr_en   (FEU controls memory)
MEM.data_out → FEU.mem_data_in (memory read data)
FEU.alu_* → ALU.alu_op/operand (FEU drives ALU)
ALU.acc → FEU.alu_acc          (ALU result)
ALU.acc → CU.fe_ac             (CU reads accumulator for decisions)
```

### Control Unit → Display
```
CU.display_value → SSD.display_value → seg, dp, an
CU.display_mode  → SSD.display_mode
CU.led_out       → led (direct assign)
```

### Timer ↔ Control Unit
```
CU.timer_start → TIMER.timer_start
CU.timer_reset → TIMER.timer_reset
TIMER.voting_active → CU.voting_active
```

---

## LED Output

```verilog
assign led = led_out;
```

The 16 LEDs are driven directly by the Control Unit's `led_out` signal, which changes pattern based on FSM state (see `08_controlUnit.md` for patterns).
