`default_nettype none
// ML-DSA-44/65/87 engine (keygen / sign with device-wrapped keys). The command byte selects a microcode entry:
//   0x01 ping | 0x02 UID | 0x03 32 random bytes
//   0x60+p / 0x64+p : keygen (TRNG seed / seed given in the payload)       p = 0,1,2 -> ML-DSA-44,65,87
//   0x68+p / 0x6C+p : sign  (TRNG hedge / rnd given in the payload)        payload: blob | rnd[32] | message
//   0x70 RSA-2048 keygen -> blob(672)|n(256) | 0x71 public modulus(blob) | 0x72 RS256 sign(blob | sha256 digest) -> 256-byte signature
// Responses: keygen -> blob (nonce16|ct|tag16) | public key;  sign -> signature.   Status 4 = bad blob tag, 2 = bad length.
module pq_core #(parameter [255:0] MASTER = 256'h0, parameter [127:0] UID = 128'h0)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         go,
    input  wire [7:0]   cmd,
    input  wire [15:0]  len,
    output reg          done,
    output reg  [7:0]   status,
    output reg  [15:0]  tx_len,
    output wire         busy,
    // payload RAM (RX): read, and in-place write (decrypting the key)
    output wire [12:0]  rx_ra, input wire [7:0] rx_rq,
    output wire         rx_we, output wire [12:0] rx_wa, output wire [7:0] rx_wd,
    // response RAM (TX): write, and read (hashing the public key)
    output wire         tx_we, output wire [12:0] tx_wa, output wire [7:0] tx_wd,
    output wire [12:0]  tx_ra, input wire [7:0] tx_rq,
    input  wire         trng_valid,
    input  wire [31:0]  trng_data,
    // shared bignum engine (RSA): command side and byte-bus side
    output wire         r_start_o, output wire [7:0] r_op_o, output wire [5:0] r_a_o, r_b_o, r_c_o, r_d_o, output wire [31:0] r_imm_o,
    input  wire         r_done_i, input wire r_flag_i, input wire r_bus_i,
    input  wire         rb_we_i, input wire [1:0] rb_ws_i, input wire [12:0] rb_wa_i, input wire [7:0] rb_wd_i,
    input  wire [1:0]   rb_rs_i, input wire [12:0] rb_ra_i,
    output wire [7:0]   br_data_o
);
`include "pq_cmdtab.vh"
// ---------------- sequencer ----------------
wire        p_start, s_start, k_start, b_start, sh_init, sh_mode256, sh_fin;
wire [4:0]  p_op; wire [5:0] p_sa, p_sb, p_sc; wire [31:0] p_bound;
wire        p_done, p_flag, p_busy; wire [8:0] p_hints;
wire [2:0]  s_mode; wire [5:0] s_dst; wire [7:0] s_tau; wire s_done, s_busy;
wire [3:0]  k_op; wire [5:0] k_slot, k_hidx; wire [1:0] k_space; wire [12:0] k_base; wire k_eta4, k_g1sel, k_g2sel, k_hkclr; wire [7:0] k_omega; wire k_done, k_over, k_busy;
wire [3:0]  b_op; wire [1:0] b_sp1, b_sp2; wire [12:0] b_off1, b_len, b_off2; wire [15:0] b_imm; wire b_flagclr, b_done, b_diff, b_busy;
wire        sh_ready, g2sel;
wire        r_start, r_done, r_flag, r_bus; wire [7:0] r_op; wire [5:0] r_a, r_b, r_c, r_d; wire [31:0] r_imm;
assign r_start_o = r_start; assign r_op_o = r_op; assign r_a_o = r_a; assign r_b_o = r_b; assign r_c_o = r_c; assign r_d_o = r_d; assign r_imm_o = r_imm;
assign r_done = r_done_i; assign r_flag = r_flag_i; assign r_bus = r_bus_i;
wire        q_done, q_busy; wire [7:0] q_status; wire [15:0] q_len;
wire [13:0] ent = pq_entry(cmd);
reg         bad; reg [15:0] len_r;

