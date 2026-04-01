`timescale 1ns / 1ps

// 7-Segment Multiplexed Display Driver for Basys 3
// Drives 4 common-anode digits showing hex vote counts (0-F per candidate)
// Digit layout: AN3=Cand1 | AN2=Cand2 | AN1=Cand3 | AN0=Cand4
module sevenSegDisplay(
    input clock,
    input reset,
    input [7:0] cand1_count,  // Candidate 1 vote count
    input [7:0] cand2_count,  // Candidate 2 vote count
    input [7:0] cand3_count,  // Candidate 3 vote count
    input [7:0] cand4_count,  // Candidate 4 vote count
    output reg [6:0] seg,     // Cathodes {g,f,e,d,c,b,a} active-low
    output wire dp,           // Decimal point active-low (always off)
    output reg [3:0] an       // Anodes active-low
);

// Decimal point always off
assign dp = 1'b1;

// Refresh counter: bits [19:18] cycle through 4 digits
// At 100MHz: full cycle = 2^20 / 100MHz = ~10.5ms → ~380Hz per digit
reg [19:0] refresh_counter;

always @(posedge clock) begin
    if (reset)
        refresh_counter <= 20'd0;
    else
        refresh_counter <= refresh_counter + 1;
end

wire [1:0] digit_select = refresh_counter[19:18];

// Select which digit to display and which value
reg [3:0] hex_digit;

always @(*) begin
    case (digit_select)
        2'b00: begin  // AN0 = Candidate 4 (rightmost)
            an = 4'b1110;
            hex_digit = cand4_count[3:0];  // Low nibble
        end
        2'b01: begin  // AN1 = Candidate 3
            an = 4'b1101;
            hex_digit = cand3_count[3:0];
        end
        2'b10: begin  // AN2 = Candidate 2
            an = 4'b1011;
            hex_digit = cand2_count[3:0];
        end
        2'b11: begin  // AN3 = Candidate 1 (leftmost)
            an = 4'b0111;
            hex_digit = cand1_count[3:0];
        end
        default: begin
            an = 4'b1111;
            hex_digit = 4'd0;
        end
    endcase
end

// Hex to 7-segment decoder (active-low)
// seg = {g, f, e, d, c, b, a}
always @(*) begin
    case (hex_digit)
        4'h0: seg = 7'b1000000;
        4'h1: seg = 7'b1111001;
        4'h2: seg = 7'b0100100;
        4'h3: seg = 7'b0110000;
        4'h4: seg = 7'b0011001;
        4'h5: seg = 7'b0010010;
        4'h6: seg = 7'b0000010;
        4'h7: seg = 7'b1111000;
        4'h8: seg = 7'b0000000;
        4'h9: seg = 7'b0010000;
        4'hA: seg = 7'b0001000;
        4'hB: seg = 7'b0000011;
        4'hC: seg = 7'b1000110;
        4'hD: seg = 7'b0100001;
        4'hE: seg = 7'b0000110;
        4'hF: seg = 7'b0001110;
        default: seg = 7'b1111111;  // All off
    endcase
end

endmodule
