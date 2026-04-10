`timescale 1ns / 1ps

// Arithmetic Logic Unit (ALU) — 32-bit with accumulator
// Operations: NOP, INC, ADD, SUB, LOAD, OR
// The accumulator (AC) is the central register of the fetch-execute datapath
module ALU(
    input clk,
    input reset,
    input [2:0] alu_op,         // Operation select
    input [31:0] operand,       // Second operand (from MBR or Control Unit)
    output [31:0] acc,          // Accumulator value (active at all times)
    output reg overflow,
    output zero_flag             // HIGH when acc == 0
);

    // Operation codes
    localparam OP_NOP  = 3'b000;  // No operation — acc unchanged
    localparam OP_INC  = 3'b001;  // acc <= acc + 1
    localparam OP_ADD  = 3'b010;  // acc <= acc + operand
    localparam OP_SUB  = 3'b011;  // acc <= acc - operand
    localparam OP_LOAD = 3'b100;  // acc <= operand (pass-through load)
    localparam OP_OR   = 3'b101;  // acc <= acc | operand (bitwise OR)

    reg [31:0] acc_reg;

    assign acc = acc_reg;
    assign zero_flag = (acc_reg == 32'd0);

    always @(posedge clk) begin
        if (reset) begin
            acc_reg  <= 32'd0;
            overflow <= 1'b0;
        end
        else begin
            case (alu_op)
                OP_NOP: begin
                    // No change
                end
                OP_INC: begin
                    {overflow, acc_reg} <= {1'b0, acc_reg} + 33'd1;
                end
                OP_ADD: begin
                    {overflow, acc_reg} <= {1'b0, acc_reg} + {1'b0, operand};
                end
                OP_SUB: begin
                    acc_reg  <= acc_reg - operand;
                    overflow <= 1'b0;
                end
                OP_LOAD: begin
                    acc_reg  <= operand;
                    overflow <= 1'b0;
                end
                OP_OR: begin
                    acc_reg  <= acc_reg | operand;
                    overflow <= 1'b0;
                end
                default: begin
                    // NOP
                end
            endcase
        end
    end

endmodule
