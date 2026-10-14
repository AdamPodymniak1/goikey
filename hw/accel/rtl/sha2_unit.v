`default_nettype none
// Unified SHA-2 engine: SHA-256 / HMAC-SHA256 / PBKDF2-HMAC-SHA256 and SHA-512 on ONE 64-bit datapath
// (replaces the separate hash_unit and hash512_unit).
//
// Usage (every control input is a 1-clk pulse):
//   SHA256 : begin_op(mode=0); in_valid/in_byte ...; msg_end            -> done; digest = 8 words of 32 bits
//   HMAC   : begin_op(mode=1); key_wr x N (N<=64, in order); key_done; bytes...; msg_end
//   PBKDF2 : begin_op(mode=2, iters); key_wr (password <=64 B); key_done; salt bytes...; msg_end (pb_idx = 1-based
//            block index, appended big-endian by the unit)
//   SHA512 : begin_op(mode=3); in_valid/in_byte ...; msg_end            -> done; digest = 8 words of 64 bits
// Bytes are consumed only when in_ready=1 (low while a block is being compressed). A byte presented while in_ready=0 is
// dropped and sets `overrun` (sticky until begin_op).
// The digest is read back through the RAM port while idle: dg_ra = word index, dg_q (one clock later; SHA-256 words in
// dg_q[31:0], SHA-512 words big endian in dg_q[63:0]).
//
// Area: block, key, chaining values (inner/outer state, running value, U, T), the round constants and the initial values
// live in one 64-bit block RAM. One compression engine (one round per clock, ~100 / ~120 clocks per block) reads its
// chaining value and block from that RAM and writes the new chaining value back; HMAC / PBKDF2 are sequences of such
// compressions. In SHA-256 mode the datapath uses the low 32 bits (the upper half carries don't-care values).
module sha2_unit (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         begin_op,
    input  wire [1:0]   mode,
    input  wire [31:0]  iters,
    input  wire [31:0]  pb_idx,
    input  wire         key_wr,
    input  wire [7:0]   key_byte,
    input  wire         key_done,
    input  wire         in_valid,
    input  wire [7:0]   in_byte,
    output wire         in_ready,
    input  wire         msg_end,
    output reg          busy,
    output reg          done,
    output reg          overrun,
    input  wire [2:0]   dg_ra,
    output wire [63:0]  dg_q
);
localparam M_SHA = 2'd0, M_HMAC = 2'd1, M_PBKDF2 = 2'd2, M_SHA512 = 2'd3;
// ---- RAM map (64-bit words; SHA-256 values use the low 32 bits) - keep in sync with ref/gen_sha2_rom.py ----
localparam [8:0] BLK = 9'd0, KEY = 9'd16, IST = 9'd32, OST = 9'd40, CUR = 9'd48, UREG = 9'd56, TACC = 9'd64, XI = 9'd72,
                 K256 = 9'd128, K512 = 9'd192, IV256 = 9'd272, IV512 = 9'd280;
(* ram_style="block" *) reg [63:0] hm [0:511];
initial begin
`include "sha2_rom.vh"
end
reg  [8:0]  ra, wa, obase; reg [63:0] wd; reg we; reg [63:0] rq;
wire [8:0]  ram_ra = busy ? ra : (obase + {6'd0, dg_ra});
always @(posedge clk) begin
    if (we) hm[wa] <= wd;
    rq <= hm[ram_ra];
end
assign dg_q = rq;

reg  [1:0]  md;
wire        m512 = (md == M_SHA512);

// ======================= compression engine state =======================
reg         c_go; reg [1:0] c_src; reg c_dg; reg [8:0] c_dbase, c_dst;
reg         c_done;
reg  [2:0]  cp;                              // phase: 0 idle, 1 load chain, 2 load window, 3 rounds, 4 final add
reg  [6:0]  cn;                              // phase counter
reg  [63:0] a, b, c, d, e, f, g, h;
reg  [63:0] w [0:15];
reg  [63:0] xa;
reg  [1:0]  src_q; reg dg_q_r; reg [8:0] dbase_q, dst_q, sbase;
integer i;
function [63:0] rotr64(input [63:0] x, input integer n); rotr64 = (x >> n) | (x << (64 - n)); endfunction
function [31:0] rotr32(input [31:0] x, input integer n); rotr32 = (x >> n) | (x << (32 - n)); endfunction
// Sigma functions: the upper half is always the SHA-512 function, only the low half is shared between the two modes
wire [63:0] S1_l = rotr64(e,14) ^ rotr64(e,18) ^ rotr64(e,41);
wire [31:0] S1_s = rotr32(e[31:0],6) ^ rotr32(e[31:0],11) ^ rotr32(e[31:0],25);
wire [63:0] S0_l = rotr64(a,28) ^ rotr64(a,34) ^ rotr64(a,39);
wire [31:0] S0_s = rotr32(a[31:0],2) ^ rotr32(a[31:0],13) ^ rotr32(a[31:0],22);
wire [63:0] g0_l = rotr64(w[1],1) ^ rotr64(w[1],8) ^ (w[1] >> 7);
wire [31:0] g0_s = rotr32(w[1][31:0],7) ^ rotr32(w[1][31:0],18) ^ (w[1][31:0] >> 3);
wire [63:0] g1_l = rotr64(w[14],19) ^ rotr64(w[14],61) ^ (w[14] >> 6);
wire [31:0] g1_s = rotr32(w[14][31:0],17) ^ rotr32(w[14][31:0],19) ^ (w[14][31:0] >> 10);
wire [63:0] S1  = {S1_l[63:32], m512 ? S1_l[31:0] : S1_s};
wire [63:0] S0  = {S0_l[63:32], m512 ? S0_l[31:0] : S0_s};
wire [63:0] sg0 = {g0_l[63:32], m512 ? g0_l[31:0] : g0_s};
wire [63:0] sg1 = {g1_l[63:32], m512 ? g1_l[31:0] : g1_s};
wire [63:0] ch  = (e & f) ^ (~e & g);
wire [63:0] maj = (a & b) ^ (a & c) ^ (b & c);
wire [63:0] T1  = h + S1 + ch + rq + w[0];                                   // rq = K[t] (prefetched)
wire [63:0] T2  = S0 + maj;
wire [63:0] wnew = sg1 + w[9] + sg0 + w[0];
// load / final-add order: j even -> a-chain word (3 - j/2), j odd -> e-chain word (7 - j/2)
function [2:0] widx(input [3:0] j); widx = j[0] ? (3'd7 - j[3:1]) : (3'd3 - j[3:1]); endfunction
wire [3:0]  cj    = cn[3:0] - 4'd2;                                          // index of the word that arrives now
wire [63:0] finw  = rq + (cn[0] ? h : d);
wire [4:0]  tw    = cn[4:0] - 5'd2;                                          // window word index that arrives now
wire [63:0] blkw  = !dg_q_r ? rq : (tw < 5'd8) ? rq : (tw == 5'd8) ? 64'h80000000 : (tw == 5'd15) ? 64'h00000300 : 64'd0;
wire [8:0]  kbase = m512 ? K512 : K256;
wire [6:0]  last_round = m512 ? 7'd79 : 7'd63;

// chains {a,b,c,d} and {e,f,g,h} and the 16-word window only ever shift; the head values differ per phase
wire        ch_shift = (cp == 3'd3) || ((cp == 3'd1 || cp == 3'd4) && cn >= 7'd2 && cn[0]);
wire [63:0] a_in = (cp == 3'd3) ? (T1 + T2) : (cp == 3'd1) ? xa : 64'd0;
wire [63:0] e_in = (cp == 3'd3) ? (d + T1)  : (cp == 3'd1) ? rq : 64'd0;
wire        w_shift = (cp == 3'd3) || (cp == 3'd2 && cn >= 7'd2);
wire [63:0] w_in = (cp == 3'd3) ? wnew : blkw;
always @(posedge clk) begin
    if (ch_shift) begin a <= a_in; b <= a; c <= b; d <= c; e <= e_in; f <= e; g <= f; h <= g; end
    if (w_shift) begin for (i = 0; i < 15; i = i + 1) w[i] <= w[i+1]; w[15] <= w_in; end
end

// ======================= hash unit control =======================
localparam U_IDLE=0, U_KEY=1, U_DER=2, U_WC=3, U_STREAM=4, U_BEND=5, U_IDX=6, U_PAD=7, U_AFTER=8, U_TPASS=9, U_FIN=11;
localparam A_IPAD=0, A_OPAD=1, A_BLK=2, A_OUTER=3, A_L1=4, A_L2=5;
reg [3:0]  st, resume; reg [2:0] aft; reg [6:0] sn;
reg [31:0] iters_r, jcnt;
reg [31:0] total; reg [63:0] lsh;
reg [6:0]  cnt; reg [2:0] bc; reg [63:0] sh64;
reg [63:0] wword; reg [8:0] waddr; reg wph;
reg [4:0]  nkw; reg [6:0] kcnt; reg [31:0] kw32;
reg        first, padding, last, dpad, tcopy, nolen; reg [1:0] pstage; reg [31:0] pbi;
assign in_ready = (st == U_STREAM);

wire        pad_push = (st == U_PAD);
reg  [7:0]  pad_byte;
always @(*) begin
    if (pstage == 2'd0) pad_byte = 8'h80;
    else if (pstage == 2'd1) pad_byte = 8'h00;
    else pad_byte = lsh[63:56];
end
wire        idx_push = (st == U_IDX);
reg  [7:0]  idx_byte;
always @(*) case (sn[1:0]) 2'd0: idx_byte = pbi[31:24]; 2'd1: idx_byte = pbi[23:16]; 2'd2: idx_byte = pbi[15:8]; default: idx_byte = pbi[7:0]; endcase
wire        push  = (st == U_STREAM && in_valid) || pad_push || idx_push;
wire [7:0]  pbyte = pad_push ? pad_byte : idx_push ? idx_byte : in_byte;
wire        word_done = push && (m512 ? (bc == 3'd7) : (bc[1:0] == 2'd3));
wire        blk_last  = m512 ? (cnt == 7'd127) : (cnt[5:0] == 6'd63);
wire        len_pos   = m512 ? (cnt == 7'd119) : (cnt[5:0] == 6'd55);      // last byte before the length field
wire [31:0] pad_const = dpad ? 32'h5c5c5c5c : 32'h36363636;
wire [3:0]  nxt = (st == U_IDX) ? ((sn[1:0] == 2'd3) ? U_PAD : U_IDX) : st;
wire        plain = (md == M_SHA) || (md == M_SHA512);

task launch(input [1:0] src, input dg, input [8:0] dbase, input [8:0] dst, input [2:0] after); begin
    c_go <= 1; c_src <= src; c_dg <= dg; c_dbase <= dbase; c_dst <= dst; aft <= after; st <= U_WC;
end endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cp <= 0; c_done <= 0; c_go <= 0; st <= U_IDLE; busy <= 0; done <= 0; overrun <= 0; we <= 0; wph <= 0; bc <= 0; cnt <= 0;
        md <= M_SHA; obase <= CUR; sh64 <= 64'd0;
    end else begin
        c_done <= 0; c_go <= 0; done <= 0; we <= 0;
        if (in_valid && st != U_STREAM) overrun <= 1;
        // ---------------- background word writer ----------------
        if (wph) begin we <= 1; wa <= waddr; wd <= wword; wph <= 1'b0; end
        // ---------------- compression engine ----------------
        case (cp)
        3'd0: if (c_go) begin
            src_q <= c_src; dg_q_r <= c_dg; dbase_q <= c_dbase; dst_q <= c_dst; cn <= 0; cp <= 3'd1;
            sbase <= (c_src == 2'd0) ? (m512 ? IV512 : IV256) : (c_src == 2'd1) ? IST : (c_src == 2'd2) ? OST : CUR;
        end
        3'd1: begin                                        // chaining value -> chains: 8 reads, one pair per shift
            if (cn < 7'd8) ra <= sbase + {6'd0, widx(cn[3:0])};
            if (cn >= 7'd2 && !cn[0]) xa <= rq;
            if (cn == 7'd9) begin cn <= 0; cp <= 3'd2; end else cn <= cn + 7'd1;
        end
        3'd2: begin                                        // block -> window (16 words), then prefetch K[0], K[1]
            if (cn < 7'd16) ra <= dg_q_r ? (dbase_q + {6'd0, cn[2:0]}) : (BLK + {5'd0, cn[3:0]});
            else if (cn == 7'd16) ra <= kbase;
            else ra <= kbase + 9'd1;
            if (cn == 7'd17) begin cn <= 0; cp <= 3'd3; end else cn <= cn + 7'd1;
        end
        3'd3: begin                                        // 64 / 80 rounds, K[t+2] requested now
            ra <= kbase + {2'd0, cn} + 9'd2;
            if (cn == last_round) begin cn <= 0; cp <= 3'd4; end else cn <= cn + 7'd1;
        end
        3'd4: begin                                        // H' = H + working variables (tails d / h are popped pairwise)
            if (cn < 7'd8) ra <= sbase + {6'd0, widx(cn[3:0])};
            if (cn >= 7'd2) begin
                we <= 1; wa <= dst_q + {6'd0, widx(cj)}; wd <= finw;
            end
            if (cn == 7'd9) begin cp <= 3'd0; c_done <= 1; end else cn <= cn + 7'd1;
        end
        default: cp <= 3'd0;
        endcase

        // ---------------- byte staging (message, index and padding bytes) ----------------
        if (push) begin
            sh64 <= {sh64[55:0], pbyte}; bc <= word_done ? 3'd0 : bc + 3'd1;
            if (word_done) begin wword <= {sh64[55:0], pbyte}; waddr <= BLK + (m512 ? {5'd0, cnt[6:3]} : {5'd0, cnt[5:2]}); wph <= 1'b1; end
            cnt <= blk_last ? 7'd0 : cnt + 7'd1; total <= total + 32'd1;
            if (blk_last) begin resume <= nxt; st <= U_BEND; end
            else if (st == U_IDX) begin st <= nxt; sn <= sn + 7'd1; end
        end

        // ---------------- control FSM ----------------
        if (begin_op) begin
            md <= mode; iters_r <= iters; busy <= 1; overrun <= 0; total <= (mode == M_SHA || mode == M_SHA512) ? 32'd0 : 32'd64;
            cnt <= 0; bc <= 0; wph <= 0; kcnt <= 0; first <= 1; padding <= 0; last <= 0; dpad <= 0; sn <= 0;
            st <= (mode == M_SHA || mode == M_SHA512) ? U_STREAM : U_KEY;
        end else case (st)
        U_KEY: begin
            if (key_wr) begin
                kw32 <= {kw32[23:0], key_byte}; kcnt <= kcnt + 7'd1;
                if (kcnt[1:0] == 2'd3) begin wword <= {32'd0, kw32[23:0], key_byte}; waddr <= KEY + {5'd0, kcnt[5:2]}; wph <= 1'b1; end
            end
            if (key_done) begin
                nkw <= kcnt[6:2] + {4'd0, |kcnt[1:0]};
                if (kcnt[1:0] != 2'd0) begin
                    wword <= {32'd0, (kcnt[1:0] == 2'd1) ? {kw32[7:0], 24'd0} : (kcnt[1:0] == 2'd2) ? {kw32[15:0], 16'd0} : {kw32[23:0], 8'd0}};
                    waddr <= KEY + {5'd0, kcnt[5:2]}; wph <= 1'b1;
                end
                sn <= 0; dpad <= 0; st <= U_DER;
            end
        end
        U_DER: begin                                       // BLK <= (KEY zero-padded to 16 words) ^ pad constant, then compress it
            if (sn == 7'd0) begin if (!wph && !we) sn <= 7'd1; end
            else begin
                if (sn <= 7'd16) ra <= KEY + {5'd0, sn[3:0] - 4'd1};
                if (sn >= 7'd3) begin we <= 1; wa <= BLK + {5'd0, sn[3:0] - 4'd3}; wd <= {32'd0, ((sn[4:0] - 5'd3) < nkw) ? (rq[31:0] ^ pad_const) : pad_const}; end
                if (sn == 7'd18) begin sn <= 0; launch(2'd0, 1'b0, BLK, dpad ? OST : IST, dpad ? A_OPAD : A_IPAD); end else sn <= sn + 7'd1;
            end
        end
        U_WC: if (c_done) begin
            case (aft)
            A_IPAD: begin dpad <= 1; sn <= 0; st <= U_DER; end
            A_OPAD: begin first <= 1; cnt <= 0; st <= U_STREAM; end
            A_BLK:  begin first <= 0; st <= last ? U_AFTER : resume; end
            A_OUTER: begin
                if (md == M_HMAC) begin obase <= CUR; st <= U_FIN; end
                else begin tcopy <= 1; jcnt <= 32'd1; sn <= 0; st <= U_TPASS; end
            end
            A_L1: launch(2'd2, 1'b1, XI, UREG, A_L2);
            default: begin tcopy <= 0; sn <= 0; st <= U_TPASS; end                    // A_L2
            endcase
        end
        U_STREAM: if (!in_valid && msg_end) begin
            if (md == M_PBKDF2) begin pbi <= pb_idx; sn <= 0; st <= U_IDX; end
            else begin pstage <= 2'd0; padding <= 1; st <= U_PAD; end
        end
        U_PAD: if (push) begin
            // SHA-512: a marker at byte 112..127 pushes the 16-byte length field into the next block
            if (pstage == 2'd0) begin lsh <= {29'd0, total, 3'b000}; nolen <= m512 && cnt > 7'd111 && !blk_last; pstage <= len_pos ? 2'd2 : 2'd1; end
            else if (pstage == 2'd1) begin if (len_pos && !nolen) pstage <= 2'd2; if (blk_last) nolen <= 1'b0; end
            else begin lsh <= {lsh[55:0], 8'd0}; if (blk_last) last <= 1; end
        end
        U_IDX: if (push && sn[1:0] == 2'd3) begin pstage <= 2'd0; padding <= 1; end
        U_BEND: if (!wph && !we) launch(first ? (plain ? 2'd0 : 2'd1) : 2'd3, 1'b0, BLK, CUR, A_BLK);
        U_AFTER: begin                                     // inner digest in CUR: HMAC outer hash (digest block under the opad state)
            if (plain) begin obase <= CUR; st <= U_FIN; end
            else launch(2'd2, 1'b1, CUR, (md == M_PBKDF2) ? UREG : CUR, A_OUTER);
        end
        U_TPASS: begin                                     // TACC <= tcopy ? UREG : TACC ^ UREG   (reads interleaved: UREG[k] at 2k, TACC[k] at 2k+1)
            if (sn < 7'd16) ra <= sn[0] ? (TACC + {6'd0, sn[3:1]}) : (UREG + {6'd0, sn[3:1]});
            if (sn >= 7'd3 && sn[0]) begin
                we <= 1; wa <= TACC + {6'd0, sn[3:1] - 3'd1}; wd <= tcopy ? xa : (xa ^ rq);
            end
            if (sn >= 7'd2 && !sn[0]) xa <= rq;
            if (sn == 7'd17) begin
                sn <= 0;
                if (jcnt >= iters_r) begin obase <= TACC; st <= U_FIN; end
                else begin jcnt <= jcnt + 32'd1; launch(2'd1, 1'b1, UREG, XI, A_L1); end
            end else sn <= sn + 7'd1;
        end
        U_FIN: if (!we) begin done <= 1; busy <= 0; st <= U_IDLE; end
        default: ;
        endcase
    end
end
endmodule
`default_nettype wire
