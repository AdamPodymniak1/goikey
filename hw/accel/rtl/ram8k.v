`default_nettype none
// 8 KiB simple dual-port RAM, synchronous read (infers Gowin block RAM).
module ram8k (
    input  wire clk,
    input  wire we, input wire [12:0] wa, input wire [7:0] wd,
    input  wire [12:0] ra, output reg [7:0] rq
);
reg [7:0] mem [0:8191];
always @(posedge clk) begin
    if (we) mem[wa] <= wd;
    rq <= mem[ra];
end
endmodule
`default_nettype wire
