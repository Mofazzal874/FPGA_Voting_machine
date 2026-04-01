`timescale 1ns / 1ps

// Top Module
module votingMachine(
    input clock,
    input reset,
    input mode,       // SW0: 0 = voting mode, 1 = result display mode
    input button1,    // BTNU - vote for candidate 1
    input button2,    // BTNL - vote for candidate 2
    input button3,    // BTNR - vote for candidate 3
    input button4,    // BTND - vote for candidate 4
    output reg [7:0] led
);

wire valid_vote_1;
wire valid_vote_2;
wire valid_vote_3;
wire valid_vote_4;

wire [7:0] cand1_votes;
wire [7:0] cand2_votes;
wire [7:0] cand3_votes;
wire [7:0] cand4_votes;

// Button control for candidate 1
buttonControl bc1(
    .clock(clock),
    .reset(reset),
    .button(button1),
    .valid_vote(valid_vote_1)
);

// Button control for candidate 2
buttonControl bc2(
    .clock(clock),
    .reset(reset),
    .button(button2),
    .valid_vote(valid_vote_2)
);

// Button control for candidate 3
buttonControl bc3(
    .clock(clock),
    .reset(reset),
    .button(button3),
    .valid_vote(valid_vote_3)
);

// Button control for candidate 4
buttonControl bc4(
    .clock(clock),
    .reset(reset),
    .button(button4),
    .valid_vote(valid_vote_4)
);

// Vote Logger
voteLogger VL(
    .clock(clock),
    .reset(reset),
    .cand1_vote_valid(valid_vote_1),
    .cand2_vote_valid(valid_vote_2),
    .cand3_vote_valid(valid_vote_3),
    .cand4_vote_valid(valid_vote_4),
    .cand1_vote_recvd(cand1_votes),
    .cand2_vote_recvd(cand2_votes),
    .cand3_vote_recvd(cand3_votes),
    .cand4_vote_recvd(cand4_votes)
);

// LED display logic
// mode = 0: Voting mode - LEDs show which buttons are being pressed
//           LED[3:0] map to button4..button1 (active vote indicators)
// mode = 1: Result display mode - press a button to see that candidate's vote count
always @(posedge clock) begin
    if (reset) begin
        led <= 8'd0;
    end
    else begin
        if (mode == 1'b0) begin
            // Voting mode: show active button presses on lower 4 LEDs
            led <= {4'b0000, button4, button3, button2, button1};
        end
        else begin
            // Result display mode: show vote count for selected candidate
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
