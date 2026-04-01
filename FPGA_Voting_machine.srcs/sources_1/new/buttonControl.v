`timescale 1ns / 1ps

module buttonControl(
    input clock,
    input reset,
    input button,
    output reg valid_vote
);

// 100 MHz clock: 1 second = 100,000,000 cycles
// Button must be held for 1 second to register a valid vote

reg [30:0] counter;

always @(posedge clock) begin
    if (reset)
        counter <= 0;
    else begin
        if (button && counter < 100000001)
            counter <= counter + 1;
        else if (!button)
            counter <= 0;
    end
end

always @(posedge clock) begin
    if (reset)
        valid_vote <= 1'b0;
    else begin
        if (counter == 100000000)
            valid_vote <= 1'b1;
        else
            valid_vote <= 1'b0;
    end
end

endmodule
