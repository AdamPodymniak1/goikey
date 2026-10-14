`default_nettype none
// Polynomial memory: 26 slots x 256 coefficients x 32 bit (block RAM), 1 write + 1 read port, synchronous read.
module pq_pm #(parameter NSLOT = 26)(
    input  wire        clk,
    input  wire        we,
    input  wire [13:0] wa,
    input  wire [31:0] wd,
    input  wire [13:0] ra,
    output reg  [31:0] rq
);
(* ram_style="block" *) reg [31:0] mem [0:NSLOT*256-1];
always @(posedge clk) begin
    if (we) mem[wa] <= wd;
    rq <= mem[ra];
end
endmodule
`default_nettype wire
