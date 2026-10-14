`default_nettype none
// Root of Trust, accelerator edition: provisioned 128-bit UID + ring-oscillator TRNG.
// (The full hw/tro/root_of_trust.v additionally models key slots, counter and JTAG lock.)
// The TRNG source (trng_ring / trng_core) lives in hw/tro/root_of_trust.v.
module tro_lite (
    input  wire         clk,
    input  wire         rst_n,
    output wire [127:0] uid_o,
    output wire [31:0]  trng_o,
    output wire         trng_valid
);
`ifdef UID_VAL
localparam [127:0] UID = `UID_VAL;
`else
localparam [127:0] UID = 128'hA1B2C3D4_E5F60718_293A4B5C_6D7E8F00;
`endif
assign uid_o = UID;

wire raw;
`ifdef SIM_FAST_TRNG
reg [30:0] l = 31'h2468ace1;
always @(posedge clk) l <= {l[29:0], l[30] ^ l[27]};
assign raw = l[0] ^ l[13];
`else
trng_core u_core (.clk(clk), .rst_n(rst_n), .raw(raw));
`endif

// decimate x32, von Neumann debias, 32-bit words
reg [4:0] dc = 0; reg have = 0, first = 0; reg [31:0] q = 0; reg [4:0] n = 0; reg v = 0;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin dc<=0; have<=0; first<=0; q<=0; n<=0; v<=0; end
    else begin
        v <= 0; dc <= dc + 1;
        if (dc == 5'd31) begin
            if (!have) begin first <= raw; have <= 1; end
            else begin
                have <= 0;
                if (first != raw) begin
                    q <= {q[30:0], first}; n <= n + 1;
                    if (n == 5'd31) v <= 1;
                end
            end
        end
    end
end
assign trng_o = q; assign trng_valid = v;
endmodule
`default_nettype wire
