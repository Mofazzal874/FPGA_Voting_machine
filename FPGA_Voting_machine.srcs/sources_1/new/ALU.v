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
