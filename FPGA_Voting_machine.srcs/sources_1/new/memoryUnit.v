`timescale 1ns / 1ps

// Memory Unit — BRAM-based vote counter storage
// Matches report Chapter 3 specification
// 64 x 32-bit words (inferred as Block RAM by Vivado)
// Addresses 0-3: candidate vote counters
// Addresses 4-63: reserved for voter ID hashes (future)
module memoryUnit(
    input clk,
    input reset,
    input [5:0] addr,       // 6-bit address (0-63)
    input wr_en,            // Write enable
    input [31:0] data_in,   // Write data
    output reg [31:0] data_out  // Read data (synchronous)
);

// Infer Block RAM — 64 x 32-bit
(* ram_style = "block" *) reg [31:0] mem [0:63];

// Initialize all memory to zero (loaded into FPGA bitstream)
integer i;
initial begin
    for (i = 0; i < 64; i = i + 1)
        mem[i] = 32'd0;
end

// Synchronous read/write (single-port BRAM pattern)
always @(posedge clk) begin
    if (wr_en)
        mem[addr] <= data_in;
    data_out <= mem[addr];
end

endmodule
