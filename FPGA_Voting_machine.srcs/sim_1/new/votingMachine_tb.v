`timescale 1ns / 1ps

// Testbench for FPGA Voting Machine — Phase 3
// Uses small parameter values for fast simulation:
//   Button hold = 10 cycles, timer 1-sec = 20 cycles, confirm = 20 cycles
module votingMachine_tb;

    // Clock
    reg clock;
    initial clock = 0;
    always #5 clock = ~clock;  // 100 MHz -> 10 ns period

    // Inputs
    reg        button1, button2, button3, button4;
    reg        btnc;
    reg [15:0] switches;

    // Outputs
    wire [15:0] led;
    wire [6:0]  seg;
    wire        dp;
    wire [3:0]  an;

    // DUT with small parameters for simulation
    votingMachine #(
        .HOLD_THRESHOLD(10),
        .ONE_SEC(20),
        .CONFIRM_CYCLES(20),
        .ERROR_CYCLES(30)
    ) DUT(
        .clock(clock),
        .button1(button1),
        .button2(button2),
        .button3(button3),
        .button4(button4),
        .btnc(btnc),
        .switches(switches),
        .led(led),
        .seg(seg),
        .dp(dp),
        .an(an)
    );

    // Access internal signals for debug
    wire [4:0] cu_state      = DUT.CU.state;
    wire [3:0] feu_state     = DUT.FEU.state;
    wire [31:0] alu_acc_val  = DUT.alu_acc;
    wire voting_active       = DUT.voting_active;
    wire fe_done             = DUT.fe_done;
    wire fe_match            = DUT.fe_match;
    wire [8:0] fe_match_addr = DUT.fe_match_addr;
    wire system_reset        = DUT.system_reset;

    // Wait for CU to reach a specific state (with timeout)
    task wait_for_state;
        input [4:0] target;
        integer timeout;
        begin
            timeout = 0;
            while (cu_state != target && timeout < 10000) begin
                @(posedge clock);
                timeout = timeout + 1;
            end
            if (timeout >= 10000)
                $display("  *** TIMEOUT waiting for CU state %0d at time %0t ***", target, $time);
        end
    endtask

    // Inject a single-cycle btnc_pulse (bypasses the slow debouncer)
    task inject_btnc;
        begin
            @(posedge clock);
            force DUT.btnc_pulse = 1;
            @(posedge clock);
            release DUT.btnc_pulse;
            #10;
        end
    endtask

    // Hold a candidate button long enough for valid_vote (>HOLD_THRESHOLD)
    task vote_for;
        input [1:0] cand;
        begin
            case (cand)
                2'd0: button1 = 1;
                2'd1: button2 = 1;
                2'd2: button3 = 1;
                2'd3: button4 = 1;
            endcase
            // Hold for HOLD_THRESHOLD+5 cycles = 15 * 10ns = 150ns
            #150;
            button1 = 0; button2 = 0; button3 = 0; button4 = 0;
            #50;
        end
    endtask

    // Main test sequence
    initial begin
        // Initialize
        button1 = 0; button2 = 0; button3 = 0; button4 = 0;
        btnc = 0;
        switches = 16'h0000;

        $display("==============================================");
        $display("  FPGA Voting Machine — Phase 3 Testbench");
        $display("==============================================");

        // Wait for POR to finish
        @(negedge system_reset);
        #50;
        $display("[%0t] POR complete. CU state=%0d, voting_active=%b", $time, cu_state, voting_active);

        // =============================================
        // TEST 1: Admin login with correct password
        // =============================================
        $display("\n--- TEST 1: Admin login (pw=2580) ---");
        switches = 16'h2580;
        #20;
        inject_btnc;

        wait_for_state(5'd14); // S_RESULT_DISPLAY
        $display("  PASS: Admin logged in → RESULT_DISPLAY (state %0d)", cu_state);

        // =============================================
        // TEST 2: Admin starts election (BTNC in RESULT_DISPLAY)
        // =============================================
        $display("\n--- TEST 2: Admin starts election ---");
        inject_btnc;

        wait_for_state(5'd0); // S_IDLE
        #200; // Let timer start
        $display("  voting_active=%b (expected 1)", voting_active);
        if (voting_active)
            $display("  PASS: Election started.");
        else
            $display("  FAIL: Election did not start!");

        // =============================================
        // TEST 3: Voter NID=0037 votes for Candidate 1
        // =============================================
        $display("\n--- TEST 3: Voter NID=0037 → Candidate 1 ---");
        switches = 16'h0037;
        #20;
        inject_btnc;

        wait_for_state(5'd4); // S_VOTE_ACTIVE
        $display("  NID verified. fe_match=%b, addr=%h", fe_match, fe_match_addr);

        vote_for(2'd0); // Candidate 1

        wait_for_state(5'd11); // S_CONFIRM
        $display("  Vote recorded. In CONFIRM. LEDs=%h", led);

        wait_for_state(5'd0); // S_IDLE
        $display("  PASS: Back in IDLE. MEM[0]=%0d (expected 1)", DUT.MEM.mem[0]);

        // =============================================
        // TEST 4: Voter NID=0097 votes for Candidate 2
        // =============================================
        $display("\n--- TEST 4: Voter NID=0097 → Candidate 2 ---");
        switches = 16'h0097;
        #20;
        inject_btnc;

        wait_for_state(5'd4); // S_VOTE_ACTIVE
        vote_for(2'd1); // Candidate 2

        wait_for_state(5'd0);
        $display("  PASS: MEM[1]=%0d (expected 1)", DUT.MEM.mem[1]);

        // =============================================
        // TEST 5: Voter NID=0106 votes for Candidate 1 (second vote for cand1)
        // =============================================
        $display("\n--- TEST 5: Voter NID=0106 → Candidate 1 ---");
        switches = 16'h0106;
        #20;
        inject_btnc;

        wait_for_state(5'd4);
        vote_for(2'd0);

        wait_for_state(5'd0);
        $display("  PASS: MEM[0]=%0d (expected 2)", DUT.MEM.mem[0]);

        // =============================================
        // TEST 6: Duplicate vote — NID=0037 tries again
        // =============================================
        $display("\n--- TEST 6: Duplicate vote (NID=0037) ---");
        switches = 16'h0037;
        #20;
        inject_btnc;

        wait_for_state(5'd21); // S_ERROR
        $display("  PASS: Duplicate rejected → ERROR state.");

        wait_for_state(5'd0);

        // =============================================
        // TEST 7: Invalid NID
        // =============================================
        $display("\n--- TEST 7: Invalid NID (9999) ---");
        switches = 16'h9999;
        #20;
        inject_btnc;

        wait_for_state(5'd21); // S_ERROR
        $display("  PASS: Invalid NID rejected → ERROR state.");

        wait_for_state(5'd0);

        // =============================================
        // TEST 8: Admin views results after timer expires
        // =============================================
        $display("\n--- TEST 8: Admin views results ---");
        // Force timer to expire
        force DUT.TIMER.active = 0;
        @(posedge clock);
        release DUT.TIMER.active;
        #100;
        $display("  voting_active=%b (should be 0)", voting_active);

        // Admin login
        switches = 16'h2580;
        #20;
        inject_btnc;

        wait_for_state(5'd14); // S_RESULT_DISPLAY
        $display("  Admin in RESULT_DISPLAY.");

        // View candidate 1 — raw button press (no hold needed in result mode)
        button1 = 1; #30; button1 = 0; #10;

        wait_for_state(5'd16); // S_RESULT_SHOW
        #10;
        $display("  Candidate 1 count: ACC=%0d (expected 2)", alu_acc_val);

        wait_for_state(5'd14);
        #20;

        // View candidate 2
        button2 = 1; #30; button2 = 0;

        wait_for_state(5'd16);
        #10;
        $display("  Candidate 2 count: ACC=%0d (expected 1)", alu_acc_val);

        wait_for_state(5'd14);

        // =============================================
        // TEST 9: Wrong admin password
        // =============================================
        // Go back to IDLE first
        // Force back to IDLE by resetting
        force DUT.CU.state = 5'd0;
        @(posedge clock);
        release DUT.CU.state;
        #20;

        $display("\n--- TEST 9: Wrong admin password (1111) ---");
        switches = 16'h1111;
        #20;
        inject_btnc;

        wait_for_state(5'd21); // S_ERROR
        $display("  PASS: Wrong password rejected → ERROR state.");

        wait_for_state(5'd0);

        // =============================================
        // FINAL SUMMARY
        // =============================================
        #100;
        $display("\n==============================================");
        $display("  FINAL MEMORY STATE:");
        $display("    MEM[0] Cand1 votes: %0d (expected 2)", DUT.MEM.mem[0]);
        $display("    MEM[1] Cand2 votes: %0d (expected 1)", DUT.MEM.mem[1]);
        $display("    MEM[2] Cand3 votes: %0d (expected 0)", DUT.MEM.mem[2]);
        $display("    MEM[3] Cand4 votes: %0d (expected 0)", DUT.MEM.mem[3]);
        $display("    MEM[4] Admin PW   : %h (expected 2580)", DUT.MEM.mem[4]);
        $display("    MEM[16] NID 0037  : %h (bit16 voted=%b)", DUT.MEM.mem[16], DUT.MEM.mem[16][16]);
        $display("    MEM[17] NID 0097  : %h (bit16 voted=%b)", DUT.MEM.mem[17], DUT.MEM.mem[17][16]);
        $display("    MEM[18] NID 0106  : %h (bit16 voted=%b)", DUT.MEM.mem[18], DUT.MEM.mem[18][16]);
        $display("==============================================");
        $display("  ALL TESTS COMPLETE");
        $display("==============================================");
        $finish;
    end

    // Watchdog
    initial begin
        #2000000;
        $display("*** WATCHDOG: Sim timed out at %0t ***", $time);
        $finish;
    end

endmodule
