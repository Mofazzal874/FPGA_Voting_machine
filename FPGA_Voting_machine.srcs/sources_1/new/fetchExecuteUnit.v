`timescale 1ns / 1ps

// Fetch-Execute Unit (FEU)
// Implements the manual fetch-execute cycle for all memory operations:
//   t0 (FETCH1): MAR <- PC,  present address to memory
//   t1 (FETCH2): MBR <- M[MAR],  PC <- PC + 1
//   t2 (EXEC) : perform operation (LOAD into AC, STORE, compare, etc.)
//
// Registers: PC (Program Counter), MAR (Memory Address Register),
//            MBR (Memory Buffer Register)
// The Accumulator (AC) lives in the external ALU module.
//
// Operations (commanded by Control Unit):
//   READ     — read mem[addr] into AC via fetch cycle
//   WRITE    — write data to mem[addr]
//   WRITE_AC — write AC to mem[addr]
//   SCAN     — sequential NID table scan with subtractor comparison
//   INC      — AC <- AC + 1 (no memory access)
//   OR_ACC   — AC <- AC | data (no memory access)
module fetchExecuteUnit(
    input clk,
    input reset,

    // ---- Control Unit interface ----
    input            fe_start,       // Pulse to begin operation
    input  [2:0]     fe_op,          // Operation code
    input  [8:0]     fe_addr,        // Target address (loaded into PC)
    input  [31:0]    fe_write_data,  // Data for WRITE / OR_ACC operand
    input  [15:0]    fe_scan_target, // NID value to search for (SCAN)
    input  [8:0]     fe_scan_end,    // Last address to search (SCAN)
    output reg       fe_done,        // HIGH for 1 state when operation complete
    output reg       fe_match,       // SCAN result: 1 = found
    output reg [8:0] fe_match_addr,  // Address where SCAN found a match

    // ---- Memory interface ----
    output reg [8:0]  mem_addr,
    output reg        mem_wr_en,
    output reg [31:0] mem_data_out,
    input  [31:0]     mem_data_in,

    // ---- ALU interface ----
    output reg [2:0]  alu_op,
    output reg [31:0] alu_operand,
    input  [31:0]     alu_acc,       // Current accumulator value

    // ---- Debug / display outputs ----
    output [8:0]  debug_pc,
    output [8:0]  debug_mar,
    output [31:0] debug_mbr
);

    // =========================================================
    // Operation codes (directly from control unit's fe_op)
    // =========================================================
    localparam FE_OP_NOP      = 3'b000;
    localparam FE_OP_READ     = 3'b001;
    localparam FE_OP_WRITE    = 3'b010;
    localparam FE_OP_WRITE_AC = 3'b011;
    localparam FE_OP_SCAN     = 3'b100;
    localparam FE_OP_INC      = 3'b101;
    localparam FE_OP_OR_ACC   = 3'b110;

    // ALU operation codes (match ALU.v)
    localparam ALU_NOP  = 3'b000;
    localparam ALU_INC  = 3'b001;
    localparam ALU_LOAD = 3'b100;
    localparam ALU_OR   = 3'b101;

    // =========================================================
    // FSM states
    // =========================================================
    localparam S_IDLE       = 4'd0;
    localparam S_FETCH1     = 4'd1;   // MAR <- PC, present addr to memory
    localparam S_FETCH2     = 4'd2;   // MBR <- M[MAR], PC <- PC + 1
    localparam S_EXECUTE    = 4'd3;   // ALU op or memory write
    localparam S_DONE       = 4'd4;
    localparam S_SCAN_ADDR  = 4'd5;   // Present PC to memory for scan
    localparam S_SCAN_READ  = 4'd6;   // MBR <- M[PC], PC++
    localparam S_SCAN_CMP   = 4'd7;   // Compare MBR[15:0] vs target
    localparam S_SCAN_MATCH = 4'd8;   // Match found — load into AC

    reg [3:0] state;

    // =========================================================
    // Registers: PC, MAR, MBR
    // =========================================================
    reg [8:0]  pc;
    reg [8:0]  mar;
    reg [31:0] mbr;
    reg [2:0]  op_latch;   // Latched operation code

    assign debug_pc  = pc;
    assign debug_mar = mar;
    assign debug_mbr = mbr;

    // =========================================================
    // Comparator instance — subtractor-based NID match
    // =========================================================
    wire scan_match_wire;
    comparator scan_cmp(
        .input_a(mbr[15:0]),
        .input_b(fe_scan_target),
        .match(scan_match_wire)
    );

    // =========================================================
    // Combinational outputs: memory address, write enable, ALU op
    // These are driven based on current state to meet BRAM timing
    // =========================================================
    always @(*) begin
        // Defaults — no memory write, NOP ALU, address from MAR
        mem_addr     = mar;
        mem_wr_en    = 1'b0;
        mem_data_out = 32'd0;
        alu_op       = ALU_NOP;
        alu_operand  = 32'd0;
        fe_done      = 1'b0;

        case (state)
            S_FETCH1: begin
                // Drive address from PC directly for 1-cycle-early read
                mem_addr = pc;
            end

            S_EXECUTE: begin
                case (op_latch)
                    FE_OP_READ: begin
                        // Load MBR into AC via ALU
                        alu_op      = ALU_LOAD;
                        alu_operand = mbr;
                    end
                    FE_OP_WRITE: begin
                        // Write MBR to memory at MAR
                        mem_addr     = mar;
                        mem_wr_en    = 1'b1;
                        mem_data_out = mbr;
                    end
                    FE_OP_WRITE_AC: begin
                        // Write current AC to memory at MAR
                        mem_addr     = mar;
                        mem_wr_en    = 1'b1;
                        mem_data_out = alu_acc;
                    end
                    FE_OP_INC: begin
                        alu_op = ALU_INC;
                    end
                    FE_OP_OR_ACC: begin
                        alu_op      = ALU_OR;
                        alu_operand = mbr;  // mbr was loaded with fe_write_data
                    end
                    default: ;
                endcase
            end

            S_SCAN_ADDR: begin
                // Drive PC to memory for scan read
                mem_addr = pc;
            end

            S_SCAN_MATCH: begin
                // Load matched entry into AC
                alu_op      = ALU_LOAD;
                alu_operand = mbr;
            end

            S_DONE: begin
                fe_done = 1'b1;
            end

            default: ;
        endcase
    end

    // =========================================================
    // Sequential logic — state machine and register updates
    // =========================================================
    always @(posedge clk) begin
        if (reset) begin
            state        <= S_IDLE;
            pc           <= 9'd0;
            mar          <= 9'd0;
            mbr          <= 32'd0;
            op_latch     <= 3'd0;
            fe_match     <= 1'b0;
            fe_match_addr <= 9'd0;
        end
        else begin
            case (state)
                // -------------------------------------------------
                S_IDLE: begin
                    fe_match <= 1'b0;
                    if (fe_start) begin
                        op_latch <= fe_op;
                        case (fe_op)
                            FE_OP_READ, FE_OP_WRITE_AC: begin
                                // Need to fetch from memory
                                pc    <= fe_addr;
                                state <= S_FETCH1;
                            end
                            FE_OP_WRITE: begin
                                // Need to write data to memory
                                pc    <= fe_addr;
                                mbr   <= fe_write_data;
                                state <= S_FETCH1;
                            end
                            FE_OP_SCAN: begin
                                pc    <= fe_addr;
                                state <= S_SCAN_ADDR;
                            end
                            FE_OP_INC: begin
                                // No memory needed — go straight to execute
                                state <= S_EXECUTE;
                            end
                            FE_OP_OR_ACC: begin
                                // Load operand into MBR, go to execute
                                mbr   <= fe_write_data;
                                state <= S_EXECUTE;
                            end
                            default: begin
                                state <= S_IDLE;
                            end
                        endcase
                    end
                end

                // -------------------------------------------------
                // FETCH CYCLE: t0 — MAR <- PC
                S_FETCH1: begin
                    mar   <= pc;
                    // Memory address is driven combinationally from PC
                    // so data will be available next cycle
                    state <= S_FETCH2;
                end

                // FETCH CYCLE: t1 — MBR <- M[MAR], PC <- PC + 1
                S_FETCH2: begin
                    if (op_latch != FE_OP_WRITE) begin
                        // For READ and WRITE_AC: capture memory output
                        mbr <= mem_data_in;
                    end
                    // For WRITE: MBR already has fe_write_data
                    pc    <= pc + 1;
                    state <= S_EXECUTE;
                end

                // EXECUTE: perform the operation
                S_EXECUTE: begin
                    // ALU ops and memory writes happen combinationally above
                    // This state lasts 1 cycle for the ALU to latch / BRAM to write
                    state <= S_DONE;
                end

                // DONE: signal completion
                S_DONE: begin
                    // fe_done driven combinationally
                    // Stay here 1 cycle, then return to IDLE
                    state <= S_IDLE;
                end

                // -------------------------------------------------
                // SCAN: t0 — present PC to memory
                S_SCAN_ADDR: begin
                    mar   <= pc;
                    state <= S_SCAN_READ;
                end

                // SCAN: t1 — MBR <- M[MAR], PC <- PC + 1
                S_SCAN_READ: begin
                    mbr   <= mem_data_in;
                    pc    <= pc + 1;
                    state <= S_SCAN_CMP;
                end

                // SCAN: t2 — compare MBR[15:0] with target
                S_SCAN_CMP: begin
                    if (scan_match_wire) begin
                        // NID matched — load entry into AC
                        fe_match      <= 1'b1;
                        fe_match_addr <= mar;
                        state         <= S_SCAN_MATCH;
                    end
                    else if (mbr[15:0] == 16'd0) begin
                        // Empty entry = end of table, no match
                        fe_match <= 1'b0;
                        state    <= S_DONE;
                    end
                    else if (pc > fe_scan_end + 1) begin
                        // Reached end of scan range, no match
                        fe_match <= 1'b0;
                        state    <= S_DONE;
                    end
                    else begin
                        // No match yet — continue scanning
                        state <= S_SCAN_ADDR;
                    end
                end

                // SCAN match: load matched entry into AC (1 cycle for ALU)
                S_SCAN_MATCH: begin
                    // ALU LOAD driven combinationally above
                    state <= S_DONE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
