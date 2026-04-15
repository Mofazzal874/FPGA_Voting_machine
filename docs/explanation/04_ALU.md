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

After loading a vote count, the FEU issues INC to add 1. The 33-bit addition catches overflow.

### OR Operation — Setting the Voted Flag

```verilog
OP_OR: begin
    acc_reg <= acc_reg | operand;
    overflow <= 1'b0;
end
```

Used to set bit 16 in an NID entry (the "already voted" flag). The FEU loads the NID entry into AC, then ORs with `0x00010000` to set the flag without disturbing the NID value in bits [15:0].

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
acc (out):   0   |  0  |  5  |  5  |  6
                   ↑          ↑
              Load count=5   Increment to 6
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
