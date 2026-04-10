`timescale 1ns / 1ps

// Memory Unit — BRAM-based storage (512 x 32-bit)
// Pre-loaded from nid_table.hex via $readmemh
// Memory map:
//   0x000–0x003 : Candidate 1–4 vote counts
//   0x004       : Admin password (BCD in [15:0])
//   0x005       : Election status flags
//   0x006–0x00F : Reserved
//   0x010–0x10F : NID table (256 entries, BCD in [15:0], voted flag in [16])
//   0x110–0x1FF : Reserved
module memoryUnit(
    input clk,
    input reset,
    input [8:0] addr,           // 9-bit address (0–511)
    input wr_en,                // Write enable
    input [31:0] data_in,       // Write data
    output reg [31:0] data_out  // Read data (1-cycle latency)
);

    // Infer Block RAM — 512 x 32-bit
    (* ram_style = "block" *) reg [31:0] mem [0:511];

    // Load initial contents from hex file at synthesis / simulation time
    initial begin
        $readmemh("nid_table.hex", mem);
    end

    // Synchronous read/write (single-port BRAM, read-first mode)
    always @(posedge clk) begin
        if (wr_en)
            mem[addr] <= data_in;
        data_out <= mem[addr];
    end

endmodule
