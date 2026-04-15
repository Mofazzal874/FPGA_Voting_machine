# Module 4: ALU — Arithmetic Logic Unit

## Source File
`FPGA_Voting_machine.srcs/sources_1/new/ALU.v`

---

## Purpose

The ALU is the **computational core** of the voting machine's datapath. It contains a 32-bit **accumulator register (AC)** and supports 6 operations selected by a 3-bit opcode. The Fetch-Execute Unit drives the ALU to perform read-modify-write cycles on memory data (incrementing vote counts, setting voted flags, loading values for comparison).

---

## Port Description

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | Input | 1 bit | 100 MHz system clock |
| `reset` | Input | 1 bit | Active-high synchronous reset — clears accumulator and overflow |
| `alu_op` | Input | 3 bits | Operation code (see table below) |
| `operand` | Input | 32 bits | Second operand (from FEU's MBR or Control Unit data) |
| `acc` | Output | 32 bits | Accumulator value — continuously driven, available at all times |
| `overflow` | Output | 1 bit | Flag set when INC or ADD causes a carry beyond 32 bits |
| `zero_flag` | Output | 1 bit | HIGH when accumulator equals zero |

---

## Operation Codes (3-bit)

| Code | Name | Operation | When Used |
|---|---|---|---|
| `3'b000` | **NOP** | No change to accumulator | Default / idle |
| `3'b001` | **INC** | `acc <= acc + 1` | Increment vote count after reading |
| `3'b010` | **ADD** | `acc <= acc + operand` | (Reserved for future sum/integrity checks) |
| `3'b011` | **SUB** | `acc <= acc - operand` | (Reserved for future comparisons) |
| `3'b100` | **LOAD** | `acc <= operand` | Load memory data into accumulator |
| `3'b101` | **OR** | `acc <= acc \| operand` | Set voted flag (bit 16) in NID entry |

---

## Internal Registers

| Register | Width | Purpose |
|---|---|---|
| `acc_reg` | 32 bits | The accumulator — the ALU's working register |

The output `acc` is a continuous assignment of `acc_reg`.

---

## How It Works

### LOAD Operation — Loading Data into Accumulator

```verilog
OP_LOAD: begin
    acc_reg  <= operand;
    overflow <= 1'b0;
end
```

The FEU uses LOAD to transfer memory data (via MBR) into the accumulator. For example, when reading a candidate's vote count, the FEU reads from memory, then tells the ALU to LOAD that value.

### INC Operation — Incrementing Vote Count

```verilog
OP_INC: begin
    {overflow, acc_reg} <= {1'b0, acc_reg} + 33'd1;
end
```

After loading a vote count, the FEU issues INC to add 1. **Overflow is detected using 33-bit addition** — explained in detail below.

### ADD Operation — Adding Operand to Accumulator

```verilog
OP_ADD: begin
    {overflow, acc_reg} <= {1'b0, acc_reg} + {1'b0, operand};
end
```

Same 33-bit overflow technique as INC, but adds an arbitrary 32-bit operand instead of 1.

---

## How 33-Bit Addition Detects Overflow (Detailed)

This is the key technique used in both INC and ADD. Let's break it down completely.

### The Problem

`acc_reg` is 32 bits wide. The largest unsigned 32-bit value is:

```
32'hFFFFFFFF = 4,294,967,295
```

If `acc_reg = 32'hFFFFFFFF` and we try to add 1, the result should be `4,294,967,296` — but that's **33 bits** wide (`33'h1_0000_0000`). A 32-bit register can't hold it. Without overflow detection, the value would silently wrap to `0`, losing all vote data.

### The Solution: Widen the Addition to 33 Bits

```verilog
{overflow, acc_reg} <= {1'b0, acc_reg} + 33'd1;
```

This single line does **three things**:

#### Step 1: Zero-extend `acc_reg` to 33 bits (right side)

```
{1'b0, acc_reg}
```

This is **concatenation** — it prepends a single `0` bit to the left of `acc_reg`:

```
acc_reg  =     XXXXXXXX_XXXXXXXX_XXXXXXXX_XXXXXXXX   (32 bits)
                ↓
{1'b0, acc_reg} = 0_XXXXXXXX_XXXXXXXX_XXXXXXXX_XXXXXXXX   (33 bits)
```

The extra `0` bit at position 32 creates space for a potential carry-out.

#### Step 2: Perform the addition in 33-bit space

```
  0_XXXXXXXX_XXXXXXXX_XXXXXXXX_XXXXXXXX   (33-bit acc)
+                                      1   (33-bit literal 33'd1)
─────────────────────────────────────────
= C_RRRRRRRR_RRRRRRRR_RRRRRRRR_RRRRRRRR   (33-bit result)
  ↑ ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  │              32-bit result
  └── carry bit (bit 32 of the sum)
```

Because we're adding in 33-bit space, there's room for the carry. The result is a full 33-bit value.

#### Step 3: Assign the 33-bit result to `{overflow, acc_reg}` (left side)

```
{overflow, acc_reg}    =    33-bit concatenation target
    1 bit    32 bits         (overflow gets bit 32, acc_reg gets bits 31:0)
```

This **destructures** the 33-bit result:
- **Bit 32** (the carry) goes into `overflow`
- **Bits 31:0** (the actual sum) go into `acc_reg`

### Numeric Examples

#### Example 1: Normal increment (no overflow)

```
acc_reg = 32'h00000005 (decimal 5)

Step 1:  {1'b0, 32'h00000005} = 33'h0_00000005
Step 2:  33'h0_00000005 + 33'd1 = 33'h0_00000006
Step 3:  {overflow, acc_reg} = {0, 32'h00000006}
         overflow = 0    ✓ No overflow
         acc_reg  = 6    ✓ Correct result
```

#### Example 2: Overflow on maximum value

```
acc_reg = 32'hFFFFFFFF (decimal 4,294,967,295)

Step 1:  {1'b0, 32'hFFFFFFFF} = 33'h0_FFFFFFFF
Step 2:  33'h0_FFFFFFFF + 33'd1 = 33'h1_00000000
                                       ↑
                                  Bit 32 is 1!
Step 3:  {overflow, acc_reg} = {1, 32'h00000000}
         overflow = 1    ✓ Overflow detected!
         acc_reg  = 0    (wrapped, but overflow flag alerts the system)
```

#### Example 3: ADD with large operand

```
acc_reg = 32'h80000000 (decimal 2,147,483,648)
operand = 32'h80000001 (decimal 2,147,483,649)
Sum     = 4,294,967,297 — exceeds 32-bit max!

Step 1:  {1'b0, 32'h80000000} = 33'h0_80000000
         {1'b0, 32'h80000001} = 33'h0_80000001
Step 2:  33'h0_80000000 + 33'h0_80000001 = 33'h1_00000001
Step 3:  {overflow, acc_reg} = {1, 32'h00000001}
         overflow = 1    ✓ Overflow detected!
```

### Why Not Just Check `if (acc == 32'hFFFFFFFF)` Before Adding?

That approach (used in an earlier version of this ALU) only works for INC (+1). It can't detect overflow for ADD with arbitrary operands — you'd need to check `if (acc + operand > 32'hFFFFFFFF)`, which itself could overflow. The 33-bit trick works universally for any addition.

### Hardware Cost

The 33-bit adder uses only **one extra full-adder cell** compared to a 32-bit adder. On Xilinx Artix-7, adders are implemented in the FPGA's dedicated carry chain (CARRY4 primitives), so one extra bit adds negligible area and zero extra delay (the carry chain is already there).

---

### SUB Operation — Subtraction

```verilog
OP_SUB: begin
    acc_reg  <= acc_reg - operand;
    overflow <= 1'b0;
end
```

Subtraction does **not** use the 33-bit trick — it simply performs 32-bit subtraction and clears overflow. If `operand > acc_reg`, the result wraps around (unsigned underflow), but the overflow flag is not set. This is fine for the current design since SUB is reserved for future use and not used in the voting pipeline.

### OR Operation — Setting the Voted Flag

```verilog
OP_OR: begin
    acc_reg <= acc_reg | operand;
    overflow <= 1'b0;
end
```

Bitwise OR can never overflow (OR can only set bits, never create a carry), so overflow is always cleared. Used to set bit 16 in an NID entry (the "already voted" flag). The FEU loads the NID entry into AC, then ORs with `0x00010000` to set the flag without disturbing the NID value in bits [15:0].

### Zero Flag

```verilog
assign zero_flag = (acc_reg == 32'd0);
```

Combinational output — always reflects the current accumulator state. Available for the Control Unit to check conditions.

---

## Timing — Vote Count Increment Example

```
Clock    : __|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__
alu_op   :  NOP  |LOAD | NOP | INC | NOP
operand  :   X   |  5  |  X  |  X  |  X
acc_reg  :   0   |  0  |  5  |  5  |  6
overflow :   0   |  0  |  0  |  0  |  0
acc (out):   0   |  0  |  5  |  5  |  6
                   ↑          ↑
              Load count=5   Increment to 6
              (overflow=0)   33'h0_00000005 + 1 = 33'h0_00000006
                             overflow=0, acc=6 ✓
```

The FEU orchestrates the sequence: LOAD (read from memory) → INC (add 1) → then writes `acc` back to memory via WRITE_AC.

---

## Connection to Other Modules

```
      fetchExecuteUnit                    ALU
      ┌─────────────────┐         ┌─────────────────┐
      │                 │         │                 │
      │  alu_op [2:0] ──┤────────►│  alu_op         │
      │                 │         │                 │
      │  alu_operand ───┤────────►│  operand [31:0] │
      │   [31:0]        │         │                 │
      │                 │         │  acc [31:0] ────┤────► FEU (for WRITE_AC)
      │  alu_acc ◄──────┤◄────────┤                 │────► Control Unit (fe_ac)
      │                 │         │  overflow ──────┤────► (available)
      │                 │         │  zero_flag ─────┤────► (available)
      └─────────────────┘         └─────────────────┘
```

- **Driven by**: Fetch-Execute Unit (`alu_op` and `alu_operand`)
- **Read by**: Fetch-Execute Unit (uses `alu_acc` for WRITE_AC operations), Control Unit (reads `fe_ac` for decision making — e.g., checking voted flag bit 16)
