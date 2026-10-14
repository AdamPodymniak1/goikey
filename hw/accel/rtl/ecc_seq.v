`default_nettype none
// ECC / command engine: executes microprograms (ISA in ref/ecc_asm.py) over a 128 x 256-bit register
// file held in block RAM, using the 16-bit-limb modular ALU. The same engine runs the complete
// command flows (payload parsing, key unwrapping, TRNG, SHA-512, response emission), so no wide
// temporary registers exist outside block RAM.
//
// host/test port: write registers while idle, read them back, h_go with an entry pc; h_done pulses
// (h_flag = 1 means FAILURE). Command port: `plen` bytes of payload at rx_a/rx_q, response bytes to
// tx_*, FIN sets f_status/f_len.
module ecc_seq #(parameter [127:0] UID = 128'h0)(
    input  wire         clk,
    input  wire         rst_n,
    // host / test access
    input  wire         h_we,
    input  wire [6:0]   h_wreg,
    input  wire [3:0]   h_wword,
    input  wire [15:0]  h_wdata,
    input  wire [6:0]   h_rreg,
    input  wire [3:0]   h_rword,
    output wire [15:0]  h_q,
    input  wire         h_go,
    input  wire [10:0]  h_pc,
    output reg          h_busy,
    output reg          h_done,
    output reg          h_flag,
    // command I/O
    input  wire [15:0]  plen,
    output reg  [12:0]  rx_a,
    input  wire [7:0]   rx_q,
    output reg          tx_we,
    output reg  [12:0]  tx_wa,
    output reg  [7:0]   tx_wd,
    output reg  [7:0]   f_status,
    output reg  [15:0]  f_len,
    input  wire         trng_valid,
    input  wire [31:0]  trng_data,
    // SHA-512 unit
    output reg          h5_begin,
    output reg          h5_in_valid,
    output reg  [7:0]   h5_in_byte,
    input  wire         h5_in_ready,
    output reg          h5_end,
    input  wire         h5_done,
    output reg  [2:0]   h5_ra,                 // digest word read port of the SHA-2 unit (64-bit words H0..H7)
    input  wire [63:0]  h5_q,
    // shared bignum engine (modular ALU + register file in block RAM)
    output reg          e_start,
    output reg  [3:0]   e_op,
    output reg  [6:0]   e_d, e_a, e_b,
    output reg  [1:0]   e_msel,
    input  wire         e_done,
    input  wire         e_lt,
    output wire [10:0]  x_ra,
    output wire         x_we,
    output wire [10:0]  x_wa,
    output wire [15:0]  x_wd,
    input  wire [15:0]  x_rq
);
// ---------------- memories (block RAM, synchronous read) ----------------
(* ram_style="block" *) reg [31:0] uc [0:1535];
(* ram_style="block" *) reg [15:0] km [0:1023];
initial begin
`include "ecc_ucode.vh"
end
initial begin
`include "ecc_const.vh"
end

reg         rf_we; reg [10:0] rf_wa; reg [15:0] rf_wd;
wire [10:0] rf_ra;
wire [15:0] rf_q = x_rq;                       // register file lives in the shared bignum engine
reg  [15:0] km_q; reg [31:0] uc_q;
assign x_ra = rf_ra; assign x_we = rf_we; assign x_wa = rf_wa; assign x_wd = rf_wd;
reg  [10:0] pc;
reg  [9:0]  km_ra;
always @(posedge clk) begin
    km_q <= km[km_ra];
    uc_q <= uc[pc];
end
assign h_q = rf_q;

// ---------------- modular ALU: shared bignum engine (e_* ports) ----------------
reg  [1:0]  msel;
reg  [3:0]  alu_op;

// ---------------- opcodes ----------------
localparam OP_NOP=0, OP_MUL=1, OP_ADD=2, OP_SUB=3, OP_MOV=4, OP_SEL=5, OP_MSEL=6, OP_LDK=7, OP_BITINIT=8,
           OP_BITNEXT=9, OP_HALT=10, OP_ISZ=11, OP_LT=12, OP_JF=13, OP_JNF=14, OP_JMP=15, OP_SETI=16,
           OP_NOTF=17, OP_SETF=18, OP_XOR=19, OP_AND=20, OP_OR=21, OP_BSWAP=22, OP_RXBE=23, OP_RXLE=24,
           OP_TXBE=25, OP_TXLE=26, OP_RNG=27, OP_H5BEGIN=28, OP_H5FEEDR=29, OP_H5FEEDI=30, OP_H5FILL=31,
           OP_H5FEEDRX=32, OP_H5END=33, OP_FIN=34, OP_CHKLEN=35, OP_CHKLT=36, OP_CALL=37, OP_RET=38,
           OP_LDUID=39, OP_SHR128=40;
localparam Q_IDLE=0, Q_F1=1, Q_F2=2, Q_X=3, Q_LDA=4, Q_LDB=5, Q_RUN=6, Q_ST=7, Q_MOV=8, Q_LDK=9,
           Q_SETI=10, Q_BIT1=11, Q_BIT2=12, Q_ISZ=13, Q_NXT=14,
           Q_BRA=15, Q_BRB=16, Q_BRC=17, Q_BTA=18, Q_BTB=19, Q_BTC=20, Q_RNG=21, Q_UID=22, Q_SHR=23,
           Q_FA=24, Q_FB=25, Q_FC=26, Q_FD=27, Q_HEA=28, Q_HEB=29, Q_HEC=30, Q_FIL=31, Q_FRX=32, Q_FRY=33, Q_FRZ=34, Q_ENG=35, Q_EMS=36,
           Q_HED=37, Q_HEE=38;
reg [5:0]   st;
reg [4:0]   w;
reg [31:0]  ins;
reg [7:0]   op, d, a, b;
reg [7:0]   bitctr; reg [6:0] bsrc; reg [10:0] loop_pc;
reg         flag, orr;
reg [6:0]   rd_reg;
reg [10:0]  stk [0:3]; reg [2:0] sp;

wire [7:0]  i_op  = ins[31:24];
wire [6:0]  i_a   = ins[14:8];
wire [10:0] i_tgt = ins[10:0];
wire [15:0] i_imm = ins[15:0];

// register-file read address: sequencer-driven (ov) or linear {rd_reg, w}
reg         ov_en; reg [10:0] ov_addr;
assign rf_ra = h_busy ? (ov_en ? ov_addr : ((st == Q_BIT1) ? {bsrc, bitctr[7:4]} :
                                                   (st == Q_SHR)  ? {rd_reg, w[3:0] + 4'd8} : {rd_reg, w[3:0]}))
                      : {h_rreg, h_rword};

// ---------------- byte <-> register helpers ----------------
reg [5:0]   p;                        // byte position counter
reg [7:0]   hb;                       // half-word byte buffer
reg [7:0]   n8, off8;
reg         le_f, vld;
reg [31:0]  rbuf;
wire [7:0]  cbw = vld ? rx_q : 8'd0;          // byte just read from the payload (0 outside the field)
reg [15:0]  rxi;                      // rx index (H5FEEDRX)
wire [5:0]  n6 = n8[5:0];
wire [5:0]  skip = 6'd32 - n6;        // BE: leading zero bytes
wire [5:0]  tpos = le_f ? p : (skip + p);   // integer byte position of output byte p (BE: from MSB, LE: from LSB)
wire [3:0]  t_word = le_f ? tpos[4:1] : (4'd15 - tpos[4:1]);
wire        t_hi   = le_f ? tpos[0] : ~tpos[0];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st <= Q_IDLE; h_busy <= 1'b0; h_done <= 1'b0; h_flag <= 1'b0; rf_we <= 1'b0; e_start <= 1'b0;
        msel <= 2'd0; flag <= 1'b0; pc <= 11'd0; w <= 5'd0; ov_en <= 1'b0; sp <= 3'd0; tx_we <= 1'b0;
        h5_begin <= 1'b0; h5_in_valid <= 1'b0; h5_end <= 1'b0; f_status <= 8'd0; f_len <= 16'd0;
        rx_a <= 13'd0;
    end else begin
        h_done <= 1'b0; e_start <= 1'b0; rf_we <= 1'b0; tx_we <= 1'b0;
        h5_begin <= 1'b0; h5_in_valid <= 1'b0; h5_end <= 1'b0;
        if (!h_busy) begin
            if (h_we) begin rf_we <= 1'b1; rf_wa <= {h_wreg, h_wword}; rf_wd <= h_wdata; end
            if (h_go) begin pc <= h_pc; h_busy <= 1'b1; st <= Q_EMS; flag <= 1'b0; msel <= 2'd0; sp <= 3'd0; ov_en <= 1'b0;
                            e_start <= 1'b1; e_op <= 4'd8; e_msel <= 2'd0; end
        end else case (st)
        Q_F1: st <= Q_F2;                                   // microcode ROM read latency
        Q_F2: begin ins <= uc_q; st <= Q_X; end
        Q_X: begin
            op <= i_op; d <= ins[23:16]; a <= ins[15:8]; b <= ins[7:0];
            pc <= pc + 11'd1; w <= 5'd0; st <= Q_F1; ov_en <= 1'b0;   // default: fetch next
            case (i_op)
            OP_MUL, OP_ADD, OP_SUB, OP_LT, OP_XOR, OP_AND, OP_OR, OP_BSWAP: begin
                e_start <= 1'b1; e_d <= ins[22:16]; e_a <= ins[14:8]; e_b <= ins[6:0]; e_msel <= msel; st <= Q_ENG;
                case (i_op)
                  OP_MUL: e_op <= 4'd0; OP_ADD: e_op <= 4'd1; OP_SUB: e_op <= 4'd2; OP_XOR: e_op <= 4'd3;
                  OP_AND: e_op <= 4'd4; OP_OR: e_op <= 4'd5; OP_BSWAP: e_op <= 4'd6; default: e_op <= 4'd7;
                endcase
            end
            OP_MOV:   begin rd_reg <= i_a; st <= Q_MOV; end
            OP_SEL:   begin st <= Q_BIT1; end
            OP_MSEL:  begin msel <= ins[1:0]; e_start <= 1'b1; e_op <= 4'd8; e_msel <= ins[1:0]; st <= Q_EMS; end
            OP_LDK:   begin km_ra <= {ins[5:0], 4'd0}; st <= Q_LDK; end
            OP_BITINIT: begin bsrc <= i_a; bitctr <= (ins[7:0] == 8'd0) ? 8'd255 : (ins[7:0] - 8'd1); loop_pc <= pc + 11'd1; end
            OP_BITNEXT: begin if (bitctr != 8'd0) begin bitctr <= bitctr - 8'd1; pc <= loop_pc; end end
            OP_HALT:  begin h_busy <= 1'b0; h_done <= 1'b1; h_flag <= flag; st <= Q_IDLE; end
            OP_ISZ:   begin rd_reg <= i_a; orr <= 1'b0; st <= Q_ISZ; end
            OP_JF:    begin if (flag)  pc <= i_tgt; end
            OP_JNF:   begin if (!flag) pc <= i_tgt; end
            OP_JMP:   begin pc <= i_tgt; end
            OP_SETI:  begin st <= Q_SETI; end
            OP_NOTF:  begin flag <= ~flag; end
            OP_SETF:  begin flag <= ins[0]; end
            OP_CALL:  begin stk[sp[1:0]] <= pc + 11'd1; sp <= sp + 3'd1; pc <= i_tgt; end
            OP_RET:   begin
                if (sp == 3'd0) begin h_busy <= 1'b0; h_done <= 1'b1; h_flag <= flag; st <= Q_IDLE; end
                else begin sp <= sp - 3'd1; pc <= stk[sp[1:0] - 2'd1]; end
            end
            OP_CHKLEN: begin flag <= (plen != i_imm); end
            OP_CHKLT:  begin flag <= (plen < i_imm); end
            OP_FIN:   begin f_status <= ins[23:16]; f_len <= i_imm; h_busy <= 1'b0; h_done <= 1'b1; h_flag <= flag; st <= Q_IDLE; end
            OP_LDUID: begin st <= Q_UID; end
            OP_SHR128: begin rd_reg <= i_a; st <= Q_SHR; end
            OP_RXBE, OP_RXLE: begin le_f <= (i_op == OP_RXLE); n8 <= ins[7:0]; off8 <= ins[15:8]; p <= 6'd0; st <= Q_BRA; end
            OP_TXBE, OP_TXLE: begin le_f <= (i_op == OP_TXLE); n8 <= ins[7:0]; off8 <= ins[15:8]; p <= 6'd0; st <= Q_BTA; end
            OP_RNG:   begin n8 <= ins[7:0]; st <= Q_RNG; end
            OP_H5BEGIN: begin h5_begin <= 1'b1; end
            OP_H5FEEDI: begin st <= Q_FA; end
            OP_H5FILL:  begin n8 <= ins[7:0]; st <= Q_FIL; end
            OP_H5FEEDR: begin n8 <= ins[7:0]; le_f <= 1'b0; p <= 6'd0; st <= Q_FB; end
            OP_H5FEEDRX: begin rxi <= {8'd0, ins[15:8]}; st <= Q_FRX; end
            OP_H5END:   begin st <= Q_HEA; end
            default: ;
            endcase
        end
        // ---- modular ALU operation (engine) ----
        Q_ENG: if (e_done) begin
            if (op == OP_LT) flag <= e_lt;
            st <= Q_F1;
        end
        Q_EMS: if (e_done) st <= Q_F1;            // modulus (re)loaded
        // ---- MOV / LDK: read word w in cycle w, write word w-1 in cycle w+1 ----
        Q_MOV: begin
            if (w >= 5'd1) begin rf_we <= 1'b1; rf_wa <= {d[6:0], w[3:0] - 4'd1}; rf_wd <= rf_q; end
            if (w == 5'd16) st <= Q_F1; else w <= w + 5'd1;
        end
        Q_LDK: begin
            if (w >= 5'd1) begin rf_we <= 1'b1; rf_wa <= {d[6:0], w[3:0] - 4'd1}; rf_wd <= km_q; end
            if (w != 5'd16) km_ra <= {b[5:0], w[3:0] + 4'd1};
            if (w == 5'd16) st <= Q_F1; else w <= w + 5'd1;
        end
        Q_SETI: begin
            rf_we <= 1'b1; rf_wa <= {d[6:0], w[3:0]}; rf_wd <= (w == 5'd0) ? {a, b} : 16'd0;
            if (w == 5'd15) st <= Q_F1; else w <= w + 5'd1;
        end
        Q_UID: begin                                         // d = 128-bit device UID (right-aligned)
            rf_we <= 1'b1; rf_wa <= {d[6:0], w[3:0]}; rf_wd <= (w < 5'd8) ? UID[16*w[2:0] +: 16] : 16'd0;
            if (w == 5'd15) st <= Q_F1; else w <= w + 5'd1;
        end
        // ---- SHR128: d = a >> 128 ----
        Q_SHR: begin
            // address word w+8 in cycle w (see rf_ra); data arrives in cycle w+1 -> destination word w
            if (w >= 5'd1 && w <= 5'd8) begin rf_we <= 1'b1; rf_wa <= {d[6:0], w[3:0] - 4'd1}; rf_wd <= rf_q; end
            if (w >= 5'd9)               begin rf_we <= 1'b1; rf_wa <= {d[6:0], w[3:0] - 4'd1}; rf_wd <= 16'd0; end
            if (w == 5'd16) st <= Q_F1; else w <= w + 5'd1;
        end
        // ---- SEL: d = bit(bsrc, bitctr) ? a : b ----
        Q_BIT1: st <= Q_BIT2;
        Q_BIT2: begin rd_reg <= rf_q[bitctr[3:0]] ? a[6:0] : b[6:0]; w <= 5'd0; st <= Q_MOV; end
        // ---- ISZ ----
        Q_ISZ: begin
            if (w >= 5'd1) orr <= orr | (rf_q != 16'd0);
            if (w == 5'd16) st <= Q_NXT; else w <= w + 5'd1;
        end
        Q_NXT: begin flag <= ~orr; st <= Q_F1; end

        // ---- RXBE / RXLE: payload bytes -> register d ----
        Q_BRA: begin
            if (le_f) begin vld <= (p < n6); rx_a <= {5'd0, off8} + {7'd0, p}; end
            else      begin vld <= (p >= skip); rx_a <= {5'd0, off8} + {7'd0, p - skip}; end
            st <= Q_BRB;
        end
        Q_BRB: st <= Q_BRC;
        Q_BRC: begin
            if (p[0] == 1'b0) hb <= cbw;
            else begin
                rf_we <= 1'b1;
                if (le_f) begin rf_wa <= {d[6:0], p[4:1]};          rf_wd <= {cbw, hb}; end
                else      begin rf_wa <= {d[6:0], 4'd15 - p[4:1]};  rf_wd <= {hb, cbw}; end
            end
            p <= p + 6'd1;
            if (p == 6'd31) st <= Q_F1; else st <= Q_BRA;
        end
        // ---- TXBE / TXLE: register a -> response bytes ----
        Q_BTA: begin ov_en <= 1'b1; ov_addr <= {d[6:0], t_word}; st <= Q_BTB; end   // TXBE: d = source reg
        Q_BTB: st <= Q_BTC;
        Q_BTC: begin
            tx_we <= 1'b1; tx_wa <= {5'd0, off8} + {7'd0, p}; tx_wd <= t_hi ? rf_q[15:8] : rf_q[7:0];
            p <= p + 6'd1; ov_en <= 1'b0;
            if (p == n6 - 6'd1) st <= Q_F1; else st <= Q_BTA;
        end
        // ---- RNG: d <= n8 TRNG words (right-aligned), upper words zero ----
        Q_RNG: begin
            if (w == 5'd16) st <= Q_F1;
            else if (w < {n8[3:0], 1'b0}) begin
                if (!w[0]) begin
                    if (trng_valid) begin
                        rbuf <= trng_data; rf_we <= 1'b1; rf_wa <= {d[6:0], w[3:0]}; rf_wd <= trng_data[15:0]; w <= w + 5'd1;
                    end
                end else begin
                    rf_we <= 1'b1; rf_wa <= {d[6:0], w[3:0]}; rf_wd <= rbuf[31:16]; w <= w + 5'd1;
                end
            end else begin
                rf_we <= 1'b1; rf_wa <= {d[6:0], w[3:0]}; rf_wd <= 16'd0; w <= w + 5'd1;
            end
        end
        // ---- SHA-512 feeding ----
        Q_FA: if (h5_in_ready) begin h5_in_valid <= 1'b1; h5_in_byte <= b; st <= Q_F1; end    // H5FEEDI imm (b)
        Q_FIL: begin                                                                          // H5FILL byte=a, count=b
            if (n8 == 8'd0) st <= Q_F1;
            else if (h5_in_ready) begin h5_in_valid <= 1'b1; h5_in_byte <= a; n8 <= n8 - 8'd1; end
        end
        Q_FB: begin ov_en <= 1'b1; ov_addr <= {a[6:0], t_word}; st <= Q_FC; end              // H5FEEDR a, n
        Q_FC: st <= Q_FD;
        Q_FD: if (h5_in_ready) begin
            h5_in_valid <= 1'b1; h5_in_byte <= t_hi ? rf_q[15:8] : rf_q[7:0]; p <= p + 6'd1; ov_en <= 1'b0;
            if (p == n6 - 6'd1) st <= Q_F1; else st <= Q_FB;
        end
        Q_FRX: begin                                                                          // H5FEEDRX off: payload[off..plen)
            if (rxi >= plen) st <= Q_F1; else begin rx_a <= rxi[12:0]; st <= Q_FRY; end
        end
        Q_FRY: st <= Q_FRZ;
        Q_FRZ: if (h5_in_ready) begin h5_in_valid <= 1'b1; h5_in_byte <= rx_q; rxi <= rxi + 16'd1; st <= Q_FRX; end
        Q_HEA: if (h5_in_ready) begin h5_end <= 1'b1; st <= Q_HEB; end                        // H5END d1(d), d2(a)
        Q_HEB: if (h5_done) begin w <= 5'd0; st <= Q_HEC; end
        // digest -> d (H0..H3) and a (H4..H7) as little-endian 16-bit limbs: limb w comes from word {w[4], ~w[3:2]}, slice w[1:0]
        Q_HEC: begin h5_ra <= {w[4], ~w[3], ~w[2]}; st <= Q_HED; end
        Q_HED: st <= Q_HEE;
        Q_HEE: begin
            rf_we <= 1'b1; rf_wa <= {w[4] ? a[6:0] : d[6:0], w[3:0]};
            case (w[1:0]) 2'd0: rf_wd <= h5_q[15:0]; 2'd1: rf_wd <= h5_q[31:16]; 2'd2: rf_wd <= h5_q[47:32]; default: rf_wd <= h5_q[63:48]; endcase
            if (w == 5'd31) st <= Q_F1; else begin w <= w + 5'd1; st <= Q_HEC; end
        end
        default: st <= Q_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
