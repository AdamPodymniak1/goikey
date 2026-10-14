`default_nettype none
// ML-DSA command sequencer: fetches the microcode (ref/pq/pq_asm.py ISA) and drives the polynomial unit, samplers,
// pack unit, byte unit and the SHAKE sponge. Instruction word: [31:24] op | [23:18] a | [17:12] b | [11:6] c | [5:0] d;
// ops >= 0x80 are followed by 1 (BCMP/BCPY/WIMM: 2) immediate words. The unit-select decode below mirrors pq_asm.OPS.
module pq_seq (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         go,
    input  wire [12:0]  entry,
    input  wire [15:0]  plen,
    output reg          done,
    output reg  [7:0]   status,
    output reg  [15:0]  tx_len,
    output wire         busy,
    output wire         g2sel_o,              // gamma2 selector (PARAM) for the polynomial unit
    // polynomial unit
    output reg          p_start, output reg [4:0] p_op, output reg [5:0] p_sa, p_sb, p_sc, output reg [31:0] p_bound,
    input  wire         p_done, input wire p_flag, input wire [8:0] p_hints,
    // samplers
    output reg          s_start, output reg [2:0] s_mode, output reg [5:0] s_dst, output reg [7:0] s_tau,
    input  wire         s_done,
    // pack unit
    output reg          k_start, output reg [3:0] k_op, output reg [5:0] k_slot, output reg [1:0] k_space, output reg [12:0] k_base,
    output reg          k_eta4, k_g1sel, k_g2sel, output reg [7:0] k_omega, output reg [5:0] k_hidx, output reg k_hkclr,
    input  wire         k_done, input wire k_over,
    // byte unit
    output reg          b_start, output reg [3:0] b_op, output reg [1:0] b_sp1, output reg [12:0] b_off1, output reg [12:0] b_len,
    output reg  [1:0]   b_sp2, output reg [12:0] b_off2, output reg [15:0] b_imm, output reg b_flagclr,
    input  wire         b_done, input wire b_diff,
    // RSA big-number unit
    output reg          r_start, output reg [7:0] r_op, output reg [5:0] r_a, r_b, r_c, r_d, output reg [31:0] r_imm,
    input  wire         r_done, input wire r_flag,
    // SHAKE control
    output reg          sh_init, output reg sh_mode256, output reg sh_fin, input wire sh_ready
);
// ---- microcode ROM ----
(* ram_style="block" *) reg [31:0] uc [0:4095];             // ML-DSA / info programs
(* ram_style="block" *) reg [31:0] uc2 [0:511];              // RSA programs (addresses 4096..)
initial begin
`include "pq_ucode.vh"
end
reg [12:0] pc; reg [31:0] uq1, uq2; reg pcs;
always @(posedge clk) begin uq1 <= uc[pc[11:0]]; uq2 <= uc2[pc[8:0]]; pcs <= pc[12]; end
wire [31:0] uq = pcs ? uq2 : uq1;

localparam Q_IDLE=0, Q_F1=1, Q_F2=2, Q_I1=3, Q_I1W=4, Q_I1C=5, Q_I2=6, Q_I2W=7, Q_I2C=8, Q_X=9, Q_W=10, Q_POST=11, Q_SH=12, Q_FIN=13;
reg [3:0]  st;
reg [31:0] ins, imm0, imm1;
reg [7:0]  op; reg [5:0] fa, fb, fc, fd;
reg        flag, xf;
reg [11:0] hcnt; reg [15:0] nz;
reg        eta4, g1sel, g2sel; reg [7:0] tau, lcnt, omega;
reg        busy_r;
assign busy = busy_r;
assign g2sel_o = g2sel;

wire [1:0]  d_sp  = imm0[31:30];
wire [12:0] d_off = imm0[29:17];
wire [12:0] d_len = imm0[16:4];
wire [1:0]  e_sp  = imm1[31:30];
wire [12:0] e_off = imm1[29:17];

