`default_nettype none
// AES-256 block cipher (encrypt + decrypt), byte-serial and area-optimised.
//   key_we/key_wi/key_wd : write the 8 key words (big endian, word 0 first) straight into the round-key RAM,
//                          then key_go -> expansion (~300 clk), key_ready
//   sh_en/sh_in/sh_out   : the state is a 16-byte shift register while idle: sh_out = state byte 0, and each sh_en
//                          shifts in sh_in at byte 15 (16 shifts load a block and unload the previous result)
//   blk_start (+dec)     : process the state in place (~300 clk encrypt, ~400 clk decrypt); blk_done pulses
// ONE S-box (shared forward/inverse, tower field: aes_sbox_tower.vh) serves SubBytes, InvSubBytes and the key schedule:
// four bytes per column are pushed through it one per clock. InvMixColumns = MixColumns applied three times.
// Round keys live in a 60x32 block RAM.
module aes_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         key_we,
    input  wire [2:0]   key_wi,
    input  wire [31:0]  key_wd,
    input  wire         key_go,
    output reg          key_ready,
    input  wire         blk_start,
    input  wire         dec,
    output reg          blk_done,
    input  wire         sh_en,
    input  wire [7:0]   sh_in,
    output wire [7:0]   sh_out,
    output wire [127:0] state,
    output wire         busy
);
`include "aes_sbox_tower.vh"
function [7:0] xt(input [7:0] a); xt = {a[6:0],1'b0} ^ (a[7] ? 8'h1b : 8'h00); endfunction
function [31:0] mixcol(input [31:0] c);
    reg [7:0] a0, a1, a2, a3;
    begin
        a0 = c[31:24]; a1 = c[23:16]; a2 = c[15:8]; a3 = c[7:0];
        mixcol = { xt(a0) ^ (xt(a1) ^ a1) ^ a2 ^ a3,
                   a0 ^ xt(a1) ^ (xt(a2) ^ a2) ^ a3,
                   a0 ^ a1 ^ xt(a2) ^ (xt(a3) ^ a3),
                   (xt(a0) ^ a0) ^ a1 ^ a2 ^ xt(a3) };
    end
endfunction

// ---- round-key RAM (60 words), 1 write port, 1 read port (1-clk latency) ----
(* ram_style="block" *) reg [31:0] kmem [0:63];
reg         k_we; reg [5:0] k_wa; reg [31:0] k_wd;
reg  [5:0]  k_ra;
reg  [31:0] rd_q;
always @(posedge clk) begin
    if (k_we) kmem[k_wa] <= k_wd;
    rd_q <= kmem[k_ra];
end

reg [127:0] st;
reg [95:0]  ns;
reg [31:0]  colq, wprev;
reg [3:0]   rnd;                  // round 1..14
reg [1:0]   col;
reg [1:0]   bi;                   // byte within column
reg [3:0]   sidx;                 // state byte index feeding the S-box
reg [2:0]   ph;
reg [5:0]   kw;                   // key schedule word index / ARK word counter
reg         run, d_r, ks_run;
reg [3:0]   bs;                   // block FSM
reg [3:0]   ksst;                 // key schedule FSM
assign sh_out = st[127:120];
assign state  = st;

localparam B_IDLE=0, B_ARK=1, B_RD=3, B_SB=4, B_MIX=5, B_IMX=6, B_WR=7;
localparam K_IDLE=0, K_L7=1, K_NEXT=2, K_RD=3, K_SBX=4, K_FIN=5, K_FIN2=6, K_L7W=7, K_L7R=8;
assign busy = run | ks_run;

reg  [7:0] wprev_b;
// ---- shared S-box input / output ----
reg [7:0] st_byte;
always @(*) case (sidx)
    4'd0: st_byte = st[127:120];  4'd1: st_byte = st[119:112];  4'd2: st_byte = st[111:104];  4'd3: st_byte = st[103:96];
    4'd4: st_byte = st[95:88];    4'd5: st_byte = st[87:80];    4'd6: st_byte = st[79:72];    4'd7: st_byte = st[71:64];
    4'd8: st_byte = st[63:56];    4'd9: st_byte = st[55:48];    4'd10: st_byte = st[47:40];   4'd11: st_byte = st[39:32];
    4'd12: st_byte = st[31:24];   4'd13: st_byte = st[23:16];   4'd14: st_byte = st[15:8];    default: st_byte = st[7:0];
endcase
wire       ks_sb  = (ksst == K_SBX);
wire [7:0] sb_out = aes_sbox_fi(ks_sb ? wprev_b : st_byte, !ks_sb && d_r);

// ---- round key word to read for the current column ----
wire [3:0] rk_round = d_r ? (4'd14 - rnd) : rnd;
reg [7:0] rcon;
always @(*) case (kw[5:3])
    3'd1: rcon = 8'h01; 3'd2: rcon = 8'h02; 3'd3: rcon = 8'h04; 3'd4: rcon = 8'h08;
    3'd5: rcon = 8'h10; 3'd6: rcon = 8'h20; default: rcon = 8'h40;
endcase
wire        kmod0 = (kw[2:0] == 3'd0);
wire        kmod4 = (kw[2:0] == 3'd4);
reg  [31:0] sw;                    // SubWord result being assembled (key schedule)
reg  [1:0]  kb;                    // byte counter inside SubWord
wire [31:0] wsrc  = kmod0 ? {wprev[23:0], wprev[31:24]} : wprev;     // RotWord for i%8==0
wire [31:0] wnew  = rd_q ^ (kmod0 ? (sw ^ {rcon, 24'd0}) : kmod4 ? sw : wprev);

always @(*) wprev_b = wsrc[31 - 8*kb -: 8];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_ready <= 1'b0; blk_done <= 1'b0; run <= 1'b0; ks_run <= 1'b0; k_we <= 1'b0; bs <= B_IDLE; ksst <= K_IDLE;
        rnd <= 4'd0; col <= 2'd0; kw <= 6'd0; bi <= 2'd0; k_ra <= 6'd0;
    end else begin
        blk_done <= 1'b0; k_we <= 1'b0;
        if (key_we) begin k_we <= 1'b1; k_wa <= {3'd0, key_wi}; k_wd <= key_wd; key_ready <= 1'b0; end
        if (sh_en && !run) st <= {st[119:0], sh_in};

        // ================= key schedule (words 0..7 are already in kmem) =================
        if (key_go) begin key_ready <= 1'b0; ks_run <= 1'b1; ksst <= K_L7; end
        else case (ksst)
        K_L7:  begin k_ra <= 6'd7; ksst <= K_L7W; end
        K_L7W: ksst <= K_L7R;
        K_L7R: begin wprev <= rd_q; kw <= 6'd8; ksst <= K_NEXT; end
        K_NEXT: begin                                     // word kw: read w[kw-8]
            k_ra <= kw - 6'd8; sw <= 32'd0; kb <= 2'd0;
            ksst <= (kmod0 || kmod4) ? K_SBX : K_RD;
        end
        K_RD: ksst <= K_FIN;                              // BRAM read latency
        K_SBX: begin                                      // push the four bytes of (Rot)Word(w[i-1]) through the S-box
            sw <= {sw[23:0], sb_out};
            if (kb == 2'd3) ksst <= K_FIN; else kb <= kb + 2'd1;
        end
        K_FIN: ksst <= K_FIN2;
        K_FIN2: begin
            k_we <= 1'b1; k_wa <= kw; k_wd <= wnew; wprev <= wnew;
            if (kw == 6'd59) begin ksst <= K_IDLE; ks_run <= 1'b0; key_ready <= 1'b1; end
            else begin kw <= kw + 6'd1; ksst <= K_NEXT; end
        end
        default: ;
        endcase

        // ================= block cipher =================
        case (bs)
        B_IDLE: if (blk_start && !run && key_ready) begin
            d_r <= dec; run <= 1'b1; kw <= 6'd0; bs <= B_ARK;
            k_ra <= dec ? 6'd56 : 6'd0;
        end
        B_ARK: begin                                      // initial AddRoundKey: word kw-1 arrives now; the state rotates by one word per clock
            if (kw != 6'd0) st <= {st[95:0], st[127:96] ^ rd_q};
            if (kw == 6'd4) begin rnd <= 4'd1; col <= 2'd0; bi <= 2'd0; sidx <= 4'd0; bs <= B_RD; end
            else begin kw <= kw + 6'd1; k_ra <= (d_r ? 6'd56 : 6'd0) + {4'd0, kw[1:0]} + 6'd1; end
        end
        B_RD: begin                                       // start of a column: issue the round-key read
            k_ra <= {rk_round, 2'b00} + {4'd0, col}; bi <= 2'd0; bs <= B_SB;
        end
        B_SB: begin                                       // one state byte per clock through the S-box
            colq <= {colq[23:0], sb_out};
            sidx <= sidx + (d_r ? 4'd13 : 4'd5);
            if (bi == 2'd3) bs <= B_MIX; else bi <= bi + 2'd1;
        end
        B_MIX: begin
            if (d_r) begin
                colq <= colq ^ rd_q;                      // AddRoundKey, then InvMixColumns (= MixColumns^3) unless last round
                ph <= 3'd0; bs <= (rnd == 4'd14) ? B_WR : B_IMX;
            end else begin
                colq <= ((rnd == 4'd14) ? colq : mixcol(colq)) ^ rd_q; bs <= B_WR;
            end
        end
        B_IMX: begin
            colq <= mixcol(colq);
            if (ph == 3'd2) bs <= B_WR; else ph <= ph + 3'd1;
        end
        B_WR: begin
            if (col == 2'd3) begin
                st <= {ns, colq}; col <= 2'd0; sidx <= 4'd0;
                if (rnd == 4'd14) begin blk_done <= 1'b1; run <= 1'b0; bs <= B_IDLE; end
                else begin rnd <= rnd + 4'd1; bs <= B_RD; end
            end else begin
                ns <= {ns[63:0], colq}; col <= col + 2'd1; bs <= B_RD;
            end
        end
        default: bs <= B_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
