# Module 4: ALU — Arithmetic Logic Unit

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/ALU.v`

---

## Purpose

The ALU (Arithmetic Logic Unit) is the **computational core** of the voting machine, as described in **Chapter 4** of the project report. It performs arithmetic operations needed during the voting process: incrementing vote counters, summing all counters for integrity checks, and comparing values for authentication. A 2-bit operation code (`alu_op`) selects which operation to execute on each clock cycle.

---

## Full Source Code

```verilog
`timescale 1ns / 1ps

// Arithmetic Logic Unit (ALU)
// Matches report Chapter 4 specification
// Operations: NOP(00), INC(01), SUM(10), COMPARE(11)
module ALU(
    input clk,
    input reset,
    input [1:0] alu_op,
    input [31:0] operand,
    output [31:0] result,
    output reg overflow
);

reg [31:0] acc;

always @(posedge clk) begin
    if (reset) begin
        acc <= 32'd0;
        overflow <= 1'b0;
    end
    else begin
        case (alu_op)
            2'b01: begin  // INC — increment accumulator by 1
                if (acc == 32'hFFFFFFFF)
                    overflow <= 1'b1;
                else
                    acc <= acc + 1;
            end
            2'b10: begin  // SUM — add operand to accumulator
                acc <= acc + operand;
            end
            2'b11: begin  // COMPARE — pass-through (no accumulator change)
                // Result driven combinationally below
            end
            default: begin  // NOP — no operation
                // Do nothing
            end
        endcase
    end
end

// Output mux: COMPARE passes operand through, others output accumulator
assign result = (alu_op == 2'b11) ? operand : acc;

endmodule
```

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | Input | 1 bit | 100 MHz system clock (named `clk` to match report's VHDL convention) |
| `reset` | Input | 1 bit | Active-high synchronous reset — clears accumulator and overflow flag |
| `alu_op` | Input | 2 bits | Operation code selecting which operation to perform (see table below) |
| `operand` | Input | 32 bits | External data input — used by SUM and COMPARE operations |
| `result` | Output | 32 bits | Computation result — either the accumulator value or the operand pass-through |
| `overflow` | Output | 1 bit | Flag set when accumulator reaches maximum value (0xFFFFFFFF) |

---

## Operation Codes

The 2-bit `alu_op` signal selects from four operations, matching the report's Table 4.1:

| `alu_op` | Operation | What It Does | When Used |
|---|---|---|---|
| `2'b00` | **NOP** | No operation — accumulator holds its value | Default/idle state |
| `2'b01` | **INC** | Increment accumulator by 1 | When a vote is cast |
| `2'b10` | **SUM** | Add `operand` to accumulator | Integrity check — sum all counters |
| `2'b11` | **COMPARE** | Pass `operand` through to `result` | Authentication — compare hashes |

---

## Internal Registers

| Register | Width | Purpose |
|---|---|---|
| `acc` | 32 bits | The **accumulator** — the ALU's working register that stores intermediate and final computation results |

The accumulator is the heart of the ALU. All sequential operations (INC, SUM) modify `acc`. Its value persists across clock cycles until explicitly changed by an operation or reset.

---

## How It Works — Step by Step

### Part 1: Reset Logic

```verilog
always @(posedge clk) begin
    if (reset) begin
        acc <= 32'd0;
        overflow <= 1'b0;
    end
```

**On the rising edge of the clock, if `reset` is high:**
- The accumulator is cleared to zero (`32'd0` = 32-bit decimal zero)
- The overflow flag is cleared to `0`

This occurs when the user presses **BTNC** on the Basys 3 board. It prepares the ALU for a fresh election by zeroing out any previous computations.

---

### Part 2: NOP Operation (`alu_op = 2'b00`)

```verilog
            default: begin  // NOP — no operation
                // Do nothing
            end
```

**What happens**: Absolutely nothing. The accumulator retains its current value. The `default` case in the Verilog `case` statement catches `2'b00` (and any undefined values).

**When it's used**: This is the ALU's idle state. In the current top module (`votingMachine.v`), the ALU receives `alu_op = 2'b00` on every clock cycle where no vote is being registered:

```verilog
// In votingMachine.v — ALU operation control:
always @(*) begin
    if (valid_vote_1 || valid_vote_2 || valid_vote_3 || valid_vote_4)
        alu_op = 2'b01;  // INC
    else
        alu_op = 2'b00;  // NOP ← this is the default state
end
```

Since valid votes are extremely rare (one pulse per ~1 second of button holding), the ALU spends 99.9999999% of its time in NOP.

---

### Part 3: INC Operation (`alu_op = 2'b01`)

```verilog
            2'b01: begin  // INC — increment accumulator by 1
                if (acc == 32'hFFFFFFFF)
                    overflow <= 1'b1;
                else
                    acc <= acc + 1;
            end
```

**What happens**: The accumulator increments by 1, **unless** it has already reached the maximum 32-bit value.

**Step-by-step logic:**

1. **Check if accumulator is at maximum**: `32'hFFFFFFFF` = 4,294,967,295 in decimal. This is the largest unsigned 32-bit number.

2. **If at maximum**: Set `overflow <= 1'b1` but **do NOT increment**. This prevents the counter from wrapping around to zero, which would lose vote data. The overflow flag serves as a permanent error condition.

3. **If NOT at maximum**: Increment normally: `acc <= acc + 1`.

**Overflow protection reasoning**: A 32-bit counter can handle over 4.29 billion votes — more than sufficient for any real election. But the overflow check provides a safety net. If somehow triggered, the `overflow` flag could be wired to halt the machine or alert officials (future FSM implementation).

**When it's used**: Currently, every time any candidate receives a valid vote, the ALU receives INC. Note that in the current design, the ALU independently counts total votes (not per-candidate) — the per-candidate counting is handled by `voteLogger`. When the Control Unit FSM is added later, the ALU will be used to increment specific candidate counters in BRAM through coordinated read-modify-write cycles.

---

### Part 4: SUM Operation (`alu_op = 2'b10`)

```verilog
            2'b10: begin  // SUM — add operand to accumulator
                acc <= acc + operand;
            end
```

**What happens**: The value on the `operand` input is added to the current accumulator value. The result is stored back in the accumulator.

**Use case — integrity verification**: After an election, the system can verify vote data integrity by summing all candidate counters:

```
Total = Counter[0] + Counter[1] + Counter[2] + Counter[3]
```

The Control Unit FSM (future) would:
1. Reset the ALU (`acc = 0`)
2. Read Counter[0] from memory → feed to `operand`, set `alu_op = SUM`
3. Read Counter[1] from memory → feed to `operand`, set `alu_op = SUM`
4. Read Counter[2] from memory → feed to `operand`, set `alu_op = SUM`
5. Read Counter[3] from memory → feed to `operand`, set `alu_op = SUM`
6. `acc` now holds the total vote count across all candidates

This total can be compared against the expected number of voters to detect anomalies.

**Current connection**: The ALU's `operand` input is wired to `mem_dout` (memory read data) in the top module:

```verilog
// In votingMachine.v:
ALU alu_inst(
    .clk(clock), .reset(reset),
    .alu_op(alu_op),
    .operand(mem_dout),   // ← Memory output feeds ALU operand
    .result(alu_result),
    .overflow(alu_overflow)
);
```

This connection is already in place for when the FSM orchestrates read-compute-write cycles.

---

### Part 5: COMPARE Operation (`alu_op = 2'b11`)

```verilog
            2'b11: begin  // COMPARE — pass-through (no accumulator change)
                // Result driven combinationally below
            end
```

**What happens inside the always block**: Nothing — the accumulator is not modified.

**What happens at the output**: The `result` output bypasses the accumulator entirely:

```verilog
// Output mux: COMPARE passes operand through, others output accumulator
assign result = (alu_op == 2'b11) ? operand : acc;
```

This is a **combinational multiplexer** (not clocked). When `alu_op == 2'b11`:
- `result = operand` (direct pass-through)
- The accumulator is untouched

**Use case — authentication check**: The Control Unit would:
1. Read a hash from the voter registry (from memory)
2. Set `alu_op = COMPARE`, with the hash on `operand`
3. Compare `result` against the newly computed hash
4. If they match → voter has already voted (reject)

This operation exists so the Control Unit can route memory data through the ALU's result bus for comparison without modifying the accumulator.

---

## Output Logic — The Result Multiplexer

```verilog
assign result = (alu_op == 2'b11) ? operand : acc;
```

This single line determines what appears on the `result` output:

| `alu_op` | `result` equals | Explanation |
|---|---|---|
| `00` (NOP) | `acc` | Current accumulator value (unchanged) |
| `01` (INC) | `acc` | Accumulator value (note: this shows the *old* value on the same cycle, the incremented value appears next cycle due to non-blocking assignment `<=`) |
| `10` (SUM) | `acc` | Accumulator value (same note as INC) |
| `11` (COMPARE) | `operand` | Direct pass-through of operand input |

**Important timing note**: Because `acc` is updated with non-blocking assignment (`<=`), the `result` output during an INC or SUM operation shows the **pre-operation** accumulator value on the same clock cycle. The new value appears on `result` one clock cycle later.

```
Clock     :  _|‾|_|‾|_|‾|_|‾|_
alu_op    :  NOP | INC | NOP | NOP
acc       :   0  |  0  |  1  |  1     ← acc updates one cycle after INC
result    :   0  |  0  |  1  |  1     ← result follows acc
```

---

## Timing Diagram — INC Operation

```
Clock    : _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
alu_op   : NOP  |INC |NOP |NOP |INC |NOP |NOP |NOP |NOP
acc      :  0   | 0  | 1  | 1  | 1  | 2  | 2  | 2  | 2
result   :  0   | 0  | 1  | 1  | 1  | 2  | 2  | 2  | 2
overflow :  0   | 0  | 0  | 0  | 0  | 0  | 0  | 0  | 0
           ↑         ↑              ↑
         reset    acc=0+1=1       acc=1+1=2
```

Each INC pulse increments the accumulator by 1. The new value is visible on `result` starting from the **next** clock cycle.

---

## Timing Diagram — SUM Operation

```
Clock    : _|‾|_|‾|_|‾|_|‾|_|‾|_
alu_op   : NOP  |SUM |SUM |NOP |NOP
operand  :  X   | 5  | 3  | X  | X
acc      :  0   | 0  | 5  | 8  | 8
result   :  0   | 0  | 5  | 8  | 8
                  ↑    ↑
              acc=0+5  acc=5+3
```

---

## Overflow Scenario

```
Clock    : _|‾|_|‾|_|‾|_
alu_op   : INC | INC | INC
acc      : FFFFFFFE | FFFFFFFE | FFFFFFFF | FFFFFFFF
overflow :    0     |    0     |    0     |    1
                                ↑              ↑
                          acc maxes out    overflow flag set
                                          acc stays at FFFFFFFF
```

Once `overflow` goes high, it stays high until `reset` is asserted. The accumulator is frozen at its maximum value to prevent data loss from wraparound.

---

## Behaviour on the FPGA Board

The ALU operates entirely internally — it has **no direct physical I/O** on the board. Its effects are observed indirectly:

1. **During voting**: Every time a valid vote pulse occurs (any button held for 1 second), `alu_op` briefly becomes `INC` for one clock cycle. The ALU's accumulator tracks the **total number of votes** cast across all candidates.

2. **The accumulator value is not displayed** in the current design. It could be displayed by extending the LED logic to show `alu_result` — for example, in a diagnostic mode.

3. **Overflow**: If somehow over 4.29 billion votes are cast (impossible in practice), `alu_overflow` goes high. This signal is currently not connected to any visible output, but the future Control Unit FSM will use it to halt the machine.

4. **After reset** (BTNC): `acc = 0`, `overflow = 0`, `result = 0`.

---

## Connection to Other Modules

```
                                 ┌───────────────────────────┐
  votingMachine.v                │          ALU              │
  ALU operation control:         │                           │
  ┌──────────────────────┐       │  alu_op ───► case stmt    │
  │ valid_vote_1 ──┐     │       │                │          │
  │ valid_vote_2 ──┤     │       │         ┌──────┴──────┐   │
  │ valid_vote_3 ──┤ OR──├──────►│         │             │   │
  │ valid_vote_4 ──┘     │       │      NOP│ INC SUM CMP │   │
  └──────────────────────┘       │         │  │   │   │  │   │
       ↓ if any vote: INC        │         │  ▼   ▼   │  │   │
       ↓ otherwise: NOP          │         │ acc+=1    │  │   │
                                 │         │    acc+=op │  │   │
  memoryUnit                     │         │           │  │   │
  ┌──────────────┐               │  ┌──────┴───────┐   │  │   │
  │ data_out ────├──[32 bits]───►│  │     acc      │   │  │   │
  └──────────────┘               │  └──────┬───────┘   │  │   │
       (operand)                 │         │           │  │   │
                                 │         ▼           │  │   │
                                 │  result = (op==CMP) │  │   │
                                 │    ? operand : acc  │  │   │
                                 │         │           │  │   │
                                 │         ▼           │  │   │
                                 │  ┌──────────────┐   │  │   │
                                 │  │ result [32]  ├───├──┴──►│ (future: CU)
                                 │  │ overflow [1] ├───├─────►│ (future: halt)
                                 │  └──────────────┘   │      │
                                 └─────────────────────────────┘
```

### Current Wiring in `votingMachine.v`

```verilog
// ALU signals
reg [1:0] alu_op;
wire [31:0] alu_result;
wire alu_overflow;

// ALU instantiation
ALU alu_inst(
    .clk(clock), .reset(reset),
    .alu_op(alu_op),
    .operand(mem_dout),       // ← reads from Memory Unit
    .result(alu_result),      // → available for future FSM
    .overflow(alu_overflow)   // → available for future FSM
);

// ALU operation control (simple, will be replaced by FSM)
always @(*) begin
    if (valid_vote_1 || valid_vote_2 || valid_vote_3 || valid_vote_4)
        alu_op = 2'b01;  // INC when any vote happens
    else
        alu_op = 2'b00;  // NOP otherwise
end
```

---

## Comparison with Report's VHDL Version

The project report (Chapter 4, Listing 4.1) provides the ALU in VHDL. Here's how our Verilog implementation maps:

| Report VHDL | Our Verilog | Notes |
|---|---|---|
| `entity ALU is port(...)` | `module ALU(...)` | Same ports, different syntax |
| `signal acc : unsigned(31 downto 0)` | `reg [31:0] acc` | Same 32-bit accumulator |
| `process(clk, reset)` | `always @(posedge clk)` | Verilog uses synchronous reset (best practice for FPGA) |
| `case alu_op is` | `case (alu_op)` | Identical operation codes |
| `when "01" => acc <= acc + 1` | `2'b01: acc <= acc + 1` | Identical logic |
| `result <= std_logic_vector(acc)` | `assign result = ... acc` | Verilog uses continuous assignment |

The logic is functionally identical. The Verilog version adds explicit overflow protection with a flag, matching the report's description of "overflow condition that the Control Unit maps to an error state."

---

## Future Enhancement

When the **Control Unit FSM** (Chapter 5) is implemented, the ALU will be used more extensively:

1. **IDLE state**: `alu_op = NOP`
2. **RECORD_VOTE state**: FSM reads candidate's current count from memory → feeds to ALU as `operand` with `alu_op = SUM` (add 1) → writes `result` back to memory
3. **Integrity check**: FSM sequences through all candidate addresses with `alu_op = SUM` to compute total
4. **Authentication**: FSM uses `alu_op = COMPARE` to route hash data for comparison

The current simple INC-on-vote / NOP-otherwise control will be replaced by the FSM's state-driven `alu_op` generation.