function [1:0] imm_count(input [7:0] o);
    case (o)
        8'h86, 8'h87, 8'h9C, 8'h9F: imm_count = 2'd2;             // BCMP BCPY WIMM BFILL
        8'hA2, 8'hA5, 8'hA6, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hAE, 8'hB1, 8'hB2, 8'hB3, 8'hB7, 8'hB8: imm_count = 2'd0;   // RSA ops without immediates
        default: imm_count = (o >= 8'h80) ? 2'd1 : 2'd0;
    endcase
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st <= Q_IDLE; busy_r <= 0; done <= 0; r_start <= 0; p_start <= 0; s_start <= 0; k_start <= 0; b_start <= 0; sh_init <= 0; sh_fin <= 0;
        k_hkclr <= 0; b_flagclr <= 0; flag <= 0; xf <= 0; hcnt <= 0; nz <= 0; pc <= 0; status <= 0; tx_len <= 0;
        eta4 <= 0; g1sel <= 0; g2sel <= 0; tau <= 0; lcnt <= 0; omega <= 0;
    end else begin
        done <= 0; r_start <= 0; p_start <= 0; s_start <= 0; k_start <= 0; b_start <= 0; sh_init <= 0; sh_fin <= 0; k_hkclr <= 0; b_flagclr <= 0;
        case (st)
        Q_IDLE: if (go) begin
            pc <= entry[12:0]; busy_r <= 1; flag <= 0; xf <= 0; st <= Q_F1;
        end
        Q_F1: begin st <= Q_F2; end                                // ROM read latency (pc presented)
        Q_F2: begin ins <= uq; st <= Q_I1; end
        Q_I1: begin
            op <= ins[31:24]; fa <= ins[23:18]; fb <= ins[17:12]; fc <= ins[11:6]; fd <= ins[5:0];
            pc <= pc + 13'd1;
            if (imm_count(ins[31:24]) == 2'd0) st <= Q_X;
            else st <= Q_I1W;
        end
        Q_I1W: st <= Q_I1C;                                        // pc already points at the first immediate word
        Q_I1C: begin imm0 <= uq; pc <= pc + 13'd1; if (imm_count(op) == 2'd2) st <= Q_I2W; else st <= Q_X; end
        Q_I2W: st <= Q_I2C;
        Q_I2C: begin imm1 <= uq; pc <= pc + 13'd1; st <= Q_X; end
        Q_X: begin
            st <= Q_W;                                              // default: wait for a unit
            case (op)
            8'h00: st <= Q_F1;
            // ---- polynomial unit ----
            8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E: begin
                p_start <= 1; p_op <= op[4:0] - 5'd2; p_sa <= fa; p_sb <= fb; p_sc <= fc; p_bound <= 32'd0;
            end
            8'h89: begin p_start <= 1; p_op <= 5'd13; p_sa <= fa; p_sb <= 6'd0; p_sc <= 6'd0; p_bound <= imm0; end   // CHKN
            // ---- samplers ----
            8'h0F: begin s_start <= 1; s_mode <= 3'd0; s_dst <= fa; s_tau <= tau; end
            8'h10: begin s_start <= 1; s_mode <= eta4 ? 3'd2 : 3'd1; s_dst <= fa; s_tau <= tau; end
            8'h11: begin s_start <= 1; s_mode <= g1sel ? 3'd4 : 3'd3; s_dst <= fa; s_tau <= tau; end
            8'h12: begin s_start <= 1; s_mode <= 3'd5; s_dst <= fa; s_tau <= tau; end
            // ---- SHAKE control ----
            8'h13: begin sh_init <= 1; sh_mode256 <= (fa != 0); st <= Q_F1; end
            8'h14: st <= Q_SH;
            // ---- scalar state ----
            8'h16: begin hcnt <= 0; k_hkclr <= 1; st <= Q_F1; end
            8'h17: begin nz <= 0; st <= Q_F1; end
            8'h18: begin nz <= nz + {8'd0, lcnt}; st <= Q_F1; end
            8'h1A: begin flag <= ~flag; st <= Q_F1; end
            8'h1B: begin flag <= 0; st <= Q_F1; end
            8'h1C: begin flag <= 1; st <= Q_F1; end
            8'h1D: begin xf <= 0; st <= Q_F1; end
            8'h1E: begin xf <= 1; st <= Q_F1; end
            8'h80: begin eta4 <= fa[0]; g1sel <= fb[0]; g2sel <= fc[0]; tau <= imm0[7:0]; lcnt <= imm0[15:8]; omega <= imm0[23:16]; st <= Q_F1; end
            // ---- byte unit ----
            8'h15: begin b_start <= 1; b_op <= 4'd10; b_sp1 <= 0; b_off1 <= 0; b_len <= 0; b_sp2 <= 0; b_off2 <= 0; b_imm <= 0; end
            8'h81: begin b_start <= 1; b_op <= 4'd0; b_sp1 <= d_sp; b_off1 <= d_off; b_len <= d_len; end
            8'h9A: begin b_start <= 1; b_op <= 4'd7; b_sp1 <= 2'd0; b_off1 <= imm0[12:0]; b_len <= 0; end
            8'h82: begin b_start <= 1; b_op <= 4'd8; b_imm <= imm0[15:0]; b_len <= 0; end
            8'h83: begin b_start <= 1; b_op <= 4'd9; b_imm <= nz + imm0[15:0]; b_len <= 0; end
            8'h84: begin b_start <= 1; b_op <= 4'd1; b_sp1 <= d_sp; b_off1 <= d_off; b_len <= d_len; end
            8'h85: begin b_start <= 1; b_op <= 4'd2; b_sp1 <= d_sp; b_off1 <= d_off; b_len <= d_len; end
            8'h86: begin b_start <= 1; b_op <= 4'd3; b_sp1 <= d_sp; b_off1 <= d_off; b_len <= d_len; b_sp2 <= e_sp; b_off2 <= e_off; end
            8'h87: begin b_start <= 1; b_op <= 4'd4; b_sp1 <= d_sp; b_off1 <= d_off; b_len <= d_len; b_sp2 <= e_sp; b_off2 <= e_off; end
            8'h88: begin b_start <= 1; b_op <= 4'd6; b_sp1 <= d_sp; b_off1 <= d_off; b_len <= d_len; end
            8'h92: begin b_start <= 1; b_op <= 4'd5; b_sp1 <= d_sp; b_off1 <= d_off; b_len <= d_len; end
            8'h9F: begin b_start <= 1; b_op <= 4'd13; b_sp1 <= d_sp; b_off1 <= d_off; b_len <= d_len; b_imm <= {8'd0, imm1[7:0]}; end
            8'h9B: begin b_start <= 1; b_op <= 4'd11; b_sp1 <= d_sp; b_off1 <= d_off; b_len <= 0; end
            8'h9C: begin b_start <= 1; b_op <= 4'd12; b_sp1 <= d_sp; b_off1 <= d_off; b_len <= 0; b_imm <= imm1[15:0]; end
            // ---- pack unit ----
            8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h8E: begin
                k_start <= 1; k_op <= op[3:0] - 4'hA; k_slot <= fa; k_space <= d_sp; k_base <= d_off;
                k_eta4 <= eta4; k_g1sel <= g1sel; k_g2sel <= g2sel; k_omega <= omega; k_hidx <= 6'd0;
            end
            8'hB9: begin k_start <= 1; k_op <= 4'd9; k_slot <= fa; k_space <= d_sp; k_base <= d_off; k_eta4 <= eta4; k_g1sel <= g1sel;
                         k_g2sel <= g2sel; k_omega <= omega; k_hidx <= 6'd0; end
            8'h8F: begin k_start <= 1; k_op <= 4'd7; k_slot <= fa; k_space <= d_sp; k_base <= d_off; k_eta4 <= eta4; k_g1sel <= g1sel;
                         k_g2sel <= g2sel; k_omega <= omega; k_hidx <= fb; end
            8'h9E: begin k_start <= 1; k_op <= 4'd8; k_slot <= fa; k_space <= d_sp; k_base <= d_off; k_eta4 <= eta4; k_g1sel <= g1sel; k_g2sel <= g2sel; k_omega <= omega; k_hidx <= 6'd0; end
            8'h90: begin k_start <= 1; k_op <= 4'd5; k_slot <= fa; k_space <= d_sp; k_base <= d_off; k_eta4 <= eta4; k_g1sel <= g1sel; k_g2sel <= g2sel; k_omega <= omega; k_hidx <= 6'd0; end
            8'h91: begin k_start <= 1; k_op <= 4'd6; k_slot <= fa; k_space <= d_sp; k_base <= d_off; k_eta4 <= eta4; k_g1sel <= g1sel; k_g2sel <= g2sel; k_omega <= omega; k_hidx <= 6'd0; end
            // ---- RSA big-number unit ----
            8'hA0, 8'hA1, 8'hA2, 8'hA3, 8'hA5, 8'hA6, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hAC, 8'hAE, 8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB7, 8'hB8: begin
                r_start <= 1; r_op <= op; r_a <= fa; r_b <= fb; r_c <= fc; r_d <= fd; r_imm <= imm0;
            end
            // ---- control ----
            8'h93: begin pc <= imm0[12:0]; st <= Q_F1; end
            8'h94: begin if (flag)  pc <= imm0[12:0]; st <= Q_F1; end
            8'h95: begin if (!flag) pc <= imm0[12:0]; st <= Q_F1; end
            8'h9D: begin if (xf)    pc <= imm0[12:0]; st <= Q_F1; end
            8'h96: begin status <= {2'd0, fa}; tx_len <= imm0[15:0]; st <= Q_FIN; end
            8'h97: begin flag <= (plen != imm0[15:0]); st <= Q_F1; end
            8'h98: begin flag <= (plen < imm0[15:0]); st <= Q_F1; end
            8'h99: begin flag <= flag | ({4'd0, hcnt} > imm0[15:0]); st <= Q_F1; end
            default: st <= Q_F1;
            endcase
        end
        Q_W: begin                                                  // wait for whichever unit was started
            if (p_done) begin
                if (op == 8'h89) flag <= flag | p_flag;
                if (op == 8'h0E) hcnt <= hcnt + {3'd0, p_hints};
                st <= Q_F1;
            end
            if (s_done) st <= Q_F1;
            if (r_done) begin if (op == 8'hAB || op == 8'hAC || op == 8'hAE) flag <= r_flag; st <= Q_F1; end
            if (k_done) begin if (op == 8'h8F) flag <= flag | k_over; st <= Q_F1; end
            if (b_done) begin if (op == 8'h86) begin flag <= flag | b_diff; b_flagclr <= 1; end st <= Q_F1; end
        end
        Q_SH: if (sh_ready) begin sh_fin <= 1; st <= Q_F1; end   // SHFIN: wait for the sponge, then pad + permute
        Q_FIN: begin done <= 1; busy_r <= 0; st <= Q_IDLE; end
        default: st <= Q_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
