`timescale 1ns / 1ps

// Top Module — FPGA Voting Machine
// Integrates: buttonControl, voteLogger, sevenSegDisplay, ALU, memoryUnit
module votingMachine(
    input clock,
    input reset,
    input mode,       // SW0: 0 = voting mode, 1 = result display mode
    input button1,    // BTNU - vote for candidate 1
    input button2,    // BTNL - vote for candidate 2
    input button3,    // BTNR - vote for candidate 3
    input button4,    // BTND - vote for candidate 4
    output reg [7:0] led,
    output [6:0] seg, // 7-segment cathodes (active-low)
    output dp,        // Decimal point (active-low)
    output [3:0] an   // 7-segment anodes (active-low)
);

// =============================================
// Internal wires
// =============================================
wire valid_vote_1, valid_vote_2, valid_vote_3, valid_vote_4;
wire [7:0] cand1_votes, cand2_votes, cand3_votes, cand4_votes;

// Memory signals
reg [5:0] mem_addr;
reg mem_wr;
reg [31:0] mem_din;
wire [31:0] mem_dout;

// ALU signals
reg [1:0] alu_op;
wire [31:0] alu_result;
wire alu_overflow;

// =============================================
// Button Control instances (1-second hold detection)
// =============================================
buttonControl bc1(
    .clock(clock), .reset(reset),
    .button(button1), .valid_vote(valid_vote_1)
);

buttonControl bc2(
    .clock(clock), .reset(reset),
    .button(button2), .valid_vote(valid_vote_2)
);

buttonControl bc3(
    .clock(clock), .reset(reset),
    .button(button3), .valid_vote(valid_vote_3)
);

buttonControl bc4(
    .clock(clock), .reset(reset),
    .button(button4), .valid_vote(valid_vote_4)
);

// =============================================
// Vote Logger (counts votes per candidate)
// =============================================
voteLogger VL(
    .clock(clock), .reset(reset),
    .cand1_vote_valid(valid_vote_1),
    .cand2_vote_valid(valid_vote_2),
    .cand3_vote_valid(valid_vote_3),
    .cand4_vote_valid(valid_vote_4),
    .cand1_vote_recvd(cand1_votes),
    .cand2_vote_recvd(cand2_votes),
    .cand3_vote_recvd(cand3_votes),
    .cand4_vote_recvd(cand4_votes)
);

// =============================================
// 7-Segment Display (shows vote counts on 4 digits)
// =============================================
sevenSegDisplay SSD(
    .clock(clock), .reset(reset),
    .cand1_count(cand1_votes),
    .cand2_count(cand2_votes),
    .cand3_count(cand3_votes),
    .cand4_count(cand4_votes),
    .seg(seg), .dp(dp), .an(an)
);

// =============================================
// ALU (INC/SUM/COMPARE/NOP — Ch.4)
// Connected to memory read data as operand
// Will be orchestrated by Control Unit FSM (future)
// =============================================
ALU alu_inst(
    .clk(clock), .reset(reset),
    .alu_op(alu_op),
    .operand(mem_dout),
    .result(alu_result),
    .overflow(alu_overflow)
);

// =============================================
// Memory Unit (BRAM — Ch.3)
// Stores vote counts at addresses 0-3
// =============================================
memoryUnit MEM(
    .clk(clock), .reset(reset),
    .addr(mem_addr),
    .wr_en(mem_wr),
    .data_in(mem_din),
    .data_out(mem_dout)
);

// =============================================
// Memory write controller
// Rotates through addresses 0-3, writing current vote counts
// =============================================
reg [1:0] mem_write_sel;

always @(posedge clock) begin
    if (reset)
        mem_write_sel <= 2'd0;
    else
        mem_write_sel <= mem_write_sel + 1;
end

always @(*) begin
    mem_addr = {4'b0000, mem_write_sel};
    mem_wr = 1'b1;
    case (mem_write_sel)
        2'd0: mem_din = {24'd0, cand1_votes};
        2'd1: mem_din = {24'd0, cand2_votes};
        2'd2: mem_din = {24'd0, cand3_votes};
        2'd3: mem_din = {24'd0, cand4_votes};
    endcase
end

// =============================================
// ALU operation control
// Currently: INC on any valid vote, NOP otherwise
// Will be fully controlled by FSM (future)
// =============================================
always @(*) begin
    if (valid_vote_1 || valid_vote_2 || valid_vote_3 || valid_vote_4)
        alu_op = 2'b01;  // INC
    else
        alu_op = 2'b00;  // NOP
end

// =============================================
// LED display logic
// mode=0: Voting mode — LEDs show active button presses
// mode=1: Result mode — press button to see vote count (binary)
// =============================================
always @(posedge clock) begin
    if (reset) begin
        led <= 8'd0;
    end
    else begin
        if (mode == 1'b0) begin
            led <= {4'b0000, button4, button3, button2, button1};
        end
        else begin
            if (button1)
                led <= cand1_votes;
            else if (button2)
                led <= cand2_votes;
            else if (button3)
                led <= cand3_votes;
            else if (button4)
                led <= cand4_votes;
            else
                led <= 8'd0;
        end
    end
end

endmodule
