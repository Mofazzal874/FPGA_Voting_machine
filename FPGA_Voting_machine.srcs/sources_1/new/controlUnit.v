`timescale 1ns / 1ps

// Control Unit — Main FSM (Moore machine)
// Orchestrates the entire voting lifecycle:
//   IDLE → VOTER_AUTH → VOTE → RECORD → CONFIRM → IDLE
//   IDLE → ADMIN_LOGIN → RESULT_DISPLAY → (optional reset) → IDLE
//
// Uses a generic WAIT_FE state with a return-state register to avoid
// duplicating wait logic for every FEU operation.
module controlUnit #(
    parameter CONFIRM_CYCLES = 100_000_000,  // 1 sec LED flash (override for sim)
    parameter ERROR_CYCLES   = 200_000_000   // 2 sec error display
)(
    input clk,
    input reset,

    // ---- Switches and buttons ----
    input [15:0] switches,     // SW15..SW0 (NID / admin password)
    input        btnc_pulse,   // Single-cycle pulse from debounced BTNC
    input        valid_vote_1, // From buttonControl (1-sec hold, for voting)
    input        valid_vote_2,
    input        valid_vote_3,
    input        valid_vote_4,
    input        button1_raw,  // Raw button inputs (for result display, no hold needed)
    input        button2_raw,
    input        button3_raw,
    input        button4_raw,

    // ---- Timer interface ----
    input        voting_active,
    output reg   timer_start,
    output reg   timer_reset,

    // ---- Fetch-Execute Unit interface ----
    output reg        fe_start,
    output reg [2:0]  fe_op,
    output reg [8:0]  fe_addr,
    output reg [31:0] fe_write_data,
    output reg [15:0] fe_scan_target,
    output reg [8:0]  fe_scan_end,
    input             fe_done,
    input             fe_match,
    input  [8:0]      fe_match_addr,
    input  [31:0]     fe_ac,         // ALU accumulator (current AC)

    // ---- Display outputs ----
    output reg [15:0] display_value, // Value to show on 7-seg
    output reg [2:0]  display_mode,  // 0=hex, 1=donE, 2=Err, 3=vote, 4=idle
    output reg [15:0] led_out,       // LED outputs
    output reg        vote_enable    // HIGH when candidate buttons should work
);

    // =========================================================
    // FEU operation codes (must match fetchExecuteUnit.v)
    // =========================================================
    localparam FE_OP_NOP      = 3'b000;
    localparam FE_OP_READ     = 3'b001;
    localparam FE_OP_WRITE    = 3'b010;
    localparam FE_OP_WRITE_AC = 3'b011;
    localparam FE_OP_SCAN     = 3'b100;
    localparam FE_OP_INC      = 3'b101;
    localparam FE_OP_OR_ACC   = 3'b110;

    // =========================================================
    // Memory addresses
    // =========================================================
    localparam ADDR_CAND1     = 9'h000;
    localparam ADDR_CAND4     = 9'h003;
    localparam ADDR_ADMIN_PW  = 9'h004;
    localparam ADDR_NID_START = 9'h010;
    localparam ADDR_NID_END   = 9'h10F;

    // =========================================================
    // Display modes (must match sevenSegDisplay.v)
    // =========================================================
    localparam DISP_HEX  = 3'd0;  // Show display_value as 4 hex digits
    localparam DISP_DONE = 3'd1;  // Show "donE"
    localparam DISP_ERR  = 3'd2;  // Show "Err "
    localparam DISP_VOTE = 3'd3;  // Show "uotE"
    localparam DISP_PASS = 3'd4;  // Show "PASS"

    // =========================================================
    // FSM States
    // =========================================================
    localparam S_IDLE              = 5'd0;
    localparam S_VOTER_AUTH        = 5'd1;   // Trigger NID SCAN
    localparam S_WAIT_FE           = 5'd2;   // Generic wait for FEU done
    localparam S_AUTH_RESULT       = 5'd3;   // Check scan result
    localparam S_VOTE_ACTIVE       = 5'd4;   // Wait for candidate button
    localparam S_RV_READ           = 5'd5;   // Read vote count
    localparam S_RV_INC            = 5'd6;   // Increment AC
    localparam S_RV_WRITE          = 5'd7;   // Write vote count back
    localparam S_RV_FLAG_READ      = 5'd8;   // Read NID entry
    localparam S_RV_FLAG_OR        = 5'd9;   // Set voted flag (OR bit 16)
    localparam S_RV_FLAG_WRITE     = 5'd10;  // Write NID entry back
    localparam S_CONFIRM           = 5'd11;  // Flash LEDs
    localparam S_ADMIN_LOGIN       = 5'd12;  // Read admin password
    localparam S_ADMIN_RESULT      = 5'd13;  // Check password
    localparam S_RESULT_DISPLAY    = 5'd14;  // Show results (button-driven)
    localparam S_RESULT_READ       = 5'd15;  // Read candidate count
    localparam S_RESULT_SHOW       = 5'd16;  // Display count value
    localparam S_ADMIN_RESET       = 5'd17;  // Clear vote counts (loop)
    localparam S_ADMIN_RESET_FLAGS = 5'd18;  // Clear voted flags (loop)
    localparam S_ADMIN_RESET_FRD   = 5'd19;  // Read NID for flag clear
    localparam S_ADMIN_RESET_FWR   = 5'd20;  // Write cleared NID back
    localparam S_ERROR             = 5'd21;  // Show error message
    localparam S_TIMER_START       = 5'd22;  // Start timer after reset

    reg [4:0] state;
    reg [4:0] return_state;        // Where to go after WAIT_FE

    // =========================================================
    // Internal registers
    // =========================================================
    reg [8:0]  saved_match_addr;   // NID entry address that matched
    reg [1:0]  candidate_sel;      // Which candidate was voted for (0-3)
    reg [27:0] delay_counter;      // For timed states (CONFIRM, ERROR)
    reg [8:0]  reset_counter;      // For admin reset loop
    reg [15:0] saved_switches;     // Latch switch value on submit
    reg [15:0] result_value;       // Latched result for display

    // Comparator for admin password check
    wire admin_pw_match;
    comparator admin_cmp(
        .input_a(saved_switches),
        .input_b(fe_ac[15:0]),
        .match(admin_pw_match)
    );

    // =========================================================
    // FSM — Sequential
    // =========================================================
    always @(posedge clk) begin
        if (reset) begin
            state            <= S_IDLE;
            return_state     <= S_IDLE;
            saved_match_addr <= 9'd0;
            candidate_sel    <= 2'd0;
            delay_counter    <= 28'd0;
            reset_counter    <= 9'd0;
            saved_switches   <= 16'd0;
            result_value     <= 16'd0;
            timer_start      <= 1'b0;
            timer_reset      <= 1'b0;
        end
        else begin
            // Default: deassert one-shot signals
            timer_start <= 1'b0;
            timer_reset <= 1'b0;

            case (state)
                // =============================================
                // IDLE — waiting for user input
                // =============================================
                S_IDLE: begin
                    delay_counter <= 28'd0;
                    if (btnc_pulse) begin
                        saved_switches <= switches;
                        if (voting_active)
                            state <= S_VOTER_AUTH;
                        else
                            state <= S_ADMIN_LOGIN;
                    end
                end

                // =============================================
                // VOTER PATH
                // =============================================

                // Trigger NID table scan
                S_VOTER_AUTH: begin
                    // FEU SCAN driven combinationally
                    return_state <= S_AUTH_RESULT;
                    state        <= S_WAIT_FE;
                end

                // Generic wait for FEU completion
                S_WAIT_FE: begin
                    if (fe_done) begin
                        state <= return_state;
                    end
                end

                // Check SCAN result
                S_AUTH_RESULT: begin
                    if (fe_match) begin
                        saved_match_addr <= fe_match_addr;
                        // AC has the matched NID entry — check voted flag
                        if (fe_ac[16]) begin
                            // Already voted
                            state <= S_ERROR;
                        end
                        else begin
                            // Valid voter, not yet voted
                            state <= S_VOTE_ACTIVE;
                        end
                    end
                    else begin
                        // NID not found
                        state <= S_ERROR;
                    end
                end

                // Wait for candidate button press
                S_VOTE_ACTIVE: begin
                    if (valid_vote_1) begin
                        candidate_sel <= 2'd0;
                        state <= S_RV_READ;
                    end
                    else if (valid_vote_2) begin
                        candidate_sel <= 2'd1;
                        state <= S_RV_READ;
                    end
                    else if (valid_vote_3) begin
                        candidate_sel <= 2'd2;
                        state <= S_RV_READ;
                    end
                    else if (valid_vote_4) begin
                        candidate_sel <= 2'd3;
                        state <= S_RV_READ;
                    end
                end

                // Read current vote count for chosen candidate
                S_RV_READ: begin
                    return_state <= S_RV_INC;
                    state        <= S_WAIT_FE;
                end

                // Increment the vote count in AC
                S_RV_INC: begin
                    return_state <= S_RV_WRITE;
                    state        <= S_WAIT_FE;
                end

                // Write incremented count back to memory
                S_RV_WRITE: begin
                    return_state <= S_RV_FLAG_READ;
                    state        <= S_WAIT_FE;
                end

                // Read the NID entry to set voted flag
                S_RV_FLAG_READ: begin
                    return_state <= S_RV_FLAG_OR;
                    state        <= S_WAIT_FE;
                end

                // OR with 0x10000 to set bit 16 (voted flag)
                S_RV_FLAG_OR: begin
                    return_state <= S_RV_FLAG_WRITE;
                    state        <= S_WAIT_FE;
                end

                // Write the NID entry back with voted flag set
                S_RV_FLAG_WRITE: begin
                    return_state <= S_CONFIRM;
                    state        <= S_WAIT_FE;
                end

                // Flash LEDs for confirmation
                S_CONFIRM: begin
                    if (delay_counter >= CONFIRM_CYCLES) begin
                        delay_counter <= 28'd0;
                        state         <= S_IDLE;
                    end
                    else begin
                        delay_counter <= delay_counter + 1;
                    end
                end

                // =============================================
                // ADMIN PATH
                // =============================================

                // Read admin password from memory
                S_ADMIN_LOGIN: begin
                    return_state <= S_ADMIN_RESULT;
                    state        <= S_WAIT_FE;
                end

                // Compare password
                S_ADMIN_RESULT: begin
                    if (admin_pw_match) begin
                        state <= S_RESULT_DISPLAY;
                    end
                    else begin
                        state <= S_ERROR;
                    end
                end

                // Result display — wait for button presses (raw, no hold needed)
                S_RESULT_DISPLAY: begin
                    if (btnc_pulse) begin
                        // Admin wants to reset and start new election
                        reset_counter <= 9'd0;
                        state         <= S_ADMIN_RESET;
                    end
                    else if (button1_raw || button2_raw ||
                             button3_raw || button4_raw) begin
                        // Determine which candidate to display
                        if (button1_raw) candidate_sel <= 2'd0;
                        else if (button2_raw) candidate_sel <= 2'd1;
                        else if (button3_raw) candidate_sel <= 2'd2;
                        else candidate_sel <= 2'd3;
                        state <= S_RESULT_READ;
                    end
                end

                // Read candidate count from memory
                S_RESULT_READ: begin
                    return_state <= S_RESULT_SHOW;
                    state        <= S_WAIT_FE;
                end

                // Latch result and display it
                S_RESULT_SHOW: begin
                    result_value <= fe_ac[15:0];
                    state        <= S_RESULT_DISPLAY;
                end

                // =============================================
                // ADMIN RESET — clear vote counts
                // =============================================
                S_ADMIN_RESET: begin
                    if (reset_counter > ADDR_CAND4) begin
                        // Done clearing votes — now clear voted flags
                        reset_counter <= ADDR_NID_START;
                        state         <= S_ADMIN_RESET_FLAGS;
                    end
                    else begin
                        // Write 0 to vote count address, then increment
                        reset_counter <= reset_counter + 1;
                        return_state  <= S_ADMIN_RESET;
                        state         <= S_WAIT_FE;
                    end
                end

                // Clear voted flags — read each NID entry
                S_ADMIN_RESET_FLAGS: begin
                    if (reset_counter > ADDR_NID_END) begin
                        // All flags cleared — start timer
                        state <= S_TIMER_START;
                    end
                    else begin
                        // Read NID entry
                        return_state <= S_ADMIN_RESET_FRD;
                        state        <= S_WAIT_FE;
                    end
                end

                // Check if entry is non-zero (valid NID)
                S_ADMIN_RESET_FRD: begin
                    if (fe_ac[15:0] == 16'd0) begin
                        // Empty entry — skip to end
                        state <= S_TIMER_START;
                    end
                    else begin
                        // Write back with bit 16 cleared
                        return_state <= S_ADMIN_RESET_FWR;
                        state        <= S_WAIT_FE;
                    end
                end

                // After writing cleared entry, advance to next
                S_ADMIN_RESET_FWR: begin
                    reset_counter <= reset_counter + 1;
                    state         <= S_ADMIN_RESET_FLAGS;
                end

                // Start election timer
                S_TIMER_START: begin
                    timer_reset <= 1'b1;   // Reset timer first
                    timer_start <= 1'b1;   // Then start it
                    state       <= S_IDLE;
                end

                // =============================================
                // ERROR — display error for a fixed duration
                // =============================================
                S_ERROR: begin
                    if (delay_counter >= ERROR_CYCLES) begin
                        delay_counter <= 28'd0;
                        state         <= S_IDLE;
                    end
                    else begin
                        delay_counter <= delay_counter + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // =========================================================
    // Combinational outputs — FEU control signals
    // Only drive fe_start HIGH in states that trigger an FEU op
    // =========================================================
    always @(*) begin
        // Defaults
        fe_start       = 1'b0;
        fe_op          = FE_OP_NOP;
        fe_addr        = 9'd0;
        fe_write_data  = 32'd0;
        fe_scan_target = 16'd0;
        fe_scan_end    = 9'd0;
        vote_enable    = 1'b0;

        case (state)
            S_VOTER_AUTH: begin
                fe_start       = 1'b1;
                fe_op          = FE_OP_SCAN;
                fe_addr        = ADDR_NID_START;
                fe_scan_target = saved_switches;
                fe_scan_end    = ADDR_NID_END;
            end

            S_VOTE_ACTIVE: begin
                vote_enable = 1'b1;
            end

            S_RV_READ: begin
                fe_start = 1'b1;
                fe_op    = FE_OP_READ;
                fe_addr  = {7'd0, candidate_sel};  // addr 0-3
            end

            S_RV_INC: begin
                fe_start = 1'b1;
                fe_op    = FE_OP_INC;
            end

            S_RV_WRITE: begin
                fe_start = 1'b1;
                fe_op    = FE_OP_WRITE_AC;
                fe_addr  = {7'd0, candidate_sel};
            end

            S_RV_FLAG_READ: begin
                fe_start = 1'b1;
                fe_op    = FE_OP_READ;
                fe_addr  = saved_match_addr;
            end

            S_RV_FLAG_OR: begin
                fe_start      = 1'b1;
                fe_op         = FE_OP_OR_ACC;
                fe_write_data = 32'h00010000;  // Set bit 16
            end

            S_RV_FLAG_WRITE: begin
                fe_start = 1'b1;
                fe_op    = FE_OP_WRITE_AC;
                fe_addr  = saved_match_addr;
            end

            S_ADMIN_LOGIN: begin
                fe_start = 1'b1;
                fe_op    = FE_OP_READ;
                fe_addr  = ADDR_ADMIN_PW;
            end

            S_RESULT_READ: begin
                fe_start = 1'b1;
                fe_op    = FE_OP_READ;
                fe_addr  = {7'd0, candidate_sel};
            end

            S_ADMIN_RESET: begin
                if (reset_counter <= ADDR_CAND4) begin
                    fe_start      = 1'b1;
                    fe_op         = FE_OP_WRITE;
                    fe_addr       = reset_counter;
                    fe_write_data = 32'd0;
                end
            end

            S_ADMIN_RESET_FLAGS: begin
                if (reset_counter <= ADDR_NID_END) begin
                    fe_start = 1'b1;
                    fe_op    = FE_OP_READ;
                    fe_addr  = reset_counter;
                end
            end

            S_ADMIN_RESET_FRD: begin
                if (fe_ac[15:0] != 16'd0) begin
                    // Write back entry with bit 16 cleared
                    fe_start      = 1'b1;
                    fe_op         = FE_OP_WRITE;
                    fe_addr       = reset_counter;
                    fe_write_data = {15'd0, 1'b0, fe_ac[15:0]};
                end
            end

            default: ;
        endcase
    end

    // =========================================================
    // Combinational outputs — Display and LEDs
    // =========================================================
    always @(*) begin
        display_value = 16'd0;
        display_mode  = DISP_HEX;
        led_out       = 16'd0;

        case (state)
            S_IDLE: begin
                // Live preview of switch value
                display_value = switches;
                display_mode  = DISP_HEX;
                // LED15 shows voting status
                led_out = {voting_active, 15'd0};
            end

            S_VOTER_AUTH, S_WAIT_FE, S_AUTH_RESULT: begin
                display_value = saved_switches;
                display_mode  = DISP_HEX;
                led_out       = 16'h5555;  // Alternating pattern = busy
            end

            S_VOTE_ACTIVE: begin
                display_mode = DISP_VOTE;  // Show "uotE"
                led_out      = 16'h000F;   // Lower 4 LEDs on
            end

            S_RV_READ, S_RV_INC, S_RV_WRITE,
            S_RV_FLAG_READ, S_RV_FLAG_OR, S_RV_FLAG_WRITE: begin
                display_mode = DISP_VOTE;
                led_out      = 16'hAAAA;  // Recording pattern
            end

            S_CONFIRM: begin
                display_mode = DISP_PASS;  // Show "PASS"
                led_out      = 16'hFFFF;   // All LEDs on
            end

            S_ADMIN_LOGIN, S_ADMIN_RESULT: begin
                display_value = 16'hAAAA;
                display_mode  = DISP_HEX;
                led_out       = 16'h00FF;
            end

            S_RESULT_DISPLAY, S_RESULT_READ, S_RESULT_SHOW: begin
                display_value = result_value;
                display_mode  = DISP_HEX;
                led_out       = {result_value};
            end

            S_ADMIN_RESET, S_ADMIN_RESET_FLAGS,
            S_ADMIN_RESET_FRD, S_ADMIN_RESET_FWR, S_TIMER_START: begin
                display_mode = DISP_HEX;
                display_value = 16'h0000;
                led_out       = 16'hF0F0;  // Reset pattern
            end

            S_ERROR: begin
                display_mode = DISP_ERR;   // Show "Err "
                led_out      = 16'hF00F;   // Error pattern
            end

            default: begin
                display_value = 16'd0;
                display_mode  = DISP_HEX;
                led_out       = 16'd0;
            end
        endcase
    end

endmodule
