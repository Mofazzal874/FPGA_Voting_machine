`timescale 1ns / 1ps

// Comparator — Subtractor-based equality check
// Computes (input_a - input_b); if difference is zero, values match.
// Purely combinational — result available same cycle.
module comparator(
    input [15:0] input_a,   // Value A (e.g., voter NID from switches)
    input [15:0] input_b,   // Value B (e.g., stored NID from memory)
    output match             // HIGH if A == B (difference is zero)
);

    wire [16:0] diff = {1'b0, input_a} - {1'b0, input_b};

    assign match = (diff == 17'd0);

endmodule