pq_seq seq (.clk(clk), .rst_n(rst_n), .go(go && ent[13]), .entry(ent[12:0]), .plen(go ? len : len_r),
    .done(q_done), .status(q_status), .tx_len(q_len), .busy(q_busy), .g2sel_o(g2sel),
    .p_start(p_start), .p_op(p_op), .p_sa(p_sa), .p_sb(p_sb), .p_sc(p_sc), .p_bound(p_bound), .p_done(p_done), .p_flag(p_flag), .p_hints(p_hints),
    .s_start(s_start), .s_mode(s_mode), .s_dst(s_dst), .s_tau(s_tau), .s_done(s_done),
    .k_start(k_start), .k_op(k_op), .k_slot(k_slot), .k_space(k_space), .k_base(k_base), .k_eta4(k_eta4), .k_g1sel(k_g1sel),
    .k_g2sel(k_g2sel), .k_omega(k_omega), .k_hidx(k_hidx), .k_hkclr(k_hkclr), .k_done(k_done), .k_over(k_over),
    .b_start(b_start), .b_op(b_op), .b_sp1(b_sp1), .b_off1(b_off1), .b_len(b_len), .b_sp2(b_sp2), .b_off2(b_off2), .b_imm(b_imm),
    .b_flagclr(b_flagclr), .b_done(b_done), .b_diff(b_diff),
    .r_start(r_start), .r_op(r_op), .r_a(r_a), .r_b(r_b), .r_c(r_c), .r_d(r_d), .r_imm(r_imm), .r_done(r_done), .r_flag(r_flag),
    .sh_init(sh_init), .sh_mode256(sh_mode256), .sh_fin(sh_fin), .sh_ready(sh_ready));
assign busy = q_busy | bad;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin done <= 0; bad <= 0; status <= 0; tx_len <= 0; len_r <= 0; end
    else begin
        done <= 0; bad <= 0;
        if (go) len_r <= len;
        if (go && !ent[13]) bad <= 1;
        if (bad)    begin done <= 1; status <= 8'd1; tx_len <= 16'd0; end
        if (q_done) begin done <= 1; status <= q_status; tx_len <= q_len; end
    end
end

// ---------------- polynomial memory and units ----------------
wire [13:0] p_ra, p_wa, s_ra, s_wa, k_ra, k_wa, pm_ra, pm_wa; wire p_we, s_we, k_we, pm_we; wire [31:0] p_wd, s_wd, k_wd, pm_wd, pm_rq;
pq_pm pm (.clk(clk), .we(pm_we), .wa(pm_wa), .wd(pm_wd), .ra(pm_ra), .rq(pm_rq));
assign pm_we = p_we | s_we | k_we;
assign pm_wa = p_we ? p_wa : s_we ? s_wa : k_wa;
assign pm_wd = p_we ? p_wd : s_we ? s_wd : k_wd;
assign pm_ra = p_busy ? p_ra : s_busy ? s_ra : k_ra;

pq_poly poly (.clk(clk), .rst_n(rst_n), .start(p_start), .op(p_op), .sa(p_sa), .sb(p_sb), .sc(p_sc), .g2sel(g2sel), .bound(p_bound),
    .busy(p_busy), .done(p_done), .flag_or(p_flag), .hint_cnt(p_hints), .ra(p_ra), .we(p_we), .wa(p_wa), .wd(p_wd), .rq(pm_rq));

// ---------------- SHAKE ----------------
wire        sh_in_valid, sh_out_ready, sh_idle, sh_take; wire [7:0] sh_in_byte, sh_out_byte;
wire        kp_sh_valid, bb_sh_valid, s_take, b_take; wire [7:0] kp_sh_byte, bb_sh_byte;
assign sh_in_valid = kp_sh_valid | bb_sh_valid;
assign sh_in_byte  = kp_sh_valid ? kp_sh_byte : bb_sh_byte;
assign sh_take     = s_take | b_take;
shake_unit sh (.clk(clk), .rst_n(rst_n), .init(sh_init), .mode(sh_mode256), .in_valid(sh_in_valid), .in_byte(sh_in_byte), .in_ready(sh_ready),
               .finalize(sh_fin), .out_take(sh_take), .out_ready(sh_out_ready), .out_byte(sh_out_byte), .idle(sh_idle));

