`timescale 1ns / 1ps

// 7-Segment Multiplexed Display Driver for Basys 3
// Modes:
//   0 (HEX)  — display_value shown as 4 hex digits
//   1 (donE) — shows "donE"
//   2 (Err)  — shows "Err "
//   3 (uotE) — shows "uotE" (vote prompt)
//   4 (PASS) — shows "PASS"
module sevenSegDisplay(
    input clock,
    input reset,
    input [15:0] display_value,  // 4-digit hex value
    input [2:0]  display_mode,   // 0=hex, 1=donE, 2=Err, 3=uotE, 4=PASS
    output reg [6:0] seg,        // Cathodes {g,f,e,d,c,b,a} active-low
    output wire dp,              // Decimal point active-low (always off)
    output reg [3:0] an          // Anodes active-low
);

    assign dp = 1'b1;  // DP always off

    // Refresh counter: bits [19:18] cycle through 4 digits (~380 Hz each)
    reg [19:0] refresh_counter;
    always @(posedge clock) begin
        if (reset)
            refresh_counter <= 20'd0;
        else
            refresh_counter <= refresh_counter + 1;
    end

    wire [1:0] digit_select = refresh_counter[19:18];

    // Select hex digit from display_value based on position
    reg [3:0] hex_digit;
    always @(*) begin
        case (digit_select)
            2'b00: hex_digit = display_value[3:0];    // AN0 rightmost
            2'b01: hex_digit = display_value[7:4];    // AN1
            2'b10: hex_digit = display_value[11:8];   // AN2
            2'b11: hex_digit = display_value[15:12];  // AN3 leftmost
            default: hex_digit = 4'd0;
        endcase
    end

    // Hex-to-7-segment decoder (active-low: 0 = segment ON)
    // seg = {g, f, e, d, c, b, a}
    reg [6:0] hex_seg;
    always @(*) begin
        case (hex_digit)
            4'h0: hex_seg = 7'b1000000;
            4'h1: hex_seg = 7'b1111001;
            4'h2: hex_seg = 7'b0100100;
            4'h3: hex_seg = 7'b0110000;
            4'h4: hex_seg = 7'b0011001;
            4'h5: hex_seg = 7'b0010010;
            4'h6: hex_seg = 7'b0000010;
            4'h7: hex_seg = 7'b1111000;
            4'h8: hex_seg = 7'b0000000;
            4'h9: hex_seg = 7'b0010000;
            4'hA: hex_seg = 7'b0001000;
            4'hB: hex_seg = 7'b0000011;
            4'hC: hex_seg = 7'b1000110;
            4'hD: hex_seg = 7'b0100001;
            4'hE: hex_seg = 7'b0000110;
            4'hF: hex_seg = 7'b0001110;
            default: hex_seg = 7'b1111111;
        endcase
    end

    // Custom character segment patterns (active-low)
    // seg = {g, f, e, d, c, b, a}
    localparam CH_d     = 7'b0100001;  // d
    localparam CH_o     = 7'b0100011;  // o (lowercase)
    localparam CH_n     = 7'b0101011;  // n (lowercase)
    localparam CH_E     = 7'b0000110;  // E
    localparam CH_r     = 7'b0101111;  // r (lowercase)
    localparam CH_BLANK = 7'b1111111;  // blank
    localparam CH_u     = 7'b1100011;  // u (lowercase)
    localparam CH_t     = 7'b0000111;  // t (lowercase)
    localparam CH_P     = 7'b0001100;  // P
    localparam CH_A     = 7'b0001000;  // A
    localparam CH_S     = 7'b0010010;  // S (same as 5)

    // Text mode lookup: 4 characters per mode
    reg [6:0] text_seg;
    always @(*) begin
        case (display_mode)
            3'd1: begin // "donE"  AN3=d, AN2=o, AN1=n, AN0=E
                case (digit_select)
                    2'b11: text_seg = CH_d;
                    2'b10: text_seg = CH_o;
                    2'b01: text_seg = CH_n;
                    2'b00: text_seg = CH_E;
                    default: text_seg = CH_BLANK;
                endcase
            end
            3'd2: begin // "Err "  AN3=E, AN2=r, AN1=r, AN0=blank
                case (digit_select)
                    2'b11: text_seg = CH_E;
                    2'b10: text_seg = CH_r;
                    2'b01: text_seg = CH_r;
                    2'b00: text_seg = CH_BLANK;
                    default: text_seg = CH_BLANK;
                endcase
            end
            3'd3: begin // "uotE"  AN3=u, AN2=o, AN1=t, AN0=E
                case (digit_select)
                    2'b11: text_seg = CH_u;
                    2'b10: text_seg = CH_o;
                    2'b01: text_seg = CH_t;
                    2'b00: text_seg = CH_E;
                    default: text_seg = CH_BLANK;
                endcase
            end
            3'd4: begin // "PASS"  AN3=P, AN2=A, AN1=S, AN0=S
                case (digit_select)
                    2'b11: text_seg = CH_P;
                    2'b10: text_seg = CH_A;
                    2'b01: text_seg = CH_S;
                    2'b00: text_seg = CH_S;
                    default: text_seg = CH_BLANK;
                endcase
            end
            default: text_seg = CH_BLANK;
        endcase
    end

    // Anode select — enable one digit at a time
    always @(*) begin
        case (digit_select)
            2'b00: an = 4'b1110;  // AN0 active
            2'b01: an = 4'b1101;  // AN1 active
            2'b10: an = 4'b1011;  // AN2 active
            2'b11: an = 4'b0111;  // AN3 active
            default: an = 4'b1111;
        endcase
    end

    // Final segment output: hex mode or text mode
    always @(*) begin
        if (display_mode == 3'd0)
            seg = hex_seg;
        else
            seg = text_seg;
    end

endmodule
