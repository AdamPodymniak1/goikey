`default_nettype none
// RSA-2048 big-number unit (CRT halves: 1024-bit registers of 64 x 16-bit words in block RAM, regs 0..15 user, 16.. internal).
// Opcodes mirror ref/pq/pq_asm.py (interpreter = oracle):
//  A0 RLDB a,desc  A1 RSTB a,desc  A2 RRNG a  A3 RSETI a,imm  A5 RMSEL a  A6 RR2 a  A7 RMUL a,b,c  A8 RADDM a,b,c  A9 RSUBM a,b,c
//  AA REXP a,b,c[,d = number of exponent words to scan (0 = all 64)]   AB RSIEVE a (flag)  AC RREM1 a (flag; imm = 65537)  AE REQ a,b (flag)  B0 RSUBI a,b,imm  B1 RSHR1 a,b
//  B2 RMULF a,b,c,d  B3 RMASK a  B4 RKINV a,b (imm = 65537)  B5 RDP a,b,c (imm = 65537)  B7 RADD2 a,b,c  B8 RCSUB a,b
// Montgomery arithmetic works modulo the register loaded by RMSEL (odd, top bit set). One clock, one engine at a time.
module bn_engine (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [7:0]   op,
    input  wire [5:0]   ra, rb, rc, rd,
    input  wire [31:0]  imm0,
    output reg          done,
    output reg          flag,
    output reg          bus_busy,
    output reg          bw_en, output reg [1:0] bw_space, output reg [12:0] bw_addr, output reg [7:0] bw_data,
    output reg  [1:0]   br_space, output reg [12:0] br_addr, input wire [7:0] br_data,
    input  wire         trng_valid, input wire [31:0] trng_data,
    // ECC client (16-word registers; MUL/ADD/SUB mod the selected curve modulus, see ecc_mod.vh)
    input  wire         e_start, input wire [3:0] e_op, input wire [6:0] e_d, e_a, e_b, input wire [1:0] e_msel,
    output reg          e_done, output reg e_lt,
    // external access to the register file while the engine is idle (ECC sequencer)
    input  wire [10:0]  x_ra, input wire x_we, input wire [10:0] x_wa, input wire [15:0] x_wd, output wire [15:0] x_rq,
    output wire         busy_o
);
`include "rsa_primes.vh"
`include "ecc_mod.vh"
localparam [6:0] ONEM = 7'd16, ACC = 7'd17, TMP = 7'd18, TMP2 = 7'd19;

reg [6:0] st, pret, mret, cret;
// ---------------- memories (simple dual port, registered read: address at edge t -> data usable at edge t+2) ----------------
(* ram_style="block" *) reg [15:0] rf [0:2047];
(* ram_style="block" *) reg [15:0] mm_ [0:63];
(* ram_style="block" *) reg [15:0] tm [0:255];
reg [10:0] rf_ra, rf_wa; reg [15:0] rf_rq, rf_wd; reg rf_we;
reg [5:0]  m_ra, m_wa;   reg [15:0] m_rq, m_wd;   reg m_we;
reg [7:0]  t_ra, t_wa;   reg [15:0] t_rq, t_wd;   reg t_we;
wire        eng_act = (st != 7'd0);                         // (st is declared below)
wire [10:0] rf_ra_m = eng_act ? rf_ra : x_ra;
wire        rf_we_m = eng_act ? rf_we : x_we;
wire [10:0] rf_wa_m = eng_act ? rf_wa : x_wa;
wire [15:0] rf_wd_m = eng_act ? rf_wd : x_wd;
always @(posedge clk) begin if (rf_we_m) rf[rf_wa_m] <= rf_wd_m; rf_rq <= rf[rf_ra_m]; end
assign x_rq = rf_rq;
assign busy_o = eng_act;
always @(posedge clk) begin if (m_we) mm_[m_wa] <= m_wd; m_rq <= mm_[m_ra]; end
always @(posedge clk) begin if (t_we) tm[t_wa] <= t_wd; t_rq <= tm[t_ra]; end

// shared multipliers
reg [15:0] m3a, m3b; reg [31:0] m3p; always @(posedge clk) m3p <= m3a * m3b;           // preamble / Newton / RMULF
reg [16:0] ka, kb;   reg [33:0] kp;  always @(posedge clk) kp <= ka * kb;               // 17x17 (mod 65537 arithmetic)
reg [31:0] pa, pn;   reg [15:0] bi, mreg, aq, nq;
always @(posedge clk) begin pa <= aq * bi; pn <= nq * mreg; end                          // Montgomery pipeline multipliers

// ---------------- states ----------------
localparam [6:0]
  S_IDLE=0, S_FIN=1,
  E_INIT=2, E_A=3, E_B=4, E_C=5, E_D=6, E_E=7, E_F=8, E_G=9, E_FIN=10, E_FIN2=11, E_FIN3=12, E_RED=13,
  M_INIT=14, M_Z=15, M_R0=16, M_R1=17, M_R2=18, M_R3=19, M_R4=20, M_R5=21, M_R6=22, M_R7=23, M_R8=24, M_S=25, M_DR=26, M_NX=27,
  C_GO=28, C_FGE=29, C_FWR=30,
  LD_A=31, LD_B=32, LD_C=33, SB_A=34, SB_B=35, SB_C=36, SB_D=37, SB_E=38,
  RN_W=39, RN_X=40, RN_Y=41,
  MS_1=42, MS_2=43, NW_0=44, NW_1=45, NW_2=46, NW_3=47, NW_4=48, NW_5=49, NW_6=50, NW_7=51, NW_8=52,
  R2_1=53, R2_2=54, R2_3=55,
  EX_0=56, EX_1=57, EX_2=58, EX_3=59, EX_4=60, EX_5=61, EX_6=62, EX_7=63,
  SV_0=64, SV_1=65, SV_2=66, SV_3=67, SV_4=68,
  RM_1=69, EQ_1=70, MF_Z=71, MF_R0=72, MF_R1=73, MF_R2=74, MF_A=75, MF_B=76, MF_C=77, MF_D=78, MF_E=79, MF_F=80, MF_G=81, MF_H=82, MF_I=83,
  S_EFIN=100,
  KI_0=84, KI_1=85, KI_2=86, KI_3=87, KI_4=88, KI_5=89, DP_0=90, DP_1=91, DP_2=92, DP_3=93, DP_4=94, A2_1=95, A2_2=96, SI_1=97, SH_1=98, MK_1=99;

// word engine modes
localparam PM_ADD=0, PM_SUBM=1, PM_COPY=2, PM_FGE=3, PM_FWR=4, PM_EQ=5, PM_SHR=6, PM_SUBI=7, PM_MASK=8, PM_ADD2LO=9, PM_ADD2HI=10,
           PM_NEGM=11, PM_FILL=12, PM_REM=13, PM_TOM=14, PM_FROMT=15, PM_DP=16,
           PM_LT=17, PM_XOR=18, PM_AND=19, PM_OR=20, PM_BSWAP=21, PM_TOMK=22;
reg [5:0]  pm; reg [6:0] pdst, psb, psc; reg [7:0] ptoff; reg [31:0] pimm; reg [16:0] pk;
reg [6:0]  pj;
reg [15:0] X, Y, Z, W, pv;
reg [19:0] cy; reg [1:0] cc; reg ge, neq;
reg signed [23:0] racc;
reg [16:0] pe_res;
wire       pdown = (pm == PM_SHR);
wire [15:0] immw = (pj == 7'd0) ? pimm[15:0] : (pj == 7'd1) ? pimm[31:16] : 16'd0;
wire [16:0] sumA  = {1'b0, X} + {1'b0, Y} + {16'd0, cy[0]};
wire [17:0] sumS  = {2'b0, X} + {2'b0, Z} + {2'b0, ~Y} + {16'd0, cy[1:0]};
wire [16:0] dWZ   = {1'b0, W} - {1'b0, Z} - {16'd0, cy[0]};
wire [16:0] dNZ   = 17'd0 - {1'b0, Z} - {16'd0, cy[0]};
wire [16:0] dXI   = {1'b0, X} - {1'b0, immw} - {16'd0, cy[0]};
wire [16:0] dXY   = {1'b0, X} - {1'b0, Y} - {16'd0, cy[0]};
wire [16:0] sumH  = {1'b0, X} + {16'd0, cy[0]};
wire [33:0] kadd  = kp + {14'd0, cy} + {33'd0, pj == 7'd0};
wire [16:0] dpd   = {1'b0, kadd[15:0]} - {1'b0, pv} - {15'd0, cc};
wire [17:0] dps   = {2'b0, dpd[15:0]} + {2'b0, pv} + {16'd0, cc};

// ECC / RSA geometry: RSA = 64 words per register ({reg[4:0], word[5:0]}), ECC = 16 words ({reg[6:0], word[3:0]})
reg        emode; reg [1:0] msel_r;
wire [5:0] nlast = emode ? 6'd15 : 6'd63;
wire [7:0] tnw   = {2'b0, nlast} + 8'd1;
function [10:0] rfa(input [6:0] r, input [5:0] w);
    rfa = emode ? {r[6:0], w[3:0]} : {r[4:0], w[5:0]};
endfunction
// composite / macro state
reg [6:0]  cdst, cs1, cs2; reg [2:0] ckind;
reg [7:0]  o_op; reg [4:0] o_a, o_b, o_c, o_d; reg [31:0] o_imm;
reg [3:0]  cnt4; reg [9:0] bitc; reg ebit;
reg [7:0]  kk; reg [6:0] k7;
reg [7:0]  hi_b; reg [5:0] wq; reg [31:0] rw; reg [5:0] rj;
reg [1:0]  sp_o; reg [12:0] off_o;
// Montgomery pipeline
reg [6:0]  msa, msb; reg [6:0] mi; reg [7:0] mk, mz;
reg [15:0] t0v, nprime, nn0, nx; reg [1:0] nit;
reg [2:0]  vq; reg [6:0] jq0, jq1; reg [6:0] j1, j2; reg v1, v2;
reg [15:0] tt, tt0, lq; reg [6:0] j0; reg v0; reg [32:0] c1, c2, pn2; reg [15:0] t64v; reg t64p;
wire [32:0] s2 = {17'd0, tt} + {1'b0, pa} + c1;
wire [32:0] w3 = {17'd0, lq} + pn2 + c2;
// sieve
reg [7:0]  spi; reg [9:0] sq; reg [10:0] sacc; reg [15:0] sw; reg [4:0] sbit;
wire [11:0] sv_t2 = {sacc, sw[15]};
// small modular arithmetic mod 65537
reg [16:0] kx, kr; reg [4:0] kn; reg kphase;
reg [16:0] kK;
// mulmod: P = hi*2^16 + lo with hi <= 65536: (lo - hi) mod 65537. kp[33:16] is hi (<= 65536).
wire [17:0] khi = kp[33:16]; wire [16:0] klo = {1'b0, kp[15:0]};
wire signed [18:0] kdiff = $signed({2'b0, klo}) - $signed({1'b0, khi});
wire [16:0] kmod = (kdiff < 0) ? (kdiff + 19'sd65537) : kdiff[16:0];
// RMULF
reg [7:0] tw; reg [32:0] mcar; reg [15:0] tv;
wire [32:0] mfs = {17'd0, tv} + {1'b0, m3p} + mcar;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st <= S_IDLE; done <= 0; e_done <= 0; e_lt <= 0; emode <= 0; flag <= 0; bus_busy <= 0; bw_en <= 0; rf_we <= 0; m_we <= 0; t_we <= 0;
        vq <= 0; v0 <= 0; v1 <= 0; v2 <= 0; t64p <= 0;
    end else begin
        done <= 0; e_done <= 0; bw_en <= 0; rf_we <= 0; m_we <= 0; t_we <= 0;
        // ---------------- Montgomery pipeline (free-running; the stream state feeds it) ----------------
        // element k: address issued at edge e_k; rq valid at e_k+2 (stage 0); product pa/pn at e_k+3 (stage 1); sum at e_k+4 (stage 2); write at e_k+5
        jq1 <= jq0; vq <= {vq[1:0], 1'b0}; v0 <= 0; v1 <= 0; v2 <= 0;
        if (vq[1]) begin aq <= (jq1 == tnw[6:0]) ? 16'd0 : rf_rq; nq <= (jq1 == tnw[6:0]) ? 16'd0 : m_rq; tt0 <= t_rq; j0 <= jq1; v0 <= 1; end
        if (v0) begin tt <= tt0; j1 <= j0; v1 <= 1; end
        if (v1) begin c1 <= {16'd0, s2[32:16]}; lq <= s2[15:0]; pn2 <= {1'b0, pn}; j2 <= j1; v2 <= 1; end
        if (v2) begin
            c2 <= {16'd0, w3[32:16]};
            if (j2 != 7'd0) begin t_we <= 1; t_wa <= {1'b0, j2} - 8'd1; t_wd <= w3[15:0]; end
            if (j2 == tnw[6:0]) begin t64p <= 1; t64v <= c1[15:0] + w3[32:16]; end
        end
        if (t64p) begin t_we <= 1; t_wa <= tnw; t_wd <= t64v; t64p <= 0; end
        case (st)
        S_IDLE: if (e_start) begin
            emode <= 1'b1; msel_r <= e_msel; flag <= 0;
            case (e_op)
            4'd0: begin cdst <= e_d; cs1 <= e_a; cs2 <= e_b; ckind <= 3'd0; cret <= S_EFIN; st <= C_GO; end
            4'd1: begin cdst <= e_d; cs1 <= e_a; cs2 <= e_b; ckind <= 3'd1; cret <= S_EFIN; st <= C_GO; end
            4'd2: begin cdst <= e_d; cs1 <= e_a; cs2 <= e_b; ckind <= 3'd2; cret <= S_EFIN; st <= C_GO; end
            4'd3: begin pm <= PM_XOR;   pdst <= e_d; psb <= e_a; psc <= e_b; ptoff <= 0; pimm <= 0; pret <= S_EFIN; st <= E_INIT; end
            4'd4: begin pm <= PM_AND;   pdst <= e_d; psb <= e_a; psc <= e_b; ptoff <= 0; pimm <= 0; pret <= S_EFIN; st <= E_INIT; end
            4'd5: begin pm <= PM_OR;    pdst <= e_d; psb <= e_a; psc <= e_b; ptoff <= 0; pimm <= 0; pret <= S_EFIN; st <= E_INIT; end
            4'd6: begin pm <= PM_BSWAP; pdst <= e_d; psb <= e_a; psc <= e_a; ptoff <= 0; pimm <= 0; pret <= S_EFIN; st <= E_INIT; end
            4'd7: begin pm <= PM_LT;    pdst <= e_d; psb <= e_a; psc <= e_b; ptoff <= 0; pimm <= 0; pret <= S_EFIN; st <= E_INIT; end
            default: begin pm <= PM_TOMK; pdst <= 7'd0; psb <= 7'd0; psc <= 7'd0; ptoff <= 0; pimm <= 0; pret <= S_EFIN; st <= E_INIT; end   // 8: select modulus
            endcase
        end else if (start) begin
            emode <= 1'b0;
            o_op <= op; o_a <= ra[4:0]; o_b <= rb[4:0]; o_c <= rc[4:0]; o_d <= rd[4:0]; o_imm <= imm0; flag <= 0;
            sp_o <= imm0[31:30]; off_o <= imm0[29:17];
            case (op)
            8'hA0: begin bus_busy <= 1; rj <= 0; wq <= 0; st <= LD_A; end
            8'hA1: begin bus_busy <= 1; wq <= 6'd63; st <= SB_A; end
            8'hA2: begin rj <= 0; st <= RN_W; end
            8'hA3: begin pm <= PM_FILL; pdst <= ra[4:0]; psb <= 5'd0; psc <= 5'd0; ptoff <= 0; pimm <= imm0; pret <= S_FIN; st <= E_INIT; end
            8'hA5: begin pm <= PM_TOM; pdst <= 5'd0; psb <= ra[4:0]; psc <= ra[4:0]; ptoff <= 0; pimm <= 0; pret <= MS_1; st <= E_INIT; end
            8'hA6: begin cdst <= TMP2; cs1 <= ONEM; cs2 <= ONEM; ckind <= 3'd1; cret <= R2_1; cnt4 <= 0; st <= C_GO; end
            8'hA7: begin cdst <= ra[4:0]; cs1 <= rb[4:0]; cs2 <= rc[4:0]; ckind <= 3'd0; cret <= S_FIN; st <= C_GO; end
            8'hA8: begin cdst <= ra[4:0]; cs1 <= rb[4:0]; cs2 <= rc[4:0]; ckind <= 3'd1; cret <= S_FIN; st <= C_GO; end
            8'hA9: begin cdst <= ra[4:0]; cs1 <= rb[4:0]; cs2 <= rc[4:0]; ckind <= 3'd2; cret <= S_FIN; st <= C_GO; end
            8'hB8: begin cdst <= ra[4:0]; cs1 <= rb[4:0]; cs2 <= rb[4:0]; ckind <= 3'd3; cret <= S_FIN; st <= C_GO; end
            8'hAA: begin cdst <= ACC; cs1 <= ONEM; cs2 <= ONEM; ckind <= 3'd3; cret <= EX_0; bitc <= (rd != 6'd0) ? {rd[5:0], 4'hF} : 10'd1023; st <= C_GO; end
            8'hAB: begin spi <= 0; st <= SV_0; end
            8'hAC: begin pm <= PM_REM; pdst <= 5'd0; psb <= ra[4:0]; psc <= ra[4:0]; ptoff <= 0; pimm <= 0; pret <= RM_1; st <= E_INIT; end
            8'hAE: begin pm <= PM_EQ; pdst <= 5'd0; psb <= ra[4:0]; psc <= rb[4:0]; ptoff <= 0; pimm <= 0; pret <= EQ_1; st <= E_INIT; end
            8'hB0: begin pm <= PM_SUBI; pdst <= ra[4:0]; psb <= rb[4:0]; psc <= rb[4:0]; ptoff <= 0; pimm <= imm0; pret <= S_FIN; st <= E_INIT; end
            8'hB1: begin pm <= PM_SHR; pdst <= ra[4:0]; psb <= rb[4:0]; psc <= rb[4:0]; ptoff <= 0; pimm <= 0; pret <= S_FIN; st <= E_INIT; end
            8'hB3: begin pm <= PM_MASK; pdst <= ra[4:0]; psb <= ra[4:0]; psc <= ra[4:0]; ptoff <= 0; pimm <= 0; pret <= S_FIN; st <= E_INIT; end
            8'hB2: begin mz <= 0; st <= MF_Z; end
            8'hB4: begin pm <= PM_REM; pdst <= 5'd0; psb <= rb[4:0]; psc <= rb[4:0]; ptoff <= 0; pimm <= 0; pret <= KI_0; st <= E_INIT; end
            8'hB5: begin rj <= 0; st <= DP_0; end
            8'hB7: begin pm <= PM_ADD2LO; pdst <= ra[4:0]; psb <= ra[4:0]; psc <= rc[4:0]; ptoff <= 0; pimm <= 0; pret <= A2_1; st <= E_INIT; end
            default: begin done <= 1; end
            endcase
        end
        S_FIN: begin done <= 1; bus_busy <= 0; st <= S_IDLE; end
        S_EFIN: begin e_done <= 1; st <= S_IDLE; end

        // ================= word engine =================
        E_INIT: begin
            pj <= pdown ? {1'b0, nlast} : 7'd0; pv <= 0; cc <= 0; neq <= 0; racc <= 0;
            if (pm == PM_SUBM) cy <= 20'd1;
            else if (pm != PM_ADD2HI) cy <= 20'd0;
            st <= E_A;
        end
        E_A: begin rf_ra <= rfa(psb, (pm == PM_BSWAP) ? (nlast - pj[5:0]) : pj[5:0]); m_ra <= pj[5:0]; t_ra <= {1'b0, pj} + ptoff; st <= E_B; end
        E_B: st <= E_C;
        E_C: begin X <= rf_rq; Z <= m_rq; W <= t_rq; rf_ra <= rfa(psc, pj[5:0]); st <= E_D; end
        E_D: begin ka <= pk; kb <= {1'b0, X}; st <= E_E; end
        E_E: begin Y <= rf_rq; st <= E_F; end                               // kp = pk*X is valid from here
        E_F: begin
            st <= E_G;
            case (pm)
            PM_ADD:   begin t_we <= 1; t_wa <= {1'b0, pj}; t_wd <= sumA[15:0]; cy <= {19'd0, sumA[16]}; end
            PM_SUBM:  begin t_we <= 1; t_wa <= {1'b0, pj}; t_wd <= sumS[15:0]; cy <= {18'd0, sumS[17:16]}; end
            PM_COPY:  begin t_we <= 1; t_wa <= {1'b0, pj}; t_wd <= X; end
            PM_FGE:   cy <= {19'd0, dWZ[16]};
            PM_FWR:   begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= ge ? dWZ[15:0] : W; cy <= {19'd0, dWZ[16]}; end
            PM_EQ:    if (X != Y) neq <= 1;
            PM_SHR:   begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= {cy[0], X[15:1]}; cy <= {19'd0, X[0]}; end
            PM_SUBI:  begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= dXI[15:0]; cy <= {19'd0, dXI[16]}; end
            PM_MASK:  begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= X | ((pj == 7'd0) ? 16'h0003 : 16'h0) | ((pj == {1'b0, nlast}) ? 16'hC000 : 16'h0); end
            PM_ADD2LO: begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= sumA[15:0]; cy <= {19'd0, sumA[16]}; end
            PM_ADD2HI: begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= sumH[15:0]; cy <= {19'd0, sumH[16]}; end
            PM_NEGM:  begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= dNZ[15:0]; cy <= {19'd0, dNZ[16]}; end
            PM_FILL:  begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= immw; end
            PM_REM:   racc <= pj[0] ? racc - $signed({8'd0, X}) : racc + $signed({8'd0, X});
            PM_LT:    cy <= {19'd0, dXY[16]};
            PM_XOR:   begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= X ^ Y; end
            PM_AND:   begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= X & Y; end
            PM_OR:    begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= X | Y; end
            PM_BSWAP: begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= {X[7:0], X[15:8]}; end
            PM_TOMK:  begin m_we <= 1; m_wa <= pj[5:0]; m_wd <= mod_word(msel_r, pj[3:0]); end
            PM_TOM:   begin m_we <= 1; m_wa <= pj[5:0]; m_wd <= X; end
            PM_FROMT: begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= W; end
            PM_DP:    begin
                if (pj < 7'd64) begin rf_we <= 1; rf_wa <= rfa(pdst, pj[5:0]); rf_wd <= dpd[15:0]; end
                cy <= {2'd0, kadd[33:16]}; cc <= dps[17:16]; pv <= dpd[15:0];
            end
            default: ;
            endcase
        end
        E_G: begin
            if (pdown ? (pj == 7'd0) : (pj == {1'b0, nlast})) st <= E_FIN;
            else begin pj <= pdown ? pj - 7'd1 : pj + 7'd1; st <= E_A; end
        end
        E_FIN: begin
            st <= E_FIN2;
            case (pm)
            PM_ADD:  begin t_we <= 1; t_wa <= tnw; t_wd <= {15'd0, cy[0]}; end
            PM_SUBM: begin t_we <= 1; t_wa <= tnw; t_wd <= {14'd0, cy[1:0]} - 16'd1; end
            PM_COPY: begin t_we <= 1; t_wa <= tnw; t_wd <= 16'd0; end
            PM_FGE:  t_ra <= tnw;
            default: ;
            endcase
        end
        E_FIN2: st <= E_FIN3;
        E_FIN3: begin
            if (pm == PM_FGE) ge <= (t_rq != 16'd0) || !cy[0];
            if (pm == PM_LT) e_lt <= cy[0];
            if (pm == PM_TOMK) nprime <= mod_n0(msel_r);
            if (pm == PM_REM) st <= E_RED; else st <= pret;
        end
        E_RED: begin
            if (racc < 0) racc <= racc + 24'sd65537;
            else if (racc >= 24'sd65537) racc <= racc - 24'sd65537;
            else begin pe_res <= racc[16:0]; st <= pret; end
        end

        // ================= Montgomery multiply: T <= A*B/R (before final reduction) =================
        M_INIT: begin mi <= 0; mz <= 0; st <= M_Z; end
        M_Z: begin t_we <= 1; t_wa <= mz; t_wd <= 16'd0; mz <= mz + 8'd1; if (mz == tnw + 8'd1) st <= M_R0; end
        M_R0: begin rf_ra <= rfa(msb, mi[5:0]); st <= M_R1; end
        M_R1: st <= M_R2;
        M_R2: begin bi <= rf_rq; rf_ra <= rfa(msa, 6'd0); t_ra <= 8'd0; m_ra <= 6'd0; st <= M_R3; end
        M_R3: st <= M_R4;
        M_R4: begin m3a <= rf_rq; m3b <= bi; t0v <= t_rq; st <= M_R5; end
        M_R5: st <= M_R6;
        M_R6: begin m3a <= t0v + m3p[15:0]; m3b <= nprime; st <= M_R7; end
        M_R7: st <= M_R8;
        M_R8: begin mreg <= m3p[15:0]; c1 <= 0; c2 <= 0; mk <= 0; st <= M_S; end
        M_S: begin
            rf_ra <= rfa(msa, mk[5:0]); t_ra <= mk; m_ra <= mk[5:0];
            vq[0] <= 1; jq0 <= mk[6:0]; mk <= mk + 8'd1;
            if (mk == tnw) st <= M_DR;
        end
        M_DR: if (!vq[0] && !vq[1] && !vq[2] && !v0 && !v1 && !v2 && !t64p && !t_we) st <= M_NX;
        M_NX: begin
            if (mi == {1'b0, nlast}) st <= mret;
            else begin mi <= mi + 7'd1; st <= M_R0; end
        end

        // ================= composite: kind 0 MUL, 1 ADDM, 2 SUBM, 3 CSUB(copy) -> reduce -> RF[cdst] =================
        C_GO: begin
            psb <= cs1; psc <= cs2; ptoff <= 0; pimm <= 0; pdst <= cdst;
            case (ckind)
            3'd0: begin msa <= cs1; msb <= cs2; mret <= C_FGE; st <= M_INIT; end
            3'd1: begin pm <= PM_ADD;  pret <= C_FGE; st <= E_INIT; end
            3'd2: begin pm <= PM_SUBM; pret <= C_FGE; st <= E_INIT; end
            default: begin pm <= PM_COPY; pret <= C_FGE; st <= E_INIT; end
            endcase
        end
        C_FGE: begin pm <= PM_FGE; pret <= C_FWR; st <= E_INIT; end
        C_FWR: begin pm <= PM_FWR; pdst <= cdst; pret <= cret; st <= E_INIT; end

        // ================= RLDB / RSTB (byte bus) =================
        LD_A: begin br_space <= sp_o; br_addr <= off_o + {6'd0, rj, 1'b0} + {12'd0, wq[0]}; st <= LD_B; end
        LD_B: st <= LD_C;
        LD_C: begin
            if (!wq[0]) begin hi_b <= br_data; wq[0] <= 1; st <= LD_A; end
            else begin
                rf_we <= 1; rf_wa <= {o_a, 6'd63 - rj[5:0]}; rf_wd <= {hi_b, br_data}; wq[0] <= 0;
                if (rj == 6'd63) st <= S_FIN; else begin rj <= rj + 6'd1; st <= LD_A; end
            end
        end
        SB_A: begin rf_ra <= {o_a, wq}; st <= SB_B; end
        SB_B: st <= SB_C;
        SB_C: begin hi_b <= rf_rq[15:8]; rw[7:0] <= rf_rq[7:0]; st <= SB_D; end
        SB_D: begin bw_en <= 1; bw_space <= sp_o; bw_addr <= off_o + {6'd0, 6'd63 - wq, 1'b0}; bw_data <= hi_b; st <= SB_E; end
        SB_E: begin
            bw_en <= 1; bw_space <= sp_o; bw_addr <= off_o + {6'd0, 6'd63 - wq, 1'b0} + 13'd1; bw_data <= rw[7:0];
            if (wq == 6'd0) st <= S_FIN; else begin wq <= wq - 6'd1; st <= SB_A; end
        end

        // ================= RRNG =================
        RN_W: if (trng_valid) begin
            rw <= trng_data; rf_we <= 1; rf_wa <= {o_a, rj[4:0], 1'b0}; rf_wd <= trng_data[15:0]; st <= RN_X;
        end
        RN_X: begin rf_we <= 1; rf_wa <= {o_a, rj[4:0], 1'b1}; rf_wd <= rw[31:16]; if (rj == 6'd31) st <= S_FIN; else begin rj <= rj + 6'd1; st <= RN_W; end end

        // ================= RMSEL: M <= RF[a]; ONEM = 2^1024 - M; nprime =============
        MS_1: begin pm <= PM_NEGM; pdst <= ONEM; psb <= ONEM; psc <= ONEM; ptoff <= 0; pimm <= 0; pret <= NW_0; st <= E_INIT; end
        NW_0: begin m_ra <= 6'd0; st <= NW_1; end
        NW_1: st <= NW_2;
        NW_2: begin nn0 <= m_rq; nx <= m_rq; nit <= 0; st <= NW_3; end
        NW_3: begin m3a <= nn0; m3b <= nx; st <= NW_4; end
        NW_4: st <= NW_5;
        NW_5: begin m3a <= nx; m3b <= 16'd2 - m3p[15:0]; st <= NW_6; end
        NW_6: st <= NW_7;
        NW_7: begin nx <= m3p[15:0]; nit <= nit + 2'd1; if (nit == 2'd2) st <= NW_8; else st <= NW_3; end
        NW_8: begin nprime <= 16'd0 - nx; st <= S_FIN; end

        // ================= RR2: R^2 mod M = (2R)^(2^10) in Montgomery arithmetic =================
        R2_1: begin cdst <= TMP2; cs1 <= TMP2; cs2 <= TMP2; ckind <= 3'd0; cnt4 <= cnt4 + 4'd1;
                    cret <= (cnt4 == 4'd9) ? R2_2 : R2_1; st <= C_GO; end
        R2_2: begin cdst <= o_a; cs1 <= TMP2; cs2 <= TMP2; ckind <= 3'd3; cret <= S_FIN; st <= C_GO; end

        // ================= REXP: acc = ONEM; for bit 1023..0: acc = acc^2; t = acc*b; if bit acc = t =================
        EX_0: begin rf_ra <= {o_c, bitc[9:4]}; st <= EX_1; end
        EX_1: st <= EX_2;
        EX_2: begin ebit <= rf_rq[bitc[3:0]]; cdst <= ACC; cs1 <= ACC; cs2 <= ACC; ckind <= 3'd0; cret <= EX_3; st <= C_GO; end
        EX_3: begin cdst <= ebit ? ACC : TMP; cs1 <= ACC; cs2 <= o_b; ckind <= 3'd0; cret <= EX_4; st <= C_GO; end
        EX_4: begin
            if (bitc == 10'd0) begin cdst <= o_a; cs1 <= ACC; cs2 <= ACC; ckind <= 3'd3; cret <= S_FIN; st <= C_GO; end
            else begin bitc <= bitc - 10'd1; st <= EX_0; end
        end

        // ================= RSIEVE: flag = (RF[a] divisible by one of the 171 odd primes below 1024) =================
        SV_0: begin sq <= sprime(spi); sacc <= 0; rj <= 6'd63; st <= SV_1; end
        SV_1: begin rf_ra <= {o_a, rj}; st <= SV_2; end
        SV_2: st <= SV_3;
        SV_3: begin sw <= rf_rq; sbit <= 0; st <= SV_4; end
        SV_4: begin
            // acc = (2*acc + bit) mod q, MSB first
            if (sv_t2 >= {2'b0, sq}) sacc <= sv_t2 - {2'b0, sq}; else sacc <= sv_t2[10:0];
            sw <= {sw[14:0], 1'b0}; sbit <= sbit + 5'd1;
            if (sbit == 5'd15) begin
                if (rj == 6'd0) st <= SI_1; else begin rj <= rj - 6'd1; st <= SV_1; end
            end
        end
        SI_1: begin
            if (sacc == 0) begin flag <= 1; st <= S_FIN; end
            else if (spi == 8'd170) begin flag <= 0; st <= S_FIN; end
            else begin spi <= spi + 8'd1; st <= SV_0; end
        end

        // ================= RREM1 / REQ =================
        RM_1: begin flag <= (pe_res == 17'd1); st <= S_FIN; end
        EQ_1: begin flag <= !neq; st <= S_FIN; end

        // ================= RMULF: (lo,hi) = c*d (operand scanning in T) =================
        MF_Z: begin t_we <= 1; t_wa <= mz; t_wd <= 16'd0; mz <= mz + 8'd1; if (mz == 8'd127) begin mi <= 0; st <= MF_R0; end end
        MF_R0: begin rf_ra <= {o_d, mi[5:0]}; st <= MF_R1; end
        MF_R1: st <= MF_R2;
        MF_R2: begin bi <= rf_rq; rj <= 0; mcar <= 0; st <= MF_A; end
        MF_A: begin rf_ra <= {o_c, rj[5:0]}; t_ra <= {1'b0, mi} + {2'b0, rj}; st <= MF_B; end
        MF_B: st <= MF_C;
        MF_C: begin m3a <= rf_rq; m3b <= bi; tv <= t_rq; st <= MF_D; end
        MF_D: st <= MF_E;
        MF_E: begin t_we <= 1; t_wa <= {1'b0, mi} + {2'b0, rj}; t_wd <= mfs[15:0]; mcar <= {16'd0, mfs[32:16]}; st <= MF_F; end
        MF_F: begin
            if (rj == 6'd63) begin t_we <= 1; t_wa <= {1'b0, mi} + 8'd64; t_wd <= mcar[15:0]; st <= MF_G; end
            else begin rj <= rj + 6'd1; st <= MF_A; end
        end
        MF_G: begin
            if (mi == 7'd63) begin pm <= PM_FROMT; pdst <= o_a; psb <= 5'd0; psc <= 5'd0; ptoff <= 8'd0; pimm <= 0; pret <= MF_H; st <= E_INIT; end
            else begin mi <= mi + 7'd1; st <= MF_R0; end
        end
        MF_H: begin pm <= PM_FROMT; pdst <= o_b; psb <= 5'd0; psc <= 5'd0; ptoff <= 8'd64; pimm <= 0; pret <= S_FIN; st <= E_INIT; end

        // ================= RKINV: K = (65537 - (x mod 65537)^-1) mod 65537, x^(65535) by square-and-multiply =================
        KI_0: begin kx <= pe_res; kr <= pe_res; kn <= 5'd0; kphase <= 0; ka <= pe_res; kb <= pe_res; st <= KI_1; end
        KI_1: st <= KI_2;                                                // kp valid after this edge
        KI_2: begin
            kr <= kmod; kphase <= ~kphase;
            if (!kphase) begin ka <= kmod; kb <= kx; st <= KI_1; end                   // r*r done -> multiply by x
            else begin
                kn <= kn + 5'd1;
                if (kn == 5'd14) st <= KI_3;
                else begin ka <= kmod; kb <= kmod; st <= KI_1; end
            end
        end
        KI_3: begin kK <= 17'd65537 - kr; st <= KI_4; end
        KI_4: begin pm <= PM_FILL; pdst <= o_a; psb <= 5'd0; psc <= 5'd0; ptoff <= 0; pimm <= {15'd0, kK}; pret <= S_FIN; st <= E_INIT; end

        // ================= RDP: dp = (1 + K*pm1)/e =================
        DP_0: begin rf_ra <= {o_c, 6'd0}; st <= DP_1; end
        DP_1: begin st <= DP_2; end
        DP_2: begin kK[15:0] <= rf_rq; rf_ra <= {o_c, 6'd1}; st <= DP_3; end
        DP_3: st <= DP_4;
        DP_4: begin
            pk <= {rf_rq[0], kK[15:0]};
            pm <= PM_DP; pdst <= o_a; psb <= o_b; psc <= o_b; ptoff <= 0; pimm <= 0; pret <= S_FIN; st <= E_INIT;
        end

        // ================= RADD2: hi += carry =================
        A2_1: begin pm <= PM_ADD2HI; pdst <= o_b; psb <= o_b; psc <= o_b; pret <= S_FIN; st <= E_INIT; end
        default: st <= S_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
