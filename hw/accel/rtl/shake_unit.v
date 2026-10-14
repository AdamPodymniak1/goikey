`default_nettype none
// SHAKE128 / SHAKE256 sponge with byte-stream absorb and squeeze (on the lane-serial keccak_core).
//   init(mode)   : mode 0 = SHAKE128 (rate 168), 1 = SHAKE256 (rate 136); clears the state
//   in_valid/in_byte (when in_ready) : absorb one byte
//   finalize (when in_ready)         : pad + permute; afterwards the unit squeezes
//   out_take (when out_ready)        : consume the byte at out_byte; permutes automatically at the rate boundary
module shake_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init,
    input  wire        mode,
    input  wire        in_valid,
    input  wire [7:0]  in_byte,
    output wire        in_ready,
    input  wire        finalize,
    input  wire        out_take,
    output wire        out_ready,
    output wire [7:0]  out_byte,
    output wire        idle
);
reg        m256;
wire [4:0] rate_lanes = m256 ? 5'd17 : 5'd21;          // rate / 8
wire [7:0] rate_bytes = m256 ? 8'd136 : 8'd168;
reg  [4:0] lp;                                          // lane pointer
reg  [2:0] bc;                                          // bytes staged in sw
reg  [55:0] sw;
reg  [7:0] pos;                                         // squeeze byte position within the rate
localparam S_ABS=0, S_FIN2=1, S_PW0=2, S_PGO=3, S_PWAIT=4, S_SQ=5, S_CLR=6, S_CLR0=7;
reg [2:0]  st;
reg        after_sq;                                    // after the permutation: 1 = squeeze, 0 = keep absorbing
reg [1:0]  cool;                                        // holdoff after issuing a core operation (core raises busy 1 clk late)
reg [1:0]  rdw;                                         // lane read latency countdown
wire       kc_busy, kc_done; reg kc_perm, kc_xor; reg [4:0] kc_lane; reg [63:0] kc_val; reg kc_clear;
wire [63:0] kc_rd; wire [4:0] kc_rdl = pos[7:3];
keccak_core kc (.clk(clk), .rst_n(rst_n), .clear(kc_clear), .xor_en(kc_xor), .xor_lane(kc_lane), .xor_val(kc_val),
                .perm(kc_perm), .busy(kc_busy), .done(kc_done), .rd_lane(kc_rdl), .rd_val(kc_rd));
wire       core_ok = !kc_busy && (cool == 2'd0) && !kc_xor && !kc_perm && !kc_clear;
assign in_ready  = (st == S_ABS) && core_ok;       // (not ready while a clear is pending)
assign out_ready = (st == S_SQ) && (rdw == 2'd0);
assign out_byte  = kc_rd[8*pos[2:0] +: 8];
assign idle      = (st == S_ABS) && core_ok;

wire        last_lane = (lp + 5'd1 == rate_lanes);
wire [63:0] pad_lane  = {8'd0, sw} | (64'h1F << {bc, 3'b000}) | (last_lane ? 64'h8000000000000000 : 64'd0);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= S_ABS; kc_perm <= 0; kc_xor <= 0; kc_clear <= 0; lp <= 0; bc <= 0; pos <= 0; m256 <= 0; sw <= 0;
                      after_sq <= 0; cool <= 0; rdw <= 0; end
    else begin
        kc_perm <= 0; kc_xor <= 0; kc_clear <= 0;
        if (cool != 2'd0) cool <= cool - 2'd1;
        if (init) begin m256 <= mode; lp <= 0; bc <= 0; sw <= 0; pos <= 0; st <= S_CLR0; end
        else case (st)
        S_CLR0: if (core_ok) begin kc_clear <= 1; cool <= 2'd3; st <= S_CLR; end      // a running permutation must finish first
        S_CLR: if (core_ok) st <= S_ABS;
        S_ABS: begin
            if (in_valid && core_ok) begin
                if (bc == 3'd7) begin
                    kc_xor <= 1; kc_lane <= lp; kc_val <= {in_byte, sw}; bc <= 0; sw <= 0; cool <= 2'd3;
                    if (last_lane) begin lp <= 0; after_sq <= 0; st <= S_PW0; end else lp <= lp + 5'd1;
                end else begin
                    sw[8*bc +: 8] <= in_byte; bc <= bc + 3'd1;
                end
            end else if (finalize && core_ok) begin
                kc_xor <= 1; kc_lane <= lp; kc_val <= pad_lane; after_sq <= 1; cool <= 2'd3;
                st <= last_lane ? S_PW0 : S_FIN2;
            end
        end
        S_FIN2: if (core_ok) begin
            kc_xor <= 1; kc_lane <= rate_lanes - 5'd1; kc_val <= 64'h8000000000000000; cool <= 2'd3; st <= S_PW0;
        end
        S_PW0:  if (core_ok) st <= S_PGO;                      // the lane XOR (read-modify-write) must be complete
        S_PGO:  begin kc_perm <= 1; cool <= 2'd3; st <= S_PWAIT; end
        S_PWAIT: if (kc_done) begin
            if (after_sq) begin pos <= 0; rdw <= 2'd2; st <= S_SQ; end else st <= S_ABS;
        end
        S_SQ: begin
            if (rdw != 2'd0) rdw <= rdw - 2'd1;
            else if (out_take) begin
                if (pos + 8'd1 == rate_bytes) begin pos <= 0; after_sq <= 1; st <= S_PGO; end
                else begin
                    pos <= pos + 8'd1;
                    if (pos[2:0] == 3'd7) rdw <= 2'd2;               // next lane must be fetched
                end
            end
        end
        default: st <= S_ABS;
        endcase
    end
end
endmodule
`default_nettype wire
