`default_nettype none
// Pipelined Montgomery multiply for ML-DSA: r = montgomery_reduce((int64)a * b)   (q = 8380417, QINV = 58728449)
// latency 4 clocks, one result per clock.
module pq_mont (
    input  wire               clk,
    input  wire               in_v,
    input  wire signed [31:0] a,
    input  wire signed [31:0] b,
    output reg                out_v,
    output reg  signed [31:0] r
);
localparam signed [31:0] Q = 32'sd8380417;
reg v1, v2, v3;
reg signed [63:0] p1, p2, p3, m3;
reg [31:0] t2;
always @(posedge clk) begin
    v1 <= in_v;  p1 <= a * b;                                           // stage 1: full product
    v2 <= v1;    p2 <= p1; t2 <= p1[31:0] * 32'd58728449;               // stage 2: t = (int32)(p * QINV)
    v3 <= v2;    m3 <= $signed(t2) * Q; p3 <= p2;                       // stage 3: t * q
    out_v <= v3; r <= (p3 - m3) >>> 32;                                 // stage 4: (p - t*q) >> 32
end
endmodule
`default_nettype wire
