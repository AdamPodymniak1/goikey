`default_nettype none
// ML-DSA polynomial unit: NTT / inverse NTT and the element-wise operations of the reference code
// (poly_pointwise_montgomery, add/sub, reduce32, caddq, power2round, decompose, make_hint, chknorm, copy/clear).
// All 32-bit signed arithmetic is bit-exact with PQClean (see ref/pq/pq_model.py).
//
// op: 0 NTT 1 INTT 2 PMUL 3 PMULA 4 PADD 5 PSUB 6 PRED 7 PCADDQ 8 PCLR 9 PCOPY 10 P2R 11 PDEC 12 MKHINT 13 CHKN
// operand slots (instruction fields a,b,c):
//   NTT/INTT/PRED/PCADDQ/PCLR/CHKN : a            PMUL/PMULA/PADD/PSUB/MKHINT : a = dest, b, c = sources
//   PCOPY : a = dest, b = source                   P2R/PDEC : a = high part, b = low part, c = source
// Poly memory port: ra presented in cycle t -> rq valid in cycle t+2 (registered address, synchronous RAM).
module pq_poly (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [4:0]  op,
    input  wire [5:0]  sa, sb, sc,
    input  wire        g2sel,                 // 0: gamma2 = (q-1)/88, 1: gamma2 = (q-1)/32
    input  wire [31:0] bound,                 // CHKN bound
    output reg         busy,
    output reg         done,
    output reg         flag_or,               // CHKN: some coefficient violates the bound
    output reg  [8:0]  hint_cnt,              // MKHINT: hints in this polynomial
    output reg  [13:0] ra,
    output reg         we,
    output reg  [13:0] wa,
    output reg  [31:0] wd,
    input  wire [31:0] rq
);
localparam signed [31:0] Q = 32'sd8380417;
localparam OP_NTT=0, OP_INTT=1, OP_PMUL=2, OP_PMULA=3, OP_PADD=4, OP_PSUB=5, OP_PRED=6, OP_PCADDQ=7, OP_PCLR=8,
           OP_PCOPY=9, OP_P2R=10, OP_PDEC=11, OP_MKHINT=12, OP_CHKN=13;

// ---------------- zeta ROM (block RAM) ----------------
(* ram_style="block" *) reg signed [31:0] zrom [0:255];
initial begin
`include "pq_zetas.vh"
end
reg [7:0] za; reg signed [31:0] zq;
always @(posedge clk) zq <= zrom[za];

// ---------------- Montgomery pipe ----------------
reg m_in; reg signed [31:0] m_a, m_b; wire m_out; wire signed [31:0] m_r;
pq_mont mont (.clk(clk), .in_v(m_in), .a(m_a), .b(m_b), .out_v(m_out), .r(m_r));

// ---------------- element-wise arithmetic ----------------
function signed [31:0] f_reduce32(input signed [31:0] a);
    reg signed [32:0] x; reg signed [31:0] t;
    begin x = {a[31], a} + 33'sd4194304; t = x >>> 23; f_reduce32 = a - ((t <<< 23) - (t <<< 13) + t); end   // t*Q as shifts and adds (a multiplier here was mis-mapped to a DSP)
