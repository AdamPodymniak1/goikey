`default_nettype none
// Byte-space operations of the ML-DSA engine. Spaces: 0 RX, 1 TX, 2 SC (scratch) via the byte bus.
//   op 0 ABS    absorb [sp1:off1, len) into SHAKE        op 1 SQ     squeeze len bytes into [sp1:off1)
//   op 2 XORKS  [sp1:off1) ^= keystream (squeezed)       op 3 CMP    flag_diff |= ([sp1:off1) != [sp2:off2)) over len bytes
//   op 4 CPY    [sp1:off1) <= [sp2:off2), len bytes      op 5 FILL0  zero [sp1:off1, len)
//   op 6 RNG    [sp1:off1) <= TRNG bytes                 op 7 ABSRX  absorb RX[off1 .. plen)
//   op 8 ABSI   absorb the byte imm[7:0]                 op 9 ABSNZ  absorb imm[15:0] as 2 bytes little endian
//   op 10 ABSM  absorb the 32-byte MASTER key           op 11 WUID  write the 16-byte device UID to [sp1:off1)
//   op 12 WIMM  write imm[15:0] (2 bytes, big endian) to [sp1:off1)   op 13 BFILL  fill [sp1:off1, len) with imm[7:0]
// Byte bus: br_addr in cycle t -> br_data valid in cycle t+1 or t+2 (addresses are held for 3 cycles).
module pq_bytes #(parameter [255:0] MASTER = 256'h0, parameter [127:0] UID = 128'h0)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [3:0]  op,
    input  wire [1:0]  sp1,
    input  wire [12:0] off1,
    input  wire [12:0] len,
    input  wire [1:0]  sp2,
    input  wire [12:0] off2,
    input  wire [15:0] imm,
    input  wire [15:0] plen,
    output reg         busy,
    output reg         done,
    output reg         flag_diff,
    input  wire        flag_clr,
    // byte bus
    output reg         bw_en,
    output reg  [1:0]  bw_space,
    output reg  [12:0] bw_addr,
    output reg  [7:0]  bw_data,
    output reg  [1:0]  br_space,
    output reg  [12:0] br_addr,
    input  wire [7:0]  br_data,
    // SHAKE
    output reg         sh_in_valid,
    output reg  [7:0]  sh_in_byte,
    input  wire        sh_in_ready,
    input  wire        out_ready,
    input  wire [7:0]  out_byte,
    output reg         out_take,
    // TRNG
    input  wire        trng_valid,
    input  wire [31:0] trng_data
);
localparam S_IDLE=0, S_STEP=1, S_RA=2, S_RAW=3, S_RAC=4, S_RB=5, S_RBW=6, S_RBC=7, S_ABSF=8, S_GAP=9,
           S_SQG=10, S_SQT=11, S_WR=12, S_NEXT=13, S_RNGW=14, S_AFTER=15;
reg [3:0]  st, back;
reg [3:0]  op_r; reg [1:0] s1, s2; reg [12:0] o1, o2, n, k; reg [15:0] im;
reg [7:0]  a, b, ks;
reg [31:0] rw;
wire [7:0] mbyte = MASTER[255 - 8*k[4:0] -: 8];
wire [7:0] ubyte = UID[127 - 8*k[3:0] -: 8];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= S_IDLE; busy <= 0; done <= 0; bw_en <= 0; sh_in_valid <= 0; out_take <= 0; flag_diff <= 0; end
    else begin
        done <= 0; bw_en <= 0; sh_in_valid <= 0; out_take <= 0;
        if (flag_clr) flag_diff <= 0;
        case (st)
        S_IDLE: if (start) begin
            busy <= 1; op_r <= op; s1 <= sp1; o1 <= off1; s2 <= sp2; o2 <= off2; im <= imm; k <= 0;
            case (op)
              4'd7:  begin n <= plen[12:0] - off1; end
              4'd8:  n <= 13'd1;
              4'd9:  n <= 13'd2;
              4'd10: n <= 13'd32;
              4'd11: n <= 13'd16;
              4'd12: n <= 13'd2;
              default: n <= len;
            endcase
            st <= S_STEP;
        end
        S_STEP: begin
            if (k >= n) begin st <= S_AFTER; end
            else case (op_r)
              4'd0, 4'd7:  begin st <= S_RA; back <= S_ABSF; end                 // read a byte, then feed it
              4'd1:        begin st <= S_SQG; back <= S_WR; end
              4'd2:        begin st <= S_RA;  back <= S_SQG; end                 // read, then squeeze + xor
              4'd3:        begin st <= S_RA;  back <= S_RB; end
              4'd4:        begin st <= S_RB;  back <= S_WR; end
              4'd5:        begin a <= 8'd0; st <= S_WR; end
              4'd6:        begin
                  if (k[1:0] == 2'd0) st <= S_RNGW;                              // need a fresh TRNG word
                  else begin a <= rw[8*k[1:0] +: 8]; st <= S_WR; end
              end
              4'd8:        begin a <= im[7:0]; st <= S_ABSF; end
              4'd9:        begin a <= k[0] ? im[15:8] : im[7:0]; st <= S_ABSF; end
              4'd10:       begin a <= mbyte; st <= S_ABSF; end
              4'd11:       begin a <= ubyte; st <= S_WR; end
              4'd12:       begin a <= k[0] ? im[7:0] : im[15:8]; st <= S_WR; end
              4'd13:       begin a <= im[7:0]; st <= S_WR; end
              default:     st <= S_AFTER;
            endcase
        end
        // ---- read byte a from (s1, o1+k) ----
        S_RA:  begin br_space <= s1; br_addr <= o1 + k; st <= S_RAW; end
        S_RAW: st <= S_RAC;
        S_RAC: begin
            a <= br_data;
            if (op_r == 4'd0 || op_r == 4'd7) st <= S_ABSF;
            else if (op_r == 4'd2) st <= S_SQG;
            else st <= S_RB;
        end
        // ---- read byte b from (s2, o2+k) ----
        S_RB:  begin br_space <= (op_r == 4'd3) ? s2 : s2; br_addr <= o2 + k; st <= S_RBW; end
        S_RBW: st <= S_RBC;
        S_RBC: begin
            if (op_r == 4'd3) begin if (a != br_data) flag_diff <= 1; st <= S_NEXT; end
            else begin a <= br_data; st <= S_WR; end                               // CPY
        end
        // ---- feed a to SHAKE ----
        S_ABSF: if (sh_in_ready) begin sh_in_valid <= 1; sh_in_byte <= a; st <= S_GAP; end
        S_GAP: st <= S_NEXT;                                                         // let the sponge take the byte before re-checking ready
        // ---- squeezed byte ----
        S_SQG: if (out_ready) begin
            if (op_r == 4'd2) a <= a ^ out_byte; else a <= out_byte;
            out_take <= 1; st <= S_SQT;
        end
        S_SQT: st <= S_WR;
        // ---- write a to (s1, o1+k) ----
        S_WR: begin bw_en <= 1; bw_space <= s1; bw_addr <= o1 + k; bw_data <= a; st <= S_NEXT; end
        S_NEXT: begin k <= k + 13'd1; st <= S_STEP; end
        S_RNGW: if (trng_valid) begin rw <= trng_data; a <= trng_data[7:0]; st <= S_WR; end
        S_AFTER: begin busy <= 0; done <= 1; st <= S_IDLE; end
        default: st <= S_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