pq_smp smp (.clk(clk), .rst_n(rst_n), .start(s_start), .mode(s_mode), .dst(s_dst), .tau(s_tau), .busy(s_busy), .done(s_done),
    .out_ready(sh_out_ready), .out_byte(sh_out_byte), .out_take(s_take), .ra(s_ra), .we(s_we), .wa(s_wa), .wd(s_wd), .rq(pm_rq));

// ---------------- byte bus ----------------
wire        kb_we, bb_we; wire [1:0] kb_ws, bb_ws, kb_rs, bb_rs; wire [12:0] kb_wa, bb_wa, kb_ra, bb_ra; wire [7:0] kb_wd, bb_wd; wire [7:0] br_data;
pq_pack pack (.clk(clk), .rst_n(rst_n), .start(k_start), .op(k_op), .slot(k_slot), .space(k_space), .base(k_base), .eta4(k_eta4), .g1sel(k_g1sel),
    .g2sel(k_g2sel), .omega(k_omega), .hidx(k_hidx), .hk_clr(k_hkclr), .busy(k_busy), .done(k_done), .hk_over(k_over),
    .ra(k_ra), .we(k_we), .wa(k_wa), .wd(k_wd), .rq(pm_rq),
    .bw_en(kb_we), .bw_space(kb_ws), .bw_addr(kb_wa), .bw_data(kb_wd), .br_space(kb_rs), .br_addr(kb_ra), .br_data(br_data),
    .sh_in_valid(kp_sh_valid), .sh_in_byte(kp_sh_byte), .sh_in_ready(sh_ready));
pq_bytes #(.MASTER(MASTER), .UID(UID)) bytes (.clk(clk), .rst_n(rst_n), .start(b_start), .op(b_op), .sp1(b_sp1), .off1(b_off1), .len(b_len),
    .sp2(b_sp2), .off2(b_off2), .imm(b_imm), .plen(go ? len : len_r), .busy(b_busy), .done(b_done), .flag_diff(b_diff), .flag_clr(b_flagclr),
    .bw_en(bb_we), .bw_space(bb_ws), .bw_addr(bb_wa), .bw_data(bb_wd), .br_space(bb_rs), .br_addr(bb_ra), .br_data(br_data),
    .sh_in_valid(bb_sh_valid), .sh_in_byte(bb_sh_byte), .sh_in_ready(sh_ready), .out_ready(sh_out_ready), .out_byte(sh_out_byte), .out_take(b_take),
    .trng_valid(trng_valid), .trng_data(trng_data));

wire        rb_we = rb_we_i; wire [1:0] rb_ws = rb_ws_i, rb_rs = rb_rs_i; wire [12:0] rb_wa = rb_wa_i, rb_ra = rb_ra_i; wire [7:0] rb_wd = rb_wd_i;
wire        bw_en = kb_we | bb_we | rb_we;
wire [1:0]  bw_space = kb_we ? kb_ws : rb_we ? rb_ws : bb_ws;
wire [12:0] bw_addr  = kb_we ? kb_wa : rb_we ? rb_wa : bb_wa;
wire [7:0]  bw_data  = kb_we ? kb_wd : rb_we ? rb_wd : bb_wd;
wire [1:0]  br_space = k_busy ? kb_rs : r_bus ? rb_rs : bb_rs;
wire [12:0] br_addr  = k_busy ? kb_ra : r_bus ? rb_ra : bb_ra;
reg  [1:0]  br_space_d; always @(posedge clk) br_space_d <= br_space;
(* ram_style="block" *) reg [7:0] sc [0:2047];
reg  [7:0]  sc_rq;
always @(posedge clk) begin
    if (bw_en && bw_space == 2'd2) sc[bw_addr[10:0]] <= bw_data;
    sc_rq <= sc[br_addr[10:0]];
end
assign br_data_o = br_data;
assign rx_ra = br_addr; assign tx_ra = br_addr;
assign rx_we = bw_en && bw_space == 2'd0; assign rx_wa = bw_addr; assign rx_wd = bw_data;
assign tx_we = bw_en && bw_space == 2'd1; assign tx_wa = bw_addr; assign tx_wd = bw_data;
assign br_data = (br_space_d == 2'd0) ? rx_rq : (br_space_d == 2'd1) ? tx_rq : sc_rq;
endmodule
`default_nettype wire
