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

// Instantiate the top module
votingMachine uut(
    .clock(clock),
    .reset(reset),
    .mode(mode),
    .button1(button1),
    .button2(button2),
    .button3(button3),
    .button4(button4),
    .led(led)
);

// Clock generation: 100 MHz = 10 ns period
initial clock = 0;
always #5 clock = ~clock;

// For simulation, we override the counter threshold inside buttonControl
// to avoid waiting 1 second (100M cycles). We'll directly test at RTL level.
// In simulation, we need to hold buttons for 100M cycles which is impractical,
// so we'll use a shorter test by forcing valid_vote signals.

// Task: simulate a button press held for required duration
// Since 100M cycles at 10ns = 1 second real time = too long for sim,
// we test the logic by directly checking smaller scenarios

initial begin
    // Initialize
    reset = 1;
    mode = 0;
    button1 = 0;
    button2 = 0;
    button3 = 0;
    button4 = 0;

    // Hold reset for 100ns
    #100;
    reset = 0;
    #20;

    // ========================================
    // Test 1: Directly force valid votes to test voteLogger
    // ========================================
    $display("=== Test 1: Force valid votes ===");
    
    // Force a valid vote for candidate 1
    force uut.valid_vote_1 = 1;
    #10;  // one clock cycle
    force uut.valid_vote_1 = 0;
    #10;
    
    // Force another valid vote for candidate 1
    force uut.valid_vote_1 = 1;
    #10;
    force uut.valid_vote_1 = 0;
    #10;
    
    // Force a valid vote for candidate 2
    force uut.valid_vote_2 = 1;
    #10;
    force uut.valid_vote_2 = 0;
    #10;
    
    // Force a valid vote for candidate 3
    force uut.valid_vote_3 = 1;
    #10;
    force uut.valid_vote_3 = 0;
    #10;
    
    // Force a valid vote for candidate 4
    force uut.valid_vote_4 = 1;
    #10;
    force uut.valid_vote_4 = 0;
    #20;
    
    // ========================================
    // Test 2: Check results via mode switch
    // ========================================
    $display("=== Test 2: Check results in display mode ===");
    mode = 1;
    #20;
    
    // Press button1 to see candidate 1 votes (should be 2)
    button1 = 1;
    #20;
    $display("Candidate 1 votes (LED): %d (expected: 2)", led);
    button1 = 0;
    #10;
    
    // Press button2 to see candidate 2 votes (should be 1)
    button2 = 1;
    #20;
    $display("Candidate 2 votes (LED): %d (expected: 1)", led);
    button2 = 0;
    #10;
    
    // Press button3 to see candidate 3 votes (should be 1)
    button3 = 1;
    #20;
    $display("Candidate 3 votes (LED): %d (expected: 1)", led);
    button3 = 0;
    #10;
    
    // Press button4 to see candidate 4 votes (should be 1)
    button4 = 1;
    #20;
    $display("Candidate 4 votes (LED): %d (expected: 1)", led);
    button4 = 0;
    #10;
    
    // ========================================
    // Test 3: Reset clears all votes
    // ========================================
    $display("=== Test 3: Reset clears votes ===");
    reset = 1;
    #50;
    reset = 0;
    #20;
    
    // Check candidate 1 votes after reset (should be 0)
    mode = 1;
    button1 = 1;
    #20;
    $display("Candidate 1 votes after reset (LED): %d (expected: 0)", led);
    button1 = 0;
    #10;
    
    // ========================================
    // Test 4: Voting mode LED indicator
    // ========================================
    $display("=== Test 4: Voting mode LED indicators ===");
    mode = 0;
    #10;
    button1 = 1;
    #20;
    $display("Voting mode, button1 pressed, LED: %b (expected: 00000001)", led);
    button1 = 0;
    button3 = 1;
    #20;
    $display("Voting mode, button3 pressed, LED: %b (expected: 00000100)", led);
    button3 = 0;
    #20;
    
    $display("=== All tests complete ===");
    $finish;
end

endmodule
