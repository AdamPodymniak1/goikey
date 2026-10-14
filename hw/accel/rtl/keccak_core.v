`default_nettype none
// Keccak-f[1600], lane-serial with 5-lane shift rings (64-bit datapath, state in a small RAM) - about 120 clocks per round.
//   clear                   : zero the state (25 clocks)
//   xor_en/xor_lane/xor_val : state[lane] ^= val               (read-modify-write, `busy` for 2 clocks)
//   perm                    : 24 rounds; `busy` meanwhile, `done` pulses at the end
//   rd_lane -> rd_val       : lane read, valid 2 clocks after rd_lane is stable (only when !busy)
// RAM timing: ra presented in cycle t -> rq valid in cycle t+2.
// Per round: pass A (column parities, ring `cr`), pass B (theta: lane ^= D[x], in place), pass C (rho/pi gathered one output
// row at a time into ring `rr`, chi + iota written to the other bank).  No wide multiplexers: both rings only shift.
module keccak_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         clear,
    input  wire         xor_en,
    input  wire [4:0]   xor_lane,
    input  wire [63:0]  xor_val,
    input  wire         perm,
    output wire         busy,
    output reg          done,
    input  wire [4:0]   rd_lane,
    output wire [63:0]  rd_val
);
`include "keccak_tab.vh"
(* ram_style="block" *) reg [63:0] km [0:63];            // {bank, lane}
reg  [5:0]  ra;  reg [63:0] rq;
reg         we;  reg [5:0] wa; reg [63:0] wd;
always @(posedge clk) begin
    if (we) km[wa] <= wd;
    rq <= km[ra];
end
assign rd_val = rq;

localparam K_IDLE=0, K_CLR=1, K_X1=2, K_X2=3, K_A=4, K_B=5, K_GAP=6, K_CG=7, K_CW=8;
reg [3:0]  st;
assign busy = (st != K_IDLE);
reg        cur;                                           // active bank
reg [4:0]  c;                                             // generic counter (clear / pass counter)
reg [4:0]  rnd;
reg [2:0]  ix, iy, cx, cy;                                // issue / consume coordinates
reg [2:0]  row;                                           // output row (pass C)
reg [4:0]  xl; reg [63:0] xv;
reg [63:0] cacc;
reg [319:0] cr, rr;

