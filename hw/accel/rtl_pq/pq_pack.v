`default_nettype none
// ML-DSA bit packing between polynomials and byte spaces.
//   op 0 PKT1 (10 b, v=c)   1 PKT0 (13 b, v=4096-c)   2 PKETA (3/4 b, v=eta-c)   3 PKZ (18/20 b, v=gamma1-c)
//      4 PKW1 (6/4 b, v=c)  5 UPKETA   6 UPKT0   7 PKH (hint positions)   9 UPKW1 (unpack w1, 6/4 b)
// Byte spaces: 0 RX, 1 TX, 2 SC (read/write through the byte bus), 3 = SHAKE absorb (pack only).
// Byte bus timing: br_addr in cycle t -> br_data valid in cycle t+2.
module pq_pack (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [3:0]  op,                // 8 = raw dump (debug)
    input  wire [5:0]  slot,              // polynomial slot (PKH: hint polynomial)
    input  wire [1:0]  space,
    input  wire [12:0] base,
    input  wire        eta4,              // 0: eta=2, 1: eta=4
    input  wire        g1sel,             // 0: gamma1 = 2^17, 1: 2^19
    input  wire        g2sel,             // 0: gamma2=(q-1)/88 (6-bit w1), 1: (q-1)/32 (4-bit w1)
    input  wire [7:0]  omega,
    input  wire [5:0]  hidx,              // PKH: index of the hint polynomial (selects the count byte)
    input  wire        hk_clr,            // reset the hint position counter
    output reg         busy,
    output reg         done,
    output reg         hk_over,           // PKH: more than omega hints so far
    // polynomial memory
    output reg  [13:0] ra,
    output reg         we,
    output reg  [13:0] wa,
    output reg  [31:0] wd,
    input  wire [31:0] rq,
    // byte bus
    output reg         bw_en,
    output reg  [1:0]  bw_space,
    output reg  [12:0] bw_addr,
    output reg  [7:0]  bw_data,
    output reg  [1:0]  br_space,
    output reg  [12:0] br_addr,
    input  wire [7:0]  br_data,
    // SHAKE absorb sink
    output reg         sh_in_valid,
    output reg  [7:0]  sh_in_byte,
    input  wire        sh_in_ready
);
localparam S_IDLE=0, S_R=1, S_RW=2, S_RC=3, S_EM=4, S_EMW=5, S_NEXT=6,
           S_UB=7, S_UBW=8, S_UBC=9, S_UW=10, S_UWW=11,
           S_H=12, S_HW=13, S_HC=14, S_HWR=15, S_HEND=16, S_HEND2=17, S_EMG=18;
reg [4:0]  st;
reg [3:0]  op_r; reg [5:0] sl; reg [1:0] sp; reg [12:0] bs;
reg [8:0]  i;                                  // coefficient index
reg [39:0] acc; reg [5:0] accb;
reg [12:0] bcnt;                               // bytes processed
reg [7:0]  hk;                                 // hint counter (persistent across PKH calls)
reg [8:0]  hkw;
reg [5:0]  hi_r; reg [7:0] om_r;
reg        e4, g1, g2;

wire [5:0] nbits = (op_r == 4'd8) ? 6'd32 : (op_r == 4'd0) ? 5'd10 : (op_r == 4'd1 || op_r == 4'd6) ? 5'd13 :
                   (op_r == 4'd2 || op_r == 4'd5) ? (e4 ? 5'd4 : 5'd3) :
                   (op_r == 4'd3) ? (g1 ? 5'd20 : 5'd18) : (g2 ? 5'd4 : 5'd6);
wire signed [31:0] kconst = (op_r == 4'd1 || op_r == 4'd6) ? 32'sd4096 :
                            (op_r == 4'd2 || op_r == 4'd5) ? (e4 ? 32'sd4 : 32'sd2) :
                            (op_r == 4'd3) ? (g1 ? 32'sd524288 : 32'sd131072) : 32'sd0;
wire use_k = (op_r == 4'd1 || op_r == 4'd2 || op_r == 4'd3 || op_r == 4'd5 || op_r == 4'd6);
reg signed [31:0] cval;
wire [31:0] vfield = (use_k ? (kconst - cval) : cval);       // op 8 (debug dump): raw 32-bit coefficient
wire [39:0] vmask  = (40'd1 << nbits) - 40'd1;
reg [31:0] r_acc;                              // value assembled for unpack

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= S_IDLE; busy <= 0; done <= 0; we <= 0; bw_en <= 0; sh_in_valid <= 0; hk <= 0; hk_over <= 0; ra <= 0; wa <= 0; wd <= 0; end
    else begin
        done <= 0; we <= 0; bw_en <= 0; sh_in_valid <= 0;
        if (hk_clr) begin hk <= 0; hk_over <= 0; end
        case (st)
        S_IDLE: if (start) begin
            busy <= 1; op_r <= op; sl <= slot; sp <= space; bs <= base; e4 <= eta4; g1 <= g1sel; g2 <= g2sel;
            i <= 0; acc <= 0; accb <= 0; bcnt <= 0; hi_r <= hidx; om_r <= omega; hkw <= 0;
            st <= (op == 4'd5 || op == 4'd6 || op == 4'd9) ? S_UB : (op == 4'd7) ? S_H : S_R;
        end
        // ---------------- pack ----------------
        S_R:  begin ra <= {sl, i[7:0]}; st <= S_RW; end
        S_RW: st <= S_RC;
        S_RC: begin cval <= rq; st <= S_EM; end
        S_EM: begin                                                              // append the field once, then drain whole bytes
            acc <= acc | (({8'd0, vfield} & vmask) << accb); accb <= accb + nbits;
            st <= S_EMW;
        end
        S_EMW: begin                                                             // emit one byte per visit while >= 8 bits
            if (accb >= 6'd8) begin
                if (sp == 2'd3) begin
                    if (sh_in_ready) begin sh_in_valid <= 1; sh_in_byte <= acc[7:0]; acc <= acc >> 8; accb <= accb - 6'd8; bcnt <= bcnt + 13'd1; st <= S_EMG; end
                end else begin
                    bw_en <= 1; bw_space <= sp; bw_addr <= bs + bcnt; bw_data <= acc[7:0]; acc <= acc >> 8; accb <= accb - 6'd8; bcnt <= bcnt + 13'd1;
                end
            end else st <= S_NEXT;
        end
        S_EMG: st <= S_EMW;                                                      // let the sponge take the byte before re-checking ready
        S_NEXT: begin
            if (i == 9'd255) begin st <= S_IDLE; busy <= 0; done <= 1; end
            else begin i <= i + 9'd1; st <= S_R; end
        end
        // ---------------- unpack ----------------
        S_UB: begin                                                              // need more bits?
            if (accb < nbits) begin br_space <= sp; br_addr <= bs + bcnt; st <= S_UBW; end
            else begin
                r_acc <= acc[31:0] & vmask[31:0]; acc <= acc >> nbits; accb <= accb - nbits; st <= S_UW;
            end
        end
        S_UBW: st <= S_UBC;
        S_UBC: begin acc <= acc | ({32'd0, br_data} << accb); accb <= accb + 6'd8; bcnt <= bcnt + 13'd1; st <= S_UB; end
        S_UW: begin
            we <= 1; wa <= {sl, i[7:0]}; wd <= use_k ? (kconst - $signed(r_acc)) : r_acc;
            if (i == 9'd255) begin st <= S_UWW; end else begin i <= i + 9'd1; st <= S_UB; end
        end
        S_UWW: begin st <= S_IDLE; busy <= 0; done <= 1; end
        // ---------------- hint positions (PKH) ----------------
        S_H:  begin ra <= {sl, i[7:0]}; st <= S_HW; end
        S_HW: st <= S_HC;
        S_HC: begin
            if (rq != 32'd0) begin
                if (hk < om_r) begin bw_en <= 1; bw_space <= sp; bw_addr <= bs + {5'd0, hk}; bw_data <= i[7:0]; end
                hk <= hk + 8'd1;
                if (hk >= om_r) hk_over <= 1;
            end
            if (i == 9'd255) st <= S_HEND; else begin i <= i + 9'd1; st <= S_H; end
        end
        S_HEND: begin bw_en <= 1; bw_space <= sp; bw_addr <= bs + {5'd0, om_r} + {7'd0, hi_r}; bw_data <= hk; st <= S_HEND2; end
        S_HEND2: begin st <= S_IDLE; busy <= 0; done <= 1; end
        default: st <= S_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
