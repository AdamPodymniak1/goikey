`default_nettype none
// Command processor for the asymmetric profile: the whole command layer is microcode running on
// ecc_seq (see ref/ecc_asm.py); this wrapper only maps the command byte to an entry point. The SHA-512 unit is the shared
// sha2_unit at the top level.
//
//  0x01 PING | 0x02 UID | 0x03 RAND(32)
//  0x30 P256_GEN -> blob(64)|pub(64)      0x31 P256_PUB blob -> pub(64)
//  0x32 P256_SIGN blob|digest(32) -> r|s  0x33 P256_ECDH blob|pub(64) -> x(32)
//  0x34 P256_VERIFY digest|r|s|X|Y -> status      0x35 P256_WRAP raw(32) -> blob
//  0x40 ED_GEN -> blob(64)|pub(32)        0x41 ED_PUB blob -> pub     0x42 ED_SIGN blob|msg -> sig(64)
//  0x43 ED_WRAP seed(32) -> blob          0x50 SHA512 data -> digest(64)
// Wrapped key blob: nonce[16] | ct[32] | tag[16] = secret ^ HMAC-SHA512(MASTER,'E'|nonce)[0:32],
// tag = HMAC-SHA512(MASTER,'M'|nonce|ct)[0:16]   (MASTER is baked into the constant ROM at build time).
// status: 0 OK 1 BAD_CMD 2 BAD_LEN 3 BAD_CRC 4 AUTH_FAIL 5 ERR 6 BAD_PARAM
module ecc_cmd #(parameter [127:0] UID = 128'h0)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         go,
    input  wire [7:0]   cmd,
    input  wire [15:0]  len,
    output wire [12:0]  mem_a,
    input  wire [7:0]   mem_q,
    output wire         tx_we,
    output wire [12:0]  tx_wa,
    output wire [7:0]   tx_wd,
    output reg          done,
    output reg  [7:0]   status,
    output reg  [15:0]  tx_len,
    output wire         busy,
    input  wire         trng_valid,
    input  wire [31:0]  trng_data,
    // shared SHA-2 unit (SHA-512 mode)
    output wire         h5_begin, output wire h5_in_valid, output wire [7:0] h5_in_byte, input wire h5_in_ready,
    output wire         h5_end, input wire h5_done, output wire [2:0] h5_ra, input wire [63:0] h5_q,
    // shared bignum engine
    output wire         e_start, output wire [3:0] e_op, output wire [6:0] e_d, e_a, e_b, output wire [1:0] e_msel,
    input  wire         e_done, input wire e_lt,
    output wire [10:0]  x_ra, output wire x_we, output wire [10:0] x_wa, output wire [15:0] x_wd, input wire [15:0] x_rq
);
`include "ecc_cmdtab.vh"
reg [15:0] len_r;
reg        bad;
wire [11:0] ent = cmd_entry(cmd);
wire        s_busy, s_done; wire [7:0] f_status; wire [15:0] f_len;

ecc_seq #(.UID(UID)) seq (.clk(clk), .rst_n(rst_n),
    .h_we(1'b0), .h_wreg(7'd0), .h_wword(4'd0), .h_wdata(16'd0), .h_rreg(7'd0), .h_rword(4'd0), .h_q(),
    .h_go(go && ent[11]), .h_pc(ent[10:0]), .h_busy(s_busy), .h_done(s_done), .h_flag(),
    .plen(go ? len : len_r), .rx_a(mem_a), .rx_q(mem_q), .tx_we(tx_we), .tx_wa(tx_wa), .tx_wd(tx_wd),
    .f_status(f_status), .f_len(f_len), .trng_valid(trng_valid), .trng_data(trng_data),
    .h5_begin(h5_begin), .h5_in_valid(h5_in_valid), .h5_in_byte(h5_in_byte), .h5_in_ready(h5_in_ready),
    .h5_end(h5_end), .h5_done(h5_done), .h5_ra(h5_ra), .h5_q(h5_q),
    .e_start(e_start), .e_op(e_op), .e_d(e_d), .e_a(e_a), .e_b(e_b), .e_msel(e_msel), .e_done(e_done), .e_lt(e_lt),
    .x_ra(x_ra), .x_we(x_we), .x_wa(x_wa), .x_wd(x_wd), .x_rq(x_rq));

assign busy = s_busy | bad;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin done <= 1'b0; bad <= 1'b0; status <= 8'd0; tx_len <= 16'd0; len_r <= 16'd0; end
    else begin
        done <= 1'b0; bad <= 1'b0;
        if (go) len_r <= len;
        if (go && !ent[11]) bad <= 1'b1;                       // unknown command
        if (bad)    begin done <= 1'b1; status <= 8'd1; tx_len <= 16'd0; end
        if (s_done) begin done <= 1'b1; status <= f_status; tx_len <= f_len; end
    end
end
endmodule
`default_nettype wire
