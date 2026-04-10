`timescale 1ns / 1ps

// Top Module — FPGA Voting Machine (Phase 3)
// Integrates: buttonControl, votingTimer, fetchExecuteUnit,
//             memoryUnit, ALU, comparator, controlUnit, sevenSegDisplay
module votingMachine #(
    parameter HOLD_THRESHOLD = 100_000_000,  // 1 sec button hold
    parameter ONE_SEC        = 100_000_000,  // 1 sec for timer
    parameter CONFIRM_CYCLES = 100_000_000,  // 1 sec confirm flash
    parameter ERROR_CYCLES   = 200_000_000   // 2 sec error display
)(
    input         clock,
    input         button1,    // BTNU — Candidate 1
    input         button2,    // BTNL — Candidate 2
    input         button3,    // BTNR — Candidate 3
    input         button4,    // BTND — Candidate 4
    input         btnc,       // BTNC — Submit / Confirm
    input  [15:0] switches,   // SW15..SW0 — NID / password entry
    output [15:0] led,        // LED15..LED0
    output [6:0]  seg,        // 7-seg cathodes (active-low)
    output        dp,         // Decimal point (active-low)
    output [3:0]  an          // 7-seg anodes (active-low)
);

    // =============================================
    // Power-on reset generator (15 cycles)
    // =============================================
    reg [3:0] por_counter = 4'd0;
    wire system_reset = (por_counter != 4'hF);
    always @(posedge clock) begin
        if (por_counter != 4'hF)
            por_counter <= por_counter + 1;
    end

    // =============================================
    // BTNC debounce + edge detect (~20 ms debounce)
    // =============================================
    reg [20:0] btnc_db_counter;
    reg        btnc_stable;
    reg        btnc_prev;
    wire       btnc_pulse = btnc_stable & ~btnc_prev;

    always @(posedge clock) begin
        if (system_reset) begin
            btnc_db_counter <= 21'd0;
            btnc_stable     <= 1'b0;
            btnc_prev       <= 1'b0;
        end
        else begin
            btnc_prev <= btnc_stable;
            if (btnc != btnc_stable) begin
                if (btnc_db_counter >= 21'd2_000_000)  // ~20 ms at 100 MHz
                    btnc_stable <= btnc;
                else
                    btnc_db_counter <= btnc_db_counter + 1;
            end
            else begin
                btnc_db_counter <= 21'd0;
            end
        end
    end

    // =============================================
    // Internal wires
    // =============================================
    wire valid_vote_1, valid_vote_2, valid_vote_3, valid_vote_4;
    wire vote_enable;

    // Timer signals
    wire voting_active;
    wire [3:0] mins_remaining;
    wire timer_start, timer_reset_sig;

    // FEU <-> Control Unit signals
    wire        fe_start, fe_done, fe_match;
    wire [2:0]  fe_op;
    wire [8:0]  fe_addr, fe_match_addr;
    wire [31:0] fe_write_data;
    wire [15:0] fe_scan_target;
    wire [8:0]  fe_scan_end;

    // FEU <-> Memory signals
    wire [8:0]  mem_addr;
    wire        mem_wr_en;
    wire [31:0] mem_data_to_mem, mem_data_from_mem;

    // FEU <-> ALU signals
    wire [2:0]  feu_alu_op;
    wire [31:0] feu_alu_operand;
    wire [31:0] alu_acc;
    wire        alu_overflow, alu_zero_flag;

    // FEU debug
    wire [8:0]  debug_pc, debug_mar;
    wire [31:0] debug_mbr;

    // Display signals
    wire [15:0] display_value;
    wire [2:0]  display_mode;
    wire [15:0] led_out;

    // =============================================
    // Button Control instances (1-second hold for candidate vote)
    // Only active when vote_enable is HIGH
    // =============================================
    buttonControl #(.HOLD_THRESHOLD(HOLD_THRESHOLD)) bc1(
        .clock(clock), .reset(system_reset),
        .enable(vote_enable),
        .button(button1), .valid_vote(valid_vote_1)
    );
    buttonControl #(.HOLD_THRESHOLD(HOLD_THRESHOLD)) bc2(
        .clock(clock), .reset(system_reset),
        .enable(vote_enable),
        .button(button2), .valid_vote(valid_vote_2)
    );
    buttonControl #(.HOLD_THRESHOLD(HOLD_THRESHOLD)) bc3(
        .clock(clock), .reset(system_reset),
        .enable(vote_enable),
        .button(button3), .valid_vote(valid_vote_3)
    );
    buttonControl #(.HOLD_THRESHOLD(HOLD_THRESHOLD)) bc4(
        .clock(clock), .reset(system_reset),
        .enable(vote_enable),
        .button(button4), .valid_vote(valid_vote_4)
    );

    // =============================================
    // Voting Timer (10-minute countdown)
    // =============================================
    votingTimer #(
        .ONE_SEC(ONE_SEC),
        .ELECTION_MINS(10)
    ) TIMER(
        .clk(clock), .reset(system_reset),
        .timer_start(timer_start),
        .timer_reset(timer_reset_sig),
        .voting_active(voting_active),
        .mins_remaining(mins_remaining)
    );

    // =============================================
    // Memory Unit (512 x 32-bit BRAM, loaded from hex)
    // =============================================
    memoryUnit MEM(
        .clk(clock), .reset(system_reset),
        .addr(mem_addr),
        .wr_en(mem_wr_en),
        .data_in(mem_data_to_mem),
        .data_out(mem_data_from_mem)
    );

    // =============================================
    // ALU (accumulator + arithmetic)
    // =============================================
    ALU ALU_INST(
        .clk(clock), .reset(system_reset),
        .alu_op(feu_alu_op),
        .operand(feu_alu_operand),
        .acc(alu_acc),
        .overflow(alu_overflow),
        .zero_flag(alu_zero_flag)
    );

    // =============================================
    // Fetch-Execute Unit
    // =============================================
    fetchExecuteUnit FEU(
        .clk(clock), .reset(system_reset),
        // Control Unit interface
        .fe_start(fe_start),
        .fe_op(fe_op),
        .fe_addr(fe_addr),
        .fe_write_data(fe_write_data),
        .fe_scan_target(fe_scan_target),
        .fe_scan_end(fe_scan_end),
        .fe_done(fe_done),
        .fe_match(fe_match),
        .fe_match_addr(fe_match_addr),
        // Memory interface
        .mem_addr(mem_addr),
        .mem_wr_en(mem_wr_en),
        .mem_data_out(mem_data_to_mem),
        .mem_data_in(mem_data_from_mem),
        // ALU interface
        .alu_op(feu_alu_op),
        .alu_operand(feu_alu_operand),
        .alu_acc(alu_acc),
        // Debug
        .debug_pc(debug_pc),
        .debug_mar(debug_mar),
        .debug_mbr(debug_mbr)
    );

    // =============================================
    // Control Unit (main FSM)
    // =============================================
    controlUnit #(
        .CONFIRM_CYCLES(CONFIRM_CYCLES),
        .ERROR_CYCLES(ERROR_CYCLES)
    ) CU(
        .clk(clock), .reset(system_reset),
        // Switches and buttons
        .switches(switches),
        .btnc_pulse(btnc_pulse),
        .valid_vote_1(valid_vote_1),
        .valid_vote_2(valid_vote_2),
        .valid_vote_3(valid_vote_3),
        .valid_vote_4(valid_vote_4),
        .button1_raw(button1),
        .button2_raw(button2),
        .button3_raw(button3),
        .button4_raw(button4),
        // Timer
        .voting_active(voting_active),
        .timer_start(timer_start),
        .timer_reset(timer_reset_sig),
        // FEU
        .fe_start(fe_start),
        .fe_op(fe_op),
        .fe_addr(fe_addr),
        .fe_write_data(fe_write_data),
        .fe_scan_target(fe_scan_target),
        .fe_scan_end(fe_scan_end),
        .fe_done(fe_done),
        .fe_match(fe_match),
        .fe_match_addr(fe_match_addr),
        .fe_ac(alu_acc),
        // Display
        .display_value(display_value),
        .display_mode(display_mode),
        .led_out(led_out),
        .vote_enable(vote_enable)
    );

    // =============================================
    // 7-Segment Display
    // =============================================
    sevenSegDisplay SSD(
        .clock(clock), .reset(system_reset),
        .display_value(display_value),
        .display_mode(display_mode),
        .seg(seg), .dp(dp), .an(an)
    );

    // =============================================
    // LED output
    // =============================================
    assign led = led_out;

endmodule
