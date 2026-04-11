`timescale 1ns / 1ps

// Voting Timer — 10-minute election countdown
// Counts seconds and minutes using cascaded counters (no hardware division)
// Admin can start and reset the timer
module votingTimer #(
    parameter ONE_SEC = 100_000_000,  // 1 second at 100 MHz (override for sim)
    parameter ELECTION_MINS = 10      // Election duration in minutes
)(
    input clk,
    input reset,
    input timer_start,          // Pulse to start election
    input timer_reset,          // Pulse to reset (admin, new election)
    output voting_active,       // HIGH while voting window is open
    output [3:0] mins_remaining // Countdown: 10 → 0
);

    // Internal state
    reg active;
    reg [26:0] sec_counter;    // Counts clock cycles within 1 second
    reg [5:0]  sec_in_min;     // 0–59: seconds within current minute
    reg [3:0]  mins_elapsed;   // 0–ELECTION_MINS

    wire voting_expired = (mins_elapsed >= ELECTION_MINS);

    assign voting_active  = active;
    assign mins_remaining = (ELECTION_MINS > mins_elapsed) ?
                            (ELECTION_MINS[3:0] - mins_elapsed) : 4'd0;

    always @(posedge clk) begin
        if (reset) begin
            active       <= 1'b0;
            sec_counter  <= 27'd0;
            sec_in_min   <= 6'd0;
            mins_elapsed <= 4'd0;
        end
        else if (timer_reset) begin
            // Reset counters; if timer_start is also asserted, start immediately
            sec_counter  <= 27'd0;
            sec_in_min   <= 6'd0;
            mins_elapsed <= 4'd0;
            active       <= timer_start ? 1'b1 : 1'b0;
        end
        else if (timer_start && !active) begin
            // Start the election
            active <= 1'b1;
        end
        else if (active) begin
            if (voting_expired) begin
                // Time's up
                active <= 1'b0;
            end
            else if (sec_counter == ONE_SEC - 1) begin
                sec_counter <= 27'd0;
                if (sec_in_min == 6'd59) begin
                    sec_in_min   <= 6'd0;
                    mins_elapsed <= mins_elapsed + 1;
                end
                else begin
                    sec_in_min <= sec_in_min + 1;
                end
            end
            else begin
                sec_counter <= sec_counter + 1;
            end
        end
    end

endmodule
