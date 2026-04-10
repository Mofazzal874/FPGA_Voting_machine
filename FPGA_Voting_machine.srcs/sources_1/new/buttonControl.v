`timescale 1ns / 1ps

module buttonControl #(
    parameter HOLD_THRESHOLD = 100_000_000  // 1 sec at 100 MHz (override for sim)
)(
    input clock,
    input reset,
    input enable,       // Must be HIGH for vote to register
    input button,
    output reg valid_vote
);

// Button must be held for HOLD_THRESHOLD cycles to register a valid vote

reg [30:0] counter;

always @(posedge clock) begin
    if (reset)
        counter <= 0;
    else begin
        if (enable && button && counter < HOLD_THRESHOLD + 1)
            counter <= counter + 1;
        else if (!button)
            counter <= 0;
    end
end

always @(posedge clock) begin
    if (reset)
        valid_vote <= 1'b0;
    else begin
        if (counter == HOLD_THRESHOLD)
            valid_vote <= 1'b1;
        else
            valid_vote <= 1'b0;
    end
end

endmodule