endfunction
function signed [31:0] f_caddq(input signed [31:0] a);
    f_caddq = a + (a[31] ? Q : 32'sd0);
endfunction
reg signed [31:0] r0, r1, r2;                 // operands
reg signed [31:0] res0, res1;
reg               hbit;
// decompose / power2round / make_hint on r0 (and r1 for the hint)
wire signed [31:0] pr_a1 = (r0 + 32'sd4095) >>> 13;
wire signed [31:0] pr_a0 = r0 - (pr_a1 <<< 13);
wire signed [31:0] d0   = (r0 + 32'sd127) >>> 7;
wire signed [31:0] d1_32 = (((d0 <<< 10) + d0) + 32'sd2097152) >>> 22;                                   // d0*1025
wire signed [31:0] d1_88 = (((d0 <<< 13) + (d0 <<< 11) + (d0 <<< 10) + (d0 <<< 3) + (d0 <<< 1) + d0) + 32'sd8388608) >>> 24;   // d0*11275
wire signed [31:0] d1_88b = d1_88 ^ (((32'sd43 - d1_88) >>> 31) & d1_88);
wire signed [31:0] dec_a1 = g2sel ? (d1_32 & 32'sd15) : d1_88b;
wire signed [31:0] g2     = g2sel ? 32'sd261888 : 32'sd95232;
// dec_a1 * 2*gamma2: 523776 = 2^19 - 2^9 (gamma2 = (q-1)/32), 190464 = 2^17 + 2^16 - 2^12 - 2^11 (gamma2 = (q-1)/88)
wire signed [31:0] a1x2g2 = g2sel ? ((dec_a1 <<< 19) - (dec_a1 <<< 9)) : ((dec_a1 <<< 17) + (dec_a1 <<< 16) - (dec_a1 <<< 12) - (dec_a1 <<< 11));
wire signed [31:0] dec_t  = r0 - a1x2g2;
wire signed [31:0] dec_a0 = dec_t - ((((Q - 32'sd1) >>> 1) - dec_t) >>> 31 & Q);
wire               mk_h   = (r0 > g2) || (r0 < -g2) || (r0 == -g2 && r1 != 0);
wire signed [31:0] cn_t0  = r0 >>> 31;
wire signed [31:0] cn_t   = r0 - (cn_t0 & (r0 <<< 1));
wire               cn_bad = (bound > 32'd1047552) || (cn_t >= $signed(bound));

// ---------------- control ----------------
localparam S_IDLE=0, S_RD=1, S_RDW=2, S_RDC=3, S_MUL=4, S_CALC=5, S_WR0=6, S_WR1=7, S_NEXT=8,
           S_NB=9, S_NR1=10, S_NR1W=11, S_NR1C=12, S_NR2=13, S_NR2W=14, S_NR2C=15, S_NM=16, S_NW0=17, S_NW1=18,
           S_NNEXT=19, S_SC=20, S_SCR=21, S_SCW=22, S_SCC=23, S_SCM=24, S_SCWR=25, S_CLRW=26, S_ZW=27;
reg [4:0]  st;
reg [4:0]  op_r;
reg [5:0]  a_r, b_r, c_r;
reg [8:0]  i;                                   // element index (0..255), also used as j in the NTT
reg [1:0]  rk, nr;                              // read counter / number of reads
// NTT state
reg [8:0]  ln, bstart, k; reg [8:0] j;
reg signed [31:0] x, y, zeta, tt;
reg        inv;

reg  [5:0] sl0, sl1, sl2;
wire [5:0] rslot = (rk == 2'd0) ? sl0 : (rk == 2'd1) ? sl1 : sl2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= S_IDLE; busy <= 0; done <= 0; we <= 0; m_in <= 0; flag_or <= 0; hint_cnt <= 0; ra <= 0; wa <= 0; wd <= 0; za <= 0; end
    else begin
        done <= 0; we <= 0; m_in <= 0;
        case (st)
        S_IDLE: if (start) begin
            busy <= 1; op_r <= op; a_r <= sa; b_r <= sb; c_r <= sc; flag_or <= 0; hint_cnt <= 0; i <= 0; rk <= 0;
            case (op)
              OP_NTT, OP_INTT: begin
                  inv <= (op == OP_INTT); ln <= (op == OP_INTT) ? 9'd1 : 9'd128; bstart <= 0; j <= 0;
                  k <= (op == OP_INTT) ? 9'd256 : 9'd0; st <= S_NB;
              end
              OP_PCLR: st <= S_CLRW;
              default: begin
                  case (op)                                                    // read plan
                    OP_PMUL, OP_PADD, OP_PSUB, OP_MKHINT: begin nr <= 2; sl0 <= sb; sl1 <= sc; sl2 <= sc; end
                    OP_PMULA:                             begin nr <= 3; sl0 <= sa; sl1 <= sb; sl2 <= sc; end
                    OP_PCOPY:                             begin nr <= 1; sl0 <= sb; sl1 <= sb; sl2 <= sb; end
                    OP_P2R, OP_PDEC:                      begin nr <= 1; sl0 <= sc; sl1 <= sc; sl2 <= sc; end
                    default:                              begin nr <= 1; sl0 <= sa; sl1 <= sa; sl2 <= sa; end   // PRED PCADDQ CHKN
                  endcase
                  st <= S_RD;
              end
            endcase
        end
        // ---------------- element-wise ----------------
        S_RD:  begin ra <= {rslot, i[7:0]}; st <= S_RDW; end
        S_RDW: st <= S_RDC;
        S_RDC: begin
            case (rk) 2'd0: r0 <= rq; 2'd1: r1 <= rq; default: r2 <= rq; endcase
            if (rk + 2'd1 == nr) st <= S_CALC; else begin rk <= rk + 2'd1; st <= S_RD; end
        end
        S_CALC: begin
            case (op_r)
              OP_PMUL:  begin m_in <= 1; m_a <= r0; m_b <= r1; st <= S_MUL; end
              OP_PMULA: begin m_in <= 1; m_a <= r1; m_b <= r2; st <= S_MUL; end
              OP_PADD:  begin res0 <= r0 + r1; st <= S_WR0; end
              OP_PSUB:  begin res0 <= r0 - r1; st <= S_WR0; end
              OP_PRED:  begin res0 <= f_reduce32(r0); st <= S_WR0; end
              OP_PCADDQ:begin res0 <= f_caddq(r0); st <= S_WR0; end
              OP_PCOPY: begin res0 <= r0; st <= S_WR0; end
              OP_P2R:   begin res0 <= pr_a1; res1 <= pr_a0; st <= S_WR0; end
              OP_PDEC:  begin res0 <= dec_a1; res1 <= dec_a0; st <= S_WR0; end
              OP_MKHINT:begin res0 <= {31'd0, mk_h}; if (mk_h) hint_cnt <= hint_cnt + 9'd1; st <= S_WR0; end
              OP_CHKN:  begin if (cn_bad) flag_or <= 1; st <= S_NEXT; end
              default:  st <= S_NEXT;
            endcase
        end
        S_MUL: if (m_out) begin res0 <= (op_r == OP_PMULA) ? r0 + m_r : m_r; st <= S_WR0; end
        S_WR0: begin
            we <= 1; wa <= {a_r, i[7:0]}; wd <= res0;
            st <= (op_r == OP_P2R || op_r == OP_PDEC) ? S_WR1 : S_NEXT;
        end
        S_WR1: begin we <= 1; wa <= {b_r, i[7:0]}; wd <= res1; st <= S_NEXT; end
        S_NEXT: begin
            if (i == 9'd255) begin st <= S_IDLE; busy <= 0; done <= 1; end
            else begin i <= i + 9'd1; rk <= 0; st <= S_RD; end
        end
        S_CLRW: begin                                                       // PCLR
            we <= 1; wa <= {a_r, i[7:0]}; wd <= 32'd0;
            if (i == 9'd255) begin st <= S_IDLE; busy <= 0; done <= 1; end else i <= i + 9'd1;
        end
        // ---------------- NTT / inverse NTT ----------------
        S_NB: begin                                                           // start of a block: next zeta
            if (!inv) begin
                if (ln == 9'd0) begin st <= S_IDLE; busy <= 0; done <= 1; end
                else if (bstart >= 9'd256) begin ln <= ln >> 1; bstart <= 0; end
                else begin za <= k[7:0] + 8'd1; k <= k + 9'd1; j <= 0; st <= S_ZW; end
            end else begin
                if (ln >= 9'd256) begin i <= 0; st <= S_SC; end              // all layers done -> final scaling
                else if (bstart >= 9'd256) begin ln <= ln << 1; bstart <= 0; end
                else begin za <= k[7:0] - 8'd1; k <= k - 9'd1; j <= 0; st <= S_ZW; end
            end
        end
        S_ZW: st <= S_NR1;                                                    // zrom address presented
        S_NR1: begin ra <= {a_r, (bstart[7:0] + j[7:0])}; st <= S_NR1W; end
        S_NR1W: st <= S_NR1C;
        S_NR1C: begin x <= rq; zeta <= inv ? -zq : zq; st <= S_NR2; end
        S_NR2: begin ra <= {a_r, (bstart[7:0] + j[7:0] + ln[7:0])}; st <= S_NR2W; end
        S_NR2W: st <= S_NR2C;
        S_NR2C: begin
            y <= rq;
            m_in <= 1; m_a <= zeta;
            m_b <= inv ? (x - rq) : rq;
            st <= S_NM;
        end
        S_NM: if (m_out) begin
            tt <= m_r;
            st <= S_NW0;
        end
        S_NW0: begin
            we <= 1; wa <= {a_r, (bstart[7:0] + j[7:0])};
            wd <= inv ? (x + y) : (x + tt);
            st <= S_NW1;
        end
        S_NW1: begin
            we <= 1; wa <= {a_r, (bstart[7:0] + j[7:0] + ln[7:0])};
            wd <= inv ? tt : (x - tt);
            st <= S_NNEXT;
        end
        S_NNEXT: begin
            if (j + 9'd1 == ln) begin bstart <= bstart + (ln << 1); st <= S_NB; end
            else begin j <= j + 9'd1; st <= S_NR1; end
        end
        // inverse NTT final scaling: a[i] = montgomery_reduce(41978 * a[i])
        S_SC:  begin ra <= {a_r, i[7:0]}; st <= S_SCR; end
        S_SCR: st <= S_SCW;
        S_SCW: st <= S_SCC;
        S_SCC: begin m_in <= 1; m_a <= 32'sd41978; m_b <= rq; st <= S_SCM; end
        S_SCM: if (m_out) begin we <= 1; wa <= {a_r, i[7:0]}; wd <= m_r; st <= S_SCWR; end
        S_SCWR: begin
            if (i == 9'd255) begin st <= S_IDLE; busy <= 0; done <= 1; end
            else begin i <= i + 9'd1; st <= S_SC; end
        end
        default: st <= S_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
