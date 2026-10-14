`default_nettype none
// ML-DSA samplers, consuming the squeeze stream of shake_unit and writing a polynomial:
//   mode 0 uniform mod q (rej_uniform, 3 bytes / candidate)        mode 1 eta=2 (rej_eta)      mode 2 eta=4
//   mode 3 gamma1 = 2^17 (18-bit fields)   mode 4 gamma1 = 2^19 (20-bit fields)
//   mode 5 SampleInBall (tau +-1 coefficients; the destination slot must be zero beforehand)
// The output is identical to the sequential-stream semantics of PQClean (block boundaries do not matter).
module pq_smp (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [2:0]  mode,
    input  wire [5:0]  dst,
    input  wire [7:0]  tau,
    output reg         busy,
    output reg         done,
    // SHAKE squeeze stream
    input  wire        out_ready,
    input  wire [7:0]  out_byte,
    output reg         out_take,
    // polynomial memory (read latency: ra in cycle t -> rq in cycle t+2)
    output reg  [13:0] ra,
    output reg         we,
    output reg  [13:0] wa,
    output reg  [31:0] wd,
    input  wire [31:0] rq
);
localparam S_IDLE=0, S_FETCH=1, S_TAKEN=2, S_GOT=3, S_N1=4, S_WAITW=5, S_GRD=6,
           S_B1=7, S_B2=8, S_B3=9, S_B4=10, S_B5=11, S_BEND=12;
reg [3:0]  st, ret_st;
reg [2:0]  m;
reg [5:0]  d_r;
reg [8:0]  ctr;                          // coefficients written
reg [7:0]  cur, u0, u1, jb;              // last fetched byte, uniform bytes, SampleInBall index byte
reg [1:0]  bi;
reg [31:0] acc; reg [5:0] accb;          // gamma1 bit accumulator
reg [63:0] signs; reg [3:0] sc;
reg [8:0]  bi_i;
reg        phase_hi;

wire [4:0]  nb  = (m == 3'd3) ? 5'd18 : 5'd20;
wire [31:0] g1c = (m == 3'd3) ? 32'd131072 : 32'd524288;
wire [3:0]  nib = phase_hi ? cur[7:4] : cur[3:0];
// nib mod 5 for nib < 15: a plain table (a multiplier-based form was mapped to a DSP block and misbehaved on the FPGA)
reg [3:0] nq5;
always @(*) case (nib)
    4'd0, 4'd5, 4'd10: nq5 = 4'd0;
    4'd1, 4'd6, 4'd11: nq5 = 4'd1;
    4'd2, 4'd7, 4'd12: nq5 = 4'd2;
    4'd3, 4'd8, 4'd13: nq5 = 4'd3;
    default:           nq5 = 4'd4;
endcase
wire        eta_ok = (m == 3'd1) ? (nib < 4'd15) : (nib < 4'd9);
wire [31:0] eta_val = (m == 3'd1) ? (32'd2 - {28'd0, nq5}) : (32'd4 - {28'd0, nib});
wire [22:0] ucand = {cur[6:0], u1, u0};                           // first byte = LSB; top bit of the third byte dropped

task fetch(input [3:0] nxt); begin ret_st <= nxt; st <= S_FETCH; end endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= S_IDLE; busy <= 0; done <= 0; we <= 0; out_take <= 0; ra <= 0; wa <= 0; wd <= 0; end
    else begin
        done <= 0; we <= 0; out_take <= 0;
        case (st)
        S_IDLE: if (start) begin
            busy <= 1; m <= mode; d_r <= dst; ctr <= 0; bi <= 0; acc <= 0; accb <= 0; phase_hi <= 0; sc <= 0; signs <= 0;
            bi_i <= 9'd256 - {1'b0, tau};
            if (mode == 3'd5) fetch(S_B1); else fetch(S_GOT);
        end
        // ---- fetch one byte of the SHAKE stream into cur ----
        S_FETCH: if (out_ready) begin cur <= out_byte; out_take <= 1; st <= S_TAKEN; end
        S_TAKEN: st <= ret_st;                                      // the sponge advances on this edge
        S_GOT: begin
            case (m)
            3'd0: begin
                if (bi == 2'd0)      begin u0 <= cur; bi <= 2'd1; fetch(S_GOT); end
                else if (bi == 2'd1) begin u1 <= cur; bi <= 2'd2; fetch(S_GOT); end
                else                 begin bi <= 2'd0; st <= S_N1; end
            end
            3'd1, 3'd2: begin phase_hi <= 0; st <= S_N1; end
            default: begin acc <= acc | ({24'd0, cur} << accb); accb <= accb + 6'd8; st <= S_GRD; end
            endcase
        end
        S_N1: begin
            if (m == 3'd0) begin                                    // uniform candidate
                if (ucand < 23'd8380417) begin
                    we <= 1; wa <= {d_r, ctr[7:0]}; wd <= {9'd0, ucand}; ctr <= ctr + 9'd1; st <= S_WAITW;
                end else fetch(S_GOT);
            end else begin                                          // eta: low nibble first, then high nibble
                if (eta_ok && ctr < 9'd256) begin
                    we <= 1; wa <= {d_r, ctr[7:0]}; wd <= eta_val; ctr <= ctr + 9'd1;
                end
                if (!phase_hi) begin phase_hi <= 1; st <= S_N1; end
                else st <= S_WAITW;
            end
        end
        S_WAITW: begin
            if (ctr >= 9'd256) begin busy <= 0; done <= 1; st <= S_IDLE; end
            else if (m >= 3'd3) st <= S_GRD;
            else fetch(S_GOT);
        end
        S_GRD: begin                                                // gamma1: emit a coefficient when enough bits are buffered
            if (accb >= {1'b0, nb}) begin
                we <= 1; wa <= {d_r, ctr[7:0]}; wd <= g1c - (acc & ((32'd1 << nb) - 32'd1));
                acc <= acc >> nb; accb <= accb - {1'b0, nb}; ctr <= ctr + 9'd1; st <= S_WAITW;
            end else fetch(S_GOT);
        end
        // ---- SampleInBall ----
        S_B1: begin                                                 // 8 sign bytes, first byte = least significant
            signs <= signs | ({56'd0, cur} << {sc[2:0], 3'b000});
            if (sc == 4'd7) st <= S_B2; else begin sc <= sc + 4'd1; fetch(S_B1); end
        end
        S_B2: begin
            if (bi_i >= 9'd256) begin busy <= 0; done <= 1; st <= S_IDLE; end
            else fetch(S_B3);
        end
        S_B3: begin                                                 // candidate j = cur accepted when j <= i
            if ({1'b0, cur} > bi_i) fetch(S_B3);
            else begin ra <= {d_r, cur}; jb <= cur; st <= S_B4; end
        end
        S_B4: st <= S_B5;
        S_B5: begin we <= 1; wa <= {d_r, bi_i[7:0]}; wd <= rq; st <= S_BEND; end        // c[i] = c[j]
        S_BEND: begin
            we <= 1; wa <= {d_r, jb}; wd <= signs[0] ? 32'hFFFFFFFF : 32'd1;             // c[j] = 1 - 2*sign
            signs <= signs >> 1; bi_i <= bi_i + 9'd1; st <= S_B2;
        end
        default: st <= S_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
