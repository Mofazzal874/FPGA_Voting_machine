`timescale 1ns / 1ps

module votingMachine_tb;

// Inputs
reg clock;
reg reset;
reg mode;
reg button1;
reg button2;
reg button3;
reg button4;

// Outputs
wire [7:0] led;
wire [6:0] seg;
wire dp;
wire [3:0] an;

// Instantiate the top module
votingMachine uut(
    .clock(clock),
    .reset(reset),
    .mode(mode),
    .button1(button1),
    .button2(button2),
    .button3(button3),
    .button4(button4),
    .led(led),
    .seg(seg),
    .dp(dp),
    .an(an)
);

// Clock generation: 100 MHz = 10 ns period
initial clock = 0;
always #5 clock = ~clock;

// Helper task: display current 7-seg info
task display_seg_info;
    begin
        $display("  7-seg: an=%b seg=%b dp=%b", an, seg, dp);
    end
endtask

initial begin
    // ========================================
    // Initialize all inputs
    // ========================================
    reset = 1;
    mode = 0;
    button1 = 0;
    button2 = 0;
    button3 = 0;
    button4 = 0;

    // Hold reset for 200ns
    #200;
    reset = 0;
    #20;

    $display("============================================");
    $display("Test 1: Force valid votes and check counting");
    $display("============================================");

    // Force 3 votes for candidate 1
    force uut.valid_vote_1 = 1; #10;
    force uut.valid_vote_1 = 0; #10;
    force uut.valid_vote_1 = 1; #10;
    force uut.valid_vote_1 = 0; #10;
    force uut.valid_vote_1 = 1; #10;
    force uut.valid_vote_1 = 0; #10;

    // Force 2 votes for candidate 2
    force uut.valid_vote_2 = 1; #10;
    force uut.valid_vote_2 = 0; #10;
    force uut.valid_vote_2 = 1; #10;
    force uut.valid_vote_2 = 0; #10;

    // Force 1 vote for candidate 3
    force uut.valid_vote_3 = 1; #10;
    force uut.valid_vote_3 = 0; #10;

    // Force 4 votes for candidate 4
    force uut.valid_vote_4 = 1; #10;
    force uut.valid_vote_4 = 0; #10;
    force uut.valid_vote_4 = 1; #10;
    force uut.valid_vote_4 = 0; #10;
    force uut.valid_vote_4 = 1; #10;
    force uut.valid_vote_4 = 0; #10;
    force uut.valid_vote_4 = 1; #10;
    force uut.valid_vote_4 = 0; #20;

    $display("  Cand1 votes: %d (expected: 3)", uut.cand1_votes);
    $display("  Cand2 votes: %d (expected: 2)", uut.cand2_votes);
    $display("  Cand3 votes: %d (expected: 1)", uut.cand3_votes);
    $display("  Cand4 votes: %d (expected: 4)", uut.cand4_votes);

    // ========================================
    $display("============================================");
    $display("Test 2: LED result mode");
    $display("============================================");
    mode = 1;
    #10;

    button1 = 1; #20;
    $display("  LED (Cand1): %d (expected: 3)", led);
    button1 = 0; #10;

    button2 = 1; #20;
    $display("  LED (Cand2): %d (expected: 2)", led);
    button2 = 0; #10;

    button3 = 1; #20;
    $display("  LED (Cand3): %d (expected: 1)", led);
    button3 = 0; #10;

    button4 = 1; #20;
    $display("  LED (Cand4): %d (expected: 4)", led);
    button4 = 0; #20;

    // ========================================
    $display("============================================");
    $display("Test 3: Memory Unit verification");
    $display("============================================");
    // Wait a few cycles for memory writes to propagate
    #100;
    $display("  MEM[0] (Cand1): %d (expected: 3)", uut.MEM.mem[0]);
    $display("  MEM[1] (Cand2): %d (expected: 2)", uut.MEM.mem[1]);
    $display("  MEM[2] (Cand3): %d (expected: 1)", uut.MEM.mem[2]);
    $display("  MEM[3] (Cand4): %d (expected: 4)", uut.MEM.mem[3]);

    // ========================================
    $display("============================================");
    $display("Test 4: ALU overflow flag");
    $display("============================================");
    $display("  ALU overflow: %b (expected: 0)", uut.alu_overflow);
    $display("  ALU result: %d", uut.alu_result);

    // ========================================
    $display("============================================");
    $display("Test 5: 7-Segment display active");
    $display("============================================");
    display_seg_info;
    // Let the display refresh a few times
    #100;
    display_seg_info;

    // ========================================
    $display("============================================");
    $display("Test 6: Reset clears everything");
    $display("============================================");
    reset = 1; #100;
    reset = 0; #50;
    $display("  After reset:");
    $display("  Cand1 votes: %d (expected: 0)", uut.cand1_votes);
    $display("  Cand2 votes: %d (expected: 0)", uut.cand2_votes);
    $display("  Cand3 votes: %d (expected: 0)", uut.cand3_votes);
    $display("  Cand4 votes: %d (expected: 0)", uut.cand4_votes);
    $display("  ALU overflow: %b (expected: 0)", uut.alu_overflow);

    // ========================================
    $display("============================================");
    $display("Test 7: Voting mode LED indicators");
    $display("============================================");
    mode = 0; #10;
    button1 = 1; button3 = 1; #20;
    $display("  Voting mode, btn1+btn3, LED: %b (expected: 00000101)", led);
    button1 = 0; button3 = 0; #20;

    $display("============================================");
    $display("ALL TESTS COMPLETE");
    $display("============================================");
    $finish;
end

endmodule
