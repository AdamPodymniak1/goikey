`default_nettype none
// ---------------------------------------------------------------------------
//  cmd   payload                                          response
//  0x01  -                                                "TROACC01" + caps[4]
//  0x02  -                                                uid[16]
//  0x03  n[2 LE] (1..1024)                                n random bytes
//  0x10  data                                             sha256[32]
//  0x11  klen[1] key[klen<=64] data                       hmac_sha256[32]
//  0x12  iters[4 LE] dklen[2 LE] pwlen[1] pw[<=64] salt   pbkdf2_hmac_sha256[dklen<=1024]
//  0x20  key[32]                                          -            (AES-256 key)
//  0x21  mode[1] iv[16] aadlen[2 LE] dlen[2 LE] aad data [tag16 if mode==5]
//        mode 0/1 ECB enc/dec, 2/3 CBC enc/dec, 4/5 GCM enc/dec (12-byte IV = iv[0..11])
//                                                        data' (+tag16 for mode 4)
//  status: 0 OK 1 BAD_CMD 2 BAD_LEN 3 BAD_CRC 4 AUTH_FAIL 5 ERR 6 BAD_PARAM 7 NO_KEY
// HAS_INFO=0 drops 0x01-0x03 (builds where the PQ / ECC processor answers them).
// ---------------------------------------------------------------------------
module accel_cmd #(parameter [31:0] CAPS = 32'h0000_000F, parameter HAS_AES = 1, parameter HAS_INFO = 1)(
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
    input  wire [127:0] uid,
    // shared sha2_unit (the top level multiplexes it between command engines)
    output wire         h_begin_o, h_keydone_o, h_key_wr_o, h_in_valid_o, h_msg_end_o,
    output wire [1:0]   h_mode_o, output wire [31:0] h_iters_o, output wire [31:0] h_idx_o,
    output wire [7:0]   h_key_byte_o, output wire [7:0] h_in_byte_o,
    input  wire         h_in_ready, h_done_i,
    output reg  [2:0]   h_dgra_o, input wire [63:0] h_dgq_i,
    input  wire         trng_valid,
    input  wire [31:0]  trng_data
);
// ---------------- crypto units ----------------
reg         h_begin, h_keydone, h_msg_end;
reg  [1:0]  h_mode;
reg  [31:0] h_iters, h_idx;
assign h_begin_o = h_begin; assign h_keydone_o = h_keydone; assign h_msg_end_o = h_msg_end;
assign h_mode_o = h_mode; assign h_iters_o = h_iters; assign h_idx_o = h_idx;
wire h_done = h_done_i;

reg         a_key_start, a_op_start;
reg  [2:0]  a_mode;
reg  [15:0] a_aadlen, a_dlen;
wire        a_key_ready, a_done, a_busy, a_auth_fail, a_tx_we;
wire [12:0] a_rx_a, a_tx_wa; wire [7:0] a_tx_wd;
generate if (HAS_AES) begin : g_aes
aes_unit au (.clk(clk), .rst_n(rst_n), .key_start(a_key_start), .op_start(a_op_start), .mode(a_mode),
             .aad_len(a_aadlen), .data_len(a_dlen), .rx_a(a_rx_a), .rx_q(mem_q),
             .tx_we(a_tx_we), .tx_wa(a_tx_wa), .tx_wd(a_tx_wd),
             .done(a_done), .auth_fail(a_auth_fail), .key_ready(a_key_ready), .busy(a_busy));
end else begin : g_noaes
    assign a_key_ready = 1'b0; assign a_done = 1'b0; assign a_busy = 1'b0; assign a_auth_fail = 1'b0;
    assign a_tx_we = 1'b0; assign a_tx_wa = 13'd0; assign a_tx_wd = 8'd0; assign a_rx_a = 13'd0;
end endgenerate

// ---------------- subroutines ----------------
reg         rd_start, fd_start, em_start;
reg  [12:0] rd_ptr_i, fd_ptr_i, em_base;
reg  [5:0]  rd_n, em_n;
reg  [15:0] fd_n;
reg         fd_key;
reg  [127:0] em_d;
wire [12:0] rd_a, fd_a; wire [55:0] acc; wire rd_done, fd_done, em_done, rd_act, fd_act;
wire        ob_valid; wire [7:0] ob_byte; wire ob_key;
sub_rdn  u_rd (.clk(clk), .rst_n(rst_n), .start(rd_start), .ptr_i(rd_ptr_i), .n(rd_n), .a(rd_a), .mem_q(mem_q),
               .acc(acc), .done(rd_done), .active(rd_act));
sub_feed u_fd (.clk(clk), .rst_n(rst_n), .start(fd_start), .ptr_i(fd_ptr_i), .n(fd_n), .key_i(fd_key), .a(fd_a),
               .mem_q(mem_q), .ready(fd_key || h_in_ready), .ob_valid(ob_valid), .ob_byte(ob_byte),
               .ob_key(ob_key), .done(fd_done), .active(fd_act));
assign mem_a = a_busy ? a_rx_a : fd_act ? fd_a : rd_a;
assign h_in_valid_o = ob_valid && !ob_key;  assign h_in_byte_o  = ob_byte;
assign h_key_wr_o   = ob_valid &&  ob_key;  assign h_key_byte_o = ob_byte;

wire        em_we; wire [12:0] em_wa; wire [7:0] em_wd;
generate if (HAS_INFO) begin : g_info
sub_emit u_em (.clk(clk), .rst_n(rst_n), .start(em_start), .base(em_base), .d(em_d), .n(em_n),
               .we(em_we), .wa(em_wa), .wd(em_wd), .done(em_done));
end else begin : g_noinfo
    assign em_we = 1'b0; assign em_wa = 13'd0; assign em_wd = 8'd0; assign em_done = 1'b0;
end endgenerate
// digest bytes (read back from the hash unit RAM) -> TX
reg         ho_we; reg [12:0] ho_wa; reg [7:0] ho_wd;
assign tx_we = em_we | a_tx_we | ho_we;
assign tx_wa = a_tx_we ? a_tx_wa : ho_we ? ho_wa : em_wa;
assign tx_wd = a_tx_we ? a_tx_wd : ho_we ? ho_wd : em_wd;

// ---------------- main sequencer ----------------
localparam S_IDLE=0, S_FIN=1,
           S_INFO=2,
           S_RND0=4, S_RND1=5, S_RND2=6,
           S_SHA0=8, S_SHA1=9, S_SHA2=10, S_SHA3=11,
           S_HM0=13, S_HM1=14, S_HM2=15, S_HM3=16,
           S_PB0=18, S_PB1=19, S_PB2=20, S_PB3=21, S_PB4=22, S_PB5=23, S_PB6=24, S_PB7=25,
           S_AK0=26, S_AK1=27, S_PB8=28,
           S_AO0=29, S_AO1=30, S_AO2=31, S_AO3=32, S_AO4=33,
           S_HO0=34, S_HO1=35, S_HO2=36;
reg [5:0]   st, ho_ret;
reg [7:0]   fin_status; reg [15:0] fin_len;
reg [15:0]  klen, dklen, pwlen, nrand, blk, dlen_r, aadlen_r, tx_off;
reg [31:0]  iters_r;
reg [2:0]   mode_r;
reg [7:0]   mode_b;
reg         hdone;
reg [4:0]   hi;
reg [15:0]  len_r;

assign busy = (st != S_IDLE);

task fin(input [7:0] s, input [15:0] l); begin fin_status <= s; fin_len <= l; st <= S_FIN; end endtask
task hout(input [5:0] r); begin hi <= 5'd0; ho_ret <= r; st <= S_HO0; end endtask       // 32 digest bytes -> TX[tx_off..]

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st <= S_IDLE; done <= 0; rd_start<=0; fd_start<=0; em_start<=0; ho_we <= 0;
        h_begin<=0; h_keydone<=0; h_msg_end<=0; a_key_start<=0; a_op_start<=0;
        hdone<=0; tx_off<=0; status<=0; tx_len<=0;
    end else begin
        done<=0; rd_start<=0; fd_start<=0; em_start<=0; ho_we <= 0;
        h_begin<=0; h_keydone<=0; h_msg_end<=0; a_key_start<=0; a_op_start<=0;
        if (h_done) hdone <= 1;

        case (st)
        S_IDLE: if (go) begin
            len_r <= len; tx_off <= 0; hdone <= 0;
            case (cmd)
            8'h01: if (!HAS_INFO) fin(1, 0); else begin em_d <= {64'h54524F4143433031, CAPS, 32'd0}; em_n <= 6'd12; em_base <= 0; em_start <= 1; fin_len <= 16'd12; st <= S_INFO; end
            8'h02: if (!HAS_INFO) fin(1, 0); else begin em_d <= uid; em_n <= 6'd16; em_base <= 0; em_start <= 1; fin_len <= 16'd16; st <= S_INFO; end
            8'h03: if (!HAS_INFO) fin(1, 0); else if (len != 16'd2) fin(2, 0); else begin rd_ptr_i <= 0; rd_n <= 2; rd_start <= 1; st <= S_RND0; end
            8'h10: begin h_begin <= 1; h_mode <= 0; fd_ptr_i <= 0; fd_n <= len; fd_key <= 0; st <= S_SHA0; end
            8'h11: if (len < 1) fin(2, 0); else begin rd_ptr_i <= 0; rd_n <= 1; rd_start <= 1; st <= S_HM0; end
            8'h12: if (len < 7) fin(2, 0); else begin rd_ptr_i <= 0; rd_n <= 7; rd_start <= 1; st <= S_PB0; end
            8'h20: if (!HAS_AES) fin(1, 0); else if (len != 32) fin(2, 0); else begin a_key_start <= 1; st <= S_AK0; end
            8'h21: if (!HAS_AES) fin(1, 0); else if (len < 21) fin(2, 0); else begin rd_ptr_i <= 0; rd_n <= 1; rd_start <= 1; st <= S_AO0; end
            default: fin(1, 0);
            endcase
        end

        // ---- info commands ----
        S_INFO: if (em_done) fin(0, fin_len);

        // ---- random ----   n = LE16 at acc[15:0]
        S_RND0: if (rd_done) begin
            nrand <= {acc[7:0], acc[15:8]};
            if ({acc[7:0], acc[15:8]} == 0 || {acc[7:0], acc[15:8]} > 16'd1024) fin(6, 0); else st <= S_RND1;
        end
        S_RND1: if (trng_valid) begin
            em_d <= {trng_data, 96'd0}; em_n <= 4; em_base <= tx_off[12:0]; em_start <= 1; st <= S_RND2;
        end
        S_RND2: if (em_done) begin
            tx_off <= tx_off + 16'd4;
            if (tx_off + 16'd4 >= nrand) fin(0, nrand); else st <= S_RND1;
        end

        // ---- SHA-256 ----
        S_SHA0: begin fd_start <= 1; st <= S_SHA1; end
        S_SHA1: if (fd_done) st <= S_SHA2;
        S_SHA2: if (h_in_ready) begin h_msg_end <= 1; st <= S_SHA3; end
        S_SHA3: if (hdone) hout(S_FIN);                                        // S_FIN as return = finish with the 32-byte digest

        // ---- HMAC-SHA256 ----   acc[7:0] = klen
        S_HM0: if (rd_done) begin
            klen <= {8'd0, acc[7:0]};
            if (acc[7:0] > 64 || {8'd0, acc[7:0]} + 16'd1 > len_r) fin(6, 0);
            else begin h_begin <= 1; h_mode <= 1; st <= S_HM1; end
        end
        S_HM1: begin fd_ptr_i <= 13'd1; fd_n <= klen; fd_key <= 1; fd_start <= 1; st <= S_HM2; end
        S_HM2: if (fd_done) begin
            h_keydone <= 1; fd_ptr_i <= 13'd1 + klen[12:0]; fd_n <= len_r - 16'd1 - klen; fd_key <= 0; st <= S_HM3;
        end
        S_HM3: begin fd_start <= 1; st <= S_SHA1; end         // re-uses the SHA tail (wait, end, emit)

        // ---- PBKDF2-HMAC-SHA256 ----
        S_PB0: if (rd_done) begin
            iters_r <= {acc[31:24], acc[39:32], acc[47:40], acc[55:48]};
            dklen   <= {acc[15:8], acc[23:16]};
            pwlen   <= {8'd0, acc[7:0]};
            st <= S_PB1;
        end
        S_PB1: begin
            if (iters_r == 0 || dklen == 0 || dklen > 16'd1024 || pwlen > 16'd64 || pwlen + 16'd7 > len_r) fin(6, 0);
            else begin blk <= 1; tx_off <= 0; st <= S_PB2; end
        end
        S_PB2: begin
            h_begin <= 1; h_mode <= 2; h_iters <= iters_r; hdone <= 0;
            fd_ptr_i <= 13'd7; fd_n <= pwlen; fd_key <= 1; st <= S_PB3;
        end
        S_PB3: begin fd_start <= 1; st <= S_PB4; end
        S_PB4: if (fd_done) begin
            h_keydone <= 1; h_idx <= {16'd0, blk};
            fd_ptr_i <= 13'd7 + pwlen[12:0]; fd_n <= len_r - 16'd7 - pwlen; fd_key <= 0; fd_start <= 1; st <= S_PB5;
        end
        S_PB5: if (fd_done) st <= S_PB6;
        S_PB6: if (h_in_ready) begin h_msg_end <= 1; st <= S_PB7; end
        S_PB7: if (hdone) hout(S_PB8);
        S_PB8: begin
            tx_off <= tx_off + 16'd32; blk <= blk + 16'd1;
            if (tx_off + 16'd32 >= dklen) fin(0, dklen); else st <= S_PB2;
        end

        // ---- digest -> TX: word hi[4:2], byte hi[1:0] (big endian) ----
        S_HO0: begin h_dgra_o <= hi[4:2]; st <= S_HO1; end
        S_HO1: st <= S_HO2;
        S_HO2: begin
            ho_we <= 1; ho_wa <= tx_off[12:0] + {8'd0, hi};
            case (hi[1:0]) 2'd0: ho_wd <= h_dgq_i[31:24]; 2'd1: ho_wd <= h_dgq_i[23:16]; 2'd2: ho_wd <= h_dgq_i[15:8]; default: ho_wd <= h_dgq_i[7:0]; endcase
            hi <= hi + 5'd1;
            if (hi == 5'd31) begin if (ho_ret == S_FIN) fin(0, 16'd32); else st <= ho_ret; end
            else st <= (hi[1:0] == 2'd3) ? S_HO0 : S_HO2;
        end

        // ---- AES key ----   (the unit reads RX[0..31] itself)
        S_AK0: st <= S_AK1;
        S_AK1: if (a_done) fin(0, 0);

        // ---- AES operation ----   header: mode | iv[16] | aadlen[2 LE] | dlen[2 LE]; the unit streams the rest itself
        S_AO0: if (rd_done) begin mode_b <= acc[7:0]; rd_ptr_i <= 13'd17; rd_n <= 4; rd_start <= 1; st <= S_AO4; end
        S_AO4: if (rd_done) begin
            mode_r   <= mode_b[2:0];
            a_mode   <= mode_b[2:0];
            aadlen_r <= {acc[23:16], acc[31:24]};
            dlen_r   <= {acc[7:0], acc[15:8]};
            a_aadlen <= {acc[23:16], acc[31:24]};
            a_dlen   <= {acc[7:0], acc[15:8]};
            st <= S_AO1;
        end
        S_AO1: begin
            if (mode_b > 8'd5 || !a_key_ready) fin(!a_key_ready ? 8'd7 : 8'd6, 0);
            else if (21 + aadlen_r + dlen_r + (mode_r == 3'd5 ? 16 : 0) != len_r) fin(2, 0);
            else if (!mode_r[2] && (aadlen_r != 0 || dlen_r == 0 || dlen_r[3:0] != 0)) fin(6, 0);
            else if (dlen_r > 16'd8000) fin(6, 0);
            else begin a_op_start <= 1; st <= S_AO2; end
        end
        S_AO2: st <= S_AO3;
        S_AO3: if (a_done) begin
            if (a_auth_fail) fin(4, 0); else fin(0, dlen_r + ((mode_r == 3'd4) ? 16'd16 : 16'd0));
        end

        S_FIN: begin done <= 1; status <= fin_status; tx_len <= fin_len; st <= S_IDLE; end
        default: st <= S_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