function [4:0] lane5(input [2:0] x, input [2:0] y); lane5 = {2'b00, x} + {y, 2'b00} + {2'b00, y}; endfunction
function [2:0] mod5(input [4:0] v); begin
    if (v >= 5'd15) mod5 = v - 5'd15; else if (v >= 5'd10) mod5 = v - 5'd10; else if (v >= 5'd5) mod5 = v - 5'd5; else mod5 = v[2:0];
end endfunction
function [4:0] srcl(input [2:0] r, input [2:0] x);          // source lane of element x of output row r (pi)
    reg [2:0] xs; begin xs = mod5({2'b00, r} + {2'b00, r} + {2'b00, r} + {2'b00, x}); srcl = lane5(xs, x); end
endfunction
function [63:0] rotl64(input [63:0] x, input [5:0] n);          // 6-stage barrel rotator
    reg [63:0] v;
    begin
        v = x;
        if (n[0]) v = {v[62:0],  v[63]};
        if (n[1]) v = {v[61:0],  v[63:62]};
        if (n[2]) v = {v[59:0],  v[63:60]};
        if (n[3]) v = {v[55:0],  v[63:56]};
        if (n[4]) v = {v[47:0],  v[63:48]};
        if (n[5]) v = {v[31:0],  v[63:32]};
        rotl64 = v;
    end
endfunction
wire [63:0] c1_ = cr[255:192];
wire [63:0] dtap = cr[63:0] ^ {c1_[62:0], c1_[63]};                  // D[x] = C[x-1] ^ rotl1(C[x+1])
wire [4:0]  g_lane = srcl(row, ix);                                  // gather: issued lane
wire [4:0]  c_lane = srcl(row, cx);                                  // gather: lane arriving on rq
wire [63:0] rotv   = rotl64(rq, keccak_rot(c_lane));
wire [63:0] r0 = rr[319:256], r1 = rr[255:192], r2 = rr[191:128];
wire [63:0] chi_o  = r0 ^ (~r1 & r2);
wire [63:0] wval   = (row == 3'd0 && cx == 3'd0) ? (chi_o ^ keccak_rc(rnd)) : chi_o;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= K_IDLE; done <= 1'b0; cur <= 1'b0; we <= 1'b0; ra <= 6'd0; rnd <= 5'd0; c <= 5'd0; end
    else begin
        done <= 1'b0; we <= 1'b0;
        case (st)
        K_IDLE: begin
            ra <= {cur, rd_lane};
            if (clear) begin c <= 5'd0; st <= K_CLR; end
            else if (perm) begin c <= 5'd0; rnd <= 5'd0; ix <= 3'd0; iy <= 3'd0; cx <= 3'd0; cy <= 3'd0; st <= K_A; end
            else if (xor_en) begin xl <= xor_lane; xv <= xor_val; ra <= {cur, xor_lane}; st <= K_X1; end
        end
        K_CLR: begin
            we <= 1'b1; wa <= {cur, c}; wd <= 64'd0;
            if (c == 5'd24) st <= K_IDLE; else c <= c + 5'd1;
        end
        K_X1: st <= K_X2;
        K_X2: begin we <= 1'b1; wa <= {cur, xl}; wd <= rq ^ xv; st <= K_IDLE; end
        // ---- pass A: column parities C[x] (lanes read in column order) ----
        K_A: begin
            if (c <= 5'd24) begin
                ra <= {cur, lane5(ix, iy)};
                if (iy == 3'd4) begin iy <= 3'd0; ix <= ix + 3'd1; end else iy <= iy + 3'd1;
            end
            if (c >= 5'd2) begin
                if (cy == 3'd4) begin cr <= {cr[255:0], cacc ^ rq}; cy <= 3'd0; cx <= cx + 3'd1; end
                else begin cacc <= (cy == 3'd0) ? rq : (cacc ^ rq); cy <= cy + 3'd1; end
            end
            if (c == 5'd26) begin c <= 5'd0; ix <= 3'd0; iy <= 3'd0; cx <= 3'd0; cy <= 3'd0; st <= K_B; end
            else c <= c + 5'd1;
        end
        // ---- pass B: theta, lane ^= D[x] in place ----
        K_B: begin
            if (c <= 5'd24) begin
                ra <= {cur, lane5(ix, iy)};
                if (iy == 3'd4) begin iy <= 3'd0; ix <= ix + 3'd1; end else iy <= iy + 3'd1;
            end
            if (c >= 5'd2) begin
                we <= 1'b1; wa <= {cur, lane5(cx, cy)}; wd <= rq ^ dtap;
                if (cy == 3'd4) begin cy <= 3'd0; cx <= cx + 3'd1; cr <= {cr[255:0], cr[319:256]}; end
                else cy <= cy + 3'd1;
            end
            if (c == 5'd26) begin c <= 5'd0; row <= 3'd0; st <= K_GAP; end
            else c <= c + 5'd1;
        end
        K_GAP: begin c <= 5'd0; ix <= 3'd0; cx <= 3'd0; st <= K_CG; end                 // last theta write lands
        // ---- pass C1: gather one output row (rho + pi) ----
        K_CG: begin
            if (c <= 5'd4) begin ra <= {cur, g_lane}; ix <= ix + 3'd1; end
            if (c >= 5'd2) begin rr <= {rr[255:0], rotv}; cx <= cx + 3'd1; end
            if (c == 5'd6) begin c <= 5'd0; cx <= 3'd0; st <= K_CW; end else c <= c + 5'd1;
        end
        // ---- pass C2: chi (+ iota) of that row into the other bank ----
        K_CW: begin
            we <= 1'b1; wa <= {~cur, lane5(cx, row)}; wd <= wval;
            rr <= {rr[255:0], rr[319:256]};
            if (cx == 3'd4) begin
                if (row == 3'd4) begin
                    cur <= ~cur;
                    if (rnd == 5'd23) begin st <= K_IDLE; done <= 1'b1; end
                    else begin rnd <= rnd + 5'd1; c <= 5'd0; ix <= 3'd0; iy <= 3'd0; cx <= 3'd0; cy <= 3'd0; st <= K_A; end
                end else begin row <= row + 3'd1; c <= 5'd0; ix <= 3'd0; cx <= 3'd0; st <= K_CG; end
            end else cx <= cx + 3'd1;
        end
        default: st <= K_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
