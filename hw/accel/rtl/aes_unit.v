`default_nettype none
// AES-256 command unit: key load, ECB / CBC / GCM over the frame RAMs, byte-serial (replaces the old block-wide
// aes_modes + ghash_mul + aes_out_wr; no 128-bit buffers, shifters or masks besides the cipher state and GHASH).
//
//   key_start : load the key from RX[0..31] and expand it            -> done
//   op_start  : RX = mode | iv[16] | aadlen[2] | dlen[2] | aad | data | (tag16 if mode 5), lengths given by the caller
//               mode 0/1 ECB enc/dec, 2/3 CBC enc/dec (dlen % 16 == 0), 4/5 GCM enc/dec (12-byte IV = iv[0..11])
//               TX <- data' (+ tag16 for mode 4)                     -> done (auth_fail for a bad GCM tag)
// Every value is processed one byte at a time: the cipher state is a 16-byte shift register (aes_core sh_*), so
//   CBC-enc  shifts in P ^ (state = previous ciphertext) while the previous ciphertext is shifted out to TX,
//   CBC-dec  XORs the decrypted state with the previous ciphertext re-read from RX,
//   GCM      shifts in the next counter block while the keystream is shifted out; GHASH runs bit-serially on the
//            ciphertext stream (Y: accumulator, Z: product, V = H*x^i), and the tag is compared on the fly.
module aes_unit (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         key_start,
    input  wire         op_start,
    input  wire [2:0]   mode,
    input  wire [15:0]  aad_len,
    input  wire [15:0]  data_len,
    output reg  [12:0]  rx_a,
    input  wire [7:0]   rx_q,
    output reg          tx_we,
    output reg  [12:0]  tx_wa,
    output reg  [7:0]   tx_wd,
    output reg          done,
    output reg          auth_fail,
    output wire         key_ready,
    output wire         busy
);
// ---------------- cipher core ----------------
reg         c_kwe, c_kgo, c_start, c_sh; reg [2:0] c_kwi; reg [31:0] kacc; reg [7:0] c_shin;
wire        c_done, c_busy; wire [7:0] c_shout; wire [127:0] c_state;
reg  [2:0]  md;
wire        gcm = md[2], cbc = md[1] & ~md[2], dec = md[0];
aes_core core (.clk(clk), .rst_n(rst_n), .key_we(c_kwe), .key_wi(c_kwi), .key_wd(kacc), .key_go(c_kgo), .key_ready(key_ready),
               .blk_start(c_start), .dec(dec & ~gcm), .blk_done(c_done), .sh_en(c_sh), .sh_in(c_shin), .sh_out(c_shout),
               .state(c_state), .busy(c_busy));

// ---------------- GHASH (bit-serial: one bit of the GHASH input per clock, x_0 first) ----------------
reg  [127:0] H, Y, Z, V;
reg          g_bit, g_step, g_init, g_end;
wire         y_shift;
wire         gx = g_bit ^ Y[127];
always @(posedge clk) begin
    if (g_init)       begin Y <= 128'd0; Z <= 128'd0; V <= H; end
    else if (g_end)   begin Y <= Z; Z <= 128'd0; V <= H; end
    else if (g_step)  begin
        if (gx) Z <= Z ^ V;
        V <= {1'b0, V[127:1]} ^ (V[0] ? {8'he1, 120'd0} : 128'd0);
        Y <= {Y[126:0], 1'b0};
    end else if (y_shift) Y <= {Y[126:0], 1'b0};
end

// ---------------- byte loop engine ----------------
// One loop = 16 byte steps (i = 0..15); bytes i >= ln are padding (not read, not written, GHASH sees 0).
//   per byte: [T: 8 clk, tag mode: collect Y bits] -> A: RX read -> W -> D: compute / shift / write -> [G: 8 GHASH clk]
localparam SH_ZERO = 2'd0, SH_RX = 2'd1, SH_RXST = 2'd2, SH_CTR = 2'd3;      // core shift-in source
localparam GH_RX = 2'd0, GH_OUT = 2'd1, GH_LEN = 2'd2;                       // GHASH byte source
reg        l_rd, l_out, l_outx, l_sh, l_gh, l_tag, l_key; reg [1:0] l_shsrc, l_ghsrc; reg [12:0] l_rdbase; reg [4:0] ln;
reg [3:0]  li; reg [2:0] lb; reg [2:0] ls; reg [7:0] gb, tb; reg [12:0] optr; reg diff;
localparam LS_IDLE=0, LS_T=1, LS_A=2, LS_W=3, LS_D=4, LS_G=5;
assign     y_shift = (ls == LS_T);
reg        l_go, l_done, op_clr;
reg [95:0] iv96; reg [15:0] ctr; reg [15:0] aadl, datl;
wire       valid_b = ({1'b0, li} < ln);
wire [7:0] rxb  = (l_rd && valid_b) ? rx_q : 8'd0;
wire [7:0] ob   = (l_tag ? tb : 8'd0) ^ c_shout ^ (l_outx ? rxb : 8'd0);
reg  [7:0] ctr_b, len_b;
always @(*) begin
    case (li)
    4'd14: ctr_b = ctr[15:8]; 4'd15: ctr_b = ctr[7:0];
    default: ctr_b = (li < 4'd12) ? iv96[95:88] : 8'd0;
    endcase
    case (li)
    4'd5:  len_b = {5'd0, aadl[15:13]};  4'd6: len_b = aadl[12:5];  4'd7: len_b = {aadl[4:0], 3'd0};
    4'd13: len_b = {5'd0, datl[15:13]};  4'd14: len_b = datl[12:5]; 4'd15: len_b = {datl[4:0], 3'd0};
    default: len_b = 8'd0;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin ls <= LS_IDLE; l_done <= 1'b0; tx_we <= 1'b0; c_sh <= 1'b0; g_step <= 1'b0; c_kwe <= 1'b0; end
    else begin
        l_done <= 1'b0; tx_we <= 1'b0; c_sh <= 1'b0; g_step <= 1'b0; c_kwe <= 1'b0;
        if (op_clr) begin optr <= 13'd0; diff <= 1'b0; end
        case (ls)
        LS_IDLE: if (l_go) begin li <= 4'd0; lb <= 3'd0; ls <= l_tag ? LS_T : LS_A; end
        LS_T: begin                                                   // tag byte: next 8 bits of Y
            tb <= {tb[6:0], Y[127]}; lb <= lb + 3'd1;
            if (lb == 3'd7) ls <= LS_A;
        end
        LS_A: begin rx_a <= l_rdbase + {9'd0, li}; ls <= LS_W; end
        LS_W: ls <= LS_D;
        LS_D: begin
            if (l_out && valid_b) begin tx_we <= 1'b1; tx_wa <= optr; tx_wd <= ob; optr <= optr + 13'd1; end
            if (l_tag && l_rd && ob != rx_q) diff <= 1'b1;
            if (l_sh) begin
                c_sh <= 1'b1;
                case (l_shsrc)
                SH_RX:   c_shin <= rxb;
                SH_RXST: c_shin <= rxb ^ c_shout;
                SH_CTR:  c_shin <= ctr_b;
                default: c_shin <= 8'd0;
                endcase
                if (l_shsrc == SH_CTR && li < 4'd12) iv96 <= {iv96[87:0], iv96[95:88]};
            end
            if (l_rd && valid_b && l_shsrc == SH_RX && !l_sh && !l_gh && !l_out && !l_key) iv96 <= {iv96[87:0], rx_q};   // IV capture loop
            if (l_key) begin                                          // key loop: 4 bytes -> one key word
                kacc <= {kacc[23:0], rx_q};
                if (li[1:0] == 2'd3) begin c_kwe <= 1'b1; c_kwi <= {l_rdbase[4], li[3:2]}; end
            end
            if (l_gh) begin
                gb <= !valid_b ? 8'd0 : (l_ghsrc == GH_OUT) ? ob : (l_ghsrc == GH_LEN) ? len_b : rxb;
                lb <= 3'd0; ls <= LS_G;
            end else if (li == 4'd15) begin l_done <= 1'b1; ls <= LS_IDLE; end
            else begin li <= li + 4'd1; ls <= l_tag ? LS_T : LS_A; end
        end
        LS_G: begin
            g_step <= 1'b1; g_bit <= gb[7]; gb <= {gb[6:0], 1'b0}; lb <= lb + 3'd1;
            if (lb == 3'd7) begin
                if (li == 4'd15) begin l_done <= 1'b1; ls <= LS_IDLE; end
                else begin li <= li + 4'd1; ls <= l_tag ? LS_T : LS_A; end
            end
        end
        default: ls <= LS_IDLE;
        endcase
    end
end

// ---------------- operation sequencer ----------------
localparam M_IDLE=0, M_KEY=1, M_KEYW=2, M_KEYGO=3, M_KEYDONE=4,
           M_RUN=5, M_RUNW=6,
           M_H0=7, M_H1=8, M_IV=9, M_AAD=10, M_AADW=11, M_CTR0=12, M_DATA=13, M_DATAW=14, M_LEN=15, M_LENW=16,
           M_J0=17, M_TAG=18, M_TAGW=19,
           M_BLK=20, M_BLKW=21, M_OUT=22, M_OUTW=23, M_FIN=24, M_GE=25, M_PRE=26, M_PREW=27;
reg [4:0]  ms, ret;
reg [15:0] arem, drem; reg [12:0] iptr, pblk; reg first; reg [5:0] kc;
reg        busy_r;
assign busy = busy_r;
wire [4:0] n_a = (arem >= 16'd16) ? 5'd16 : arem[4:0];
wire [4:0] n_d = (drem >= 16'd16) ? 5'd16 : drem[4:0];

task loop(input rd, input [12:0] base, input [4:0] n, input out, input outx, input sh, input [1:0] shsrc, input gh, input [1:0] ghsrc, input tag);
begin
    l_rd <= rd; l_rdbase <= base; ln <= n; l_out <= out; l_outx <= outx; l_sh <= sh; l_shsrc <= shsrc; l_gh <= gh; l_ghsrc <= ghsrc; l_tag <= tag;
    l_key <= 1'b0; l_go <= 1'b1;
end endtask
task run_then(input [4:0] r); begin c_start <= 1'b1; ret <= r; ms <= M_RUNW; end endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ms <= M_IDLE; busy_r <= 1'b0; done <= 1'b0; auth_fail <= 1'b0; l_go <= 1'b0; c_kgo <= 1'b0; c_start <= 1'b0; op_clr <= 1'b0;
        g_init <= 1'b0; g_end <= 1'b0;
    end else begin
        done <= 1'b0; l_go <= 1'b0; c_kgo <= 1'b0; c_start <= 1'b0; g_init <= 1'b0; g_end <= 1'b0; op_clr <= 1'b0;
        case (ms)
        M_IDLE: begin
            if (key_start) begin busy_r <= 1'b1; md <= 3'd0; ms <= M_KEY; end
            else if (op_start) begin
                busy_r <= 1'b1; md <= mode; aadl <= aad_len; datl <= data_len; arem <= mode[2] ? aad_len : 16'd0; drem <= data_len;
                iptr <= 13'd21; op_clr <= 1'b1; auth_fail <= 1'b0; first <= 1'b1;
                if (mode[2]) ms <= M_H0;                                 // GCM: H = E(0)
                else if (mode[1]) ms <= M_PRE;                           // CBC
                else ms <= M_BLK;                                        // ECB
            end
        end
        // ---- key: 32 bytes (two 16-byte loops) -> 8 words -> expansion ----
        M_KEY:  begin loop(1, 13'd0, 5'd16, 0, 0, 0, SH_RX, 0, GH_RX, 0); l_key <= 1'b1; ms <= M_KEYW; end
        M_KEYW: if (l_done) begin loop(1, 13'd16, 5'd16, 0, 0, 0, SH_RX, 0, GH_RX, 0); l_key <= 1'b1; ms <= M_KEYGO; end
        M_KEYGO: if (l_done) begin kc <= 6'd0; ms <= M_KEYDONE; end
        M_KEYDONE: begin                                                 // let the last word land, then expand
            if (kc == 6'd2) c_kgo <= 1'b1;
            if (kc != 6'd5) kc <= kc + 6'd1;
            else if (key_ready) ms <= M_FIN;
        end
        // ---- run the cipher on the state ----
        M_RUNW: if (c_done) ms <= ret;
        // ---- CBC: preload the IV as the "previous ciphertext" ----
        M_PRE:  begin loop(1, 13'd1, 5'd16, 0, 0, 1, SH_RX, 0, GH_RX, 0); ms <= M_PREW; end
        M_PREW: if (l_done) ms <= M_BLK;
        // ---- ECB / CBC block: shift the input in (CBC-enc: xor with the state), process, then emit ----
        M_BLK: begin
            if (drem == 16'd0) begin
                if (cbc && !dec) begin loop(0, 13'd0, 5'd16, 1, 0, 1, SH_RXST, 0, GH_RX, 0); ms <= M_OUTW; end   // last CBC-enc block out
                else ms <= M_FIN;
            end else begin
                // CBC-enc: shift in P ^ state while the previous ciphertext (the state) goes out (not for the first block)
                loop(1, iptr, 5'd16, cbc && !dec && !first, 0, 1, (cbc && !dec) ? SH_RXST : SH_RX, 0, GH_RX, 0);
                pblk <= iptr; iptr <= iptr + 13'd16; drem <= drem - 16'd16; ms <= M_BLKW;
            end
        end
        M_BLKW: if (l_done) run_then(M_OUT);
        M_OUT: begin
            if (cbc && !dec) begin first <= 1'b0; ms <= M_BLK; end                         // output happens with the next block
            else begin                                                                      // ECB: state; CBC-dec: state ^ previous ciphertext
                loop(cbc, first ? 13'd1 : pblk - 13'd16, 5'd16, 1, cbc, 1, SH_ZERO, 0, GH_RX, 0);
                first <= 1'b0; ms <= M_OUTW;
            end
        end
        M_OUTW: if (l_done) ms <= (drem == 16'd0 && !(cbc && !dec)) ? M_FIN : (cbc && !dec) ? M_FIN : M_BLK;
        // ---- GCM ----
        M_H0: begin loop(0, 13'd0, 5'd16, 0, 0, 1, SH_ZERO, 0, GH_RX, 0); ms <= M_H1; end
        M_H1: if (l_done) run_then(M_IV);
        M_IV: begin H <= c_state; loop(1, 13'd1, 5'd12, 0, 0, 0, SH_RX, 0, GH_RX, 0); ms <= M_GE; end
        M_GE: if (l_done) begin g_init <= 1'b1; ms <= M_AAD; end
        M_AAD: begin
            if (arem == 16'd0) begin ctr <= 16'd2; loop(0, 13'd0, 5'd16, 0, 0, 1, SH_CTR, 0, GH_RX, 0); ms <= M_CTR0; end
            else begin
                loop(1, iptr, n_a, 0, 0, 0, SH_RX, 1, GH_RX, 0);
                iptr <= iptr + {8'd0, n_a}; arem <= arem - {11'd0, n_a}; ms <= M_AADW;
            end
        end
        M_AADW: if (l_done) begin g_end <= 1'b1; ms <= M_AAD; end
        M_CTR0: if (l_done) ms <= M_DATA;
        M_DATA: begin
            if (drem == 16'd0) begin loop(0, 13'd0, 5'd16, 0, 0, 0, SH_RX, 1, GH_LEN, 0); ms <= M_LENW; end
            else run_then(M_DATAW);
        end
        M_DATAW: begin                                                   // keystream in the state: out = in ^ ks; next counter block in
            ctr <= ctr + 16'd1;
            loop(1, iptr, n_d, 1, 1, 1, SH_CTR, 1, dec ? GH_RX : GH_OUT, 0);
            iptr <= iptr + {8'd0, n_d}; drem <= drem - {11'd0, n_d}; ms <= M_LEN;
        end
        M_LEN: if (l_done) begin g_end <= 1'b1; ms <= M_DATA; end
        M_LENW: if (l_done) begin g_end <= 1'b1; ctr <= 16'd1; ms <= M_J0; end
        M_J0: begin loop(0, 13'd0, 5'd16, 0, 0, 1, SH_CTR, 0, GH_RX, 0); ms <= M_TAG; end   // J0 = IV || 1
        M_TAG: if (l_done) run_then(M_TAGW);
        M_TAGW: begin                                                    // tag = S ^ E(J0): written (enc) or compared (dec)
            loop(dec, iptr, 5'd16, !dec, 0, 1, SH_ZERO, 0, GH_RX, 1); ms <= M_OUTW;
        end
        M_FIN: if (ls == LS_IDLE && !l_go) begin
            auth_fail <= gcm && dec && diff; done <= 1'b1; busy_r <= 1'b0; ms <= M_IDLE;
        end
        default: ms <= M_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
