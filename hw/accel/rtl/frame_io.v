`default_nettype none
// Framed command link.
//   host->FPGA : A5 | cmd | len_lo | len_hi | payload[len] | crc_lo | crc_hi
//   FPGA->host : 5A | status | len_lo | len_hi | payload[len] | crc_lo | crc_hi
//   CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) over cmd..payload / status..payload.
// Payload lives in an 8 KiB RX RAM and an 8 KiB TX RAM (dual-port, 1-clk read latency).
module crc16_step(input wire [15:0] c, input wire [7:0] d, output wire [15:0] n);
    function [15:0] f(input [15:0] c, input [7:0] d);
        integer i; reg [15:0] x;
        begin x = c ^ {d, 8'h00};
              for (i = 0; i < 8; i = i + 1) x = x[15] ? ((x << 1) ^ 16'h1021) : (x << 1);
              f = x; end
    endfunction
    assign n = f(c, d);
endmodule

module frame_rx (
    input  wire clk, input wire rst_n,
    input  wire byte_valid, input wire [7:0] byte_in,
    input  wire accept,                       // 0 = discard payload (busy)
    output reg  [12:0] wa, output reg we, output reg [7:0] wd,
    output reg  frame_ok, output reg frame_bad,
    output reg  [7:0] cmd, output reg [15:0] len
);
localparam R_SOF=0, R_CMD=1, R_L0=2, R_L1=3, R_PL=4, R_C0=5, R_C1=6;
reg [2:0] st; reg [15:0] cnt, crc; reg [7:0] c0; reg [23:0] idle;
wire [15:0] crc_n; crc16_step cs(.c(crc), .d(byte_in), .n(crc_n));
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st<=R_SOF; we<=0; frame_ok<=0; frame_bad<=0; idle<=0; wa<=0; end
    else begin
        we <= 0; frame_ok <= 0; frame_bad <= 0;
        if (byte_valid) idle <= 0; else if (st != R_SOF) idle <= idle + 1;
        if (idle[22]) begin st <= R_SOF; idle <= 0; end        // ~155 ms stall -> resync
        if (byte_valid) case (st)
            R_SOF: if (byte_in == 8'hA5) begin crc <= 16'hFFFF; st <= R_CMD; end
            R_CMD: begin cmd <= byte_in; crc <= crc_n; st <= R_L0; end
            R_L0:  begin len[7:0] <= byte_in; crc <= crc_n; st <= R_L1; end
            R_L1:  begin len[15:8] <= byte_in; crc <= crc_n; cnt <= 0; wa <= 0;
                         st <= ({byte_in, len[7:0]} == 16'd0) ? R_C0 : R_PL; end
            R_PL:  begin
                crc <= crc_n;
                if (accept && cnt < 16'd8192) begin we <= 1; wa <= cnt[12:0]; wd <= byte_in; end
                cnt <= cnt + 1;
                if (cnt + 1 == len) st <= R_C0;
            end
            R_C0:  begin c0 <= byte_in; st <= R_C1; end
            R_C1:  begin
                st <= R_SOF;
                if ({byte_in, c0} == crc && accept && len <= 16'd8192) frame_ok <= 1;
                else frame_bad <= 1;
            end
            default: st <= R_SOF;
        endcase
    end
end
endmodule

module frame_tx (
    input  wire clk, input wire rst_n,
    input  wire req, input wire [7:0] status, input wire [15:0] len,
    output reg  [12:0] ra, input wire [7:0] rd,     // TX RAM read (1-clk latency)
    // byte transport (UART or SPI): pulse bstart with bdata, wait for bdone
    output reg  bstart, output reg [7:0] bdata, input wire bbusy, input wire bdone,
    output wire busy
);
localparam T_IDLE=0, T_FETCH=1, T_FETCH2=2, T_LOAD=3, T_SEND=4, T_WAIT=5;
reg [2:0] st; reg [16:0] pos; reg [15:0] crc, len_r; reg [7:0] stat_r;
assign busy = (st != T_IDLE);

wire [16:0] end_pl = 17'd4 + {1'b0, len_r};
wire in_pl  = (pos >= 17'd4) && (pos < end_pl);
wire in_crc = (pos >= 17'd1) && (pos < end_pl);         // status .. payload
reg  [7:0] b;
always @(*) begin
    if      (pos == 17'd0) b = 8'h5A;
    else if (pos == 17'd1) b = stat_r;
    else if (pos == 17'd2) b = len_r[7:0];
    else if (pos == 17'd3) b = len_r[15:8];
    else if (in_pl)        b = rd;
    else if (pos == end_pl) b = crc[7:0];
    else                   b = crc[15:8];
end
wire [15:0] crc_n; crc16_step cs(.c(crc), .d(b), .n(crc_n));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st<=T_IDLE; bstart<=0; pos<=0; ra<=0; crc<=16'hFFFF; bdata<=0; end
    else begin
        bstart <= 0;
        case (st)
        T_IDLE: if (req) begin stat_r<=status; len_r<=len; pos<=0; crc<=16'hFFFF; st<=T_FETCH; end
        T_FETCH:  begin ra <= pos[12:0] - 13'd4; st <= T_FETCH2; end
        T_FETCH2: st <= T_LOAD;
        T_LOAD:   begin bdata <= b; if (in_crc) crc <= crc_n; st <= T_SEND; end
        T_SEND:   if (!bbusy) begin bstart <= 1; st <= T_WAIT; end
        T_WAIT:   if (bdone) begin
            if (pos == end_pl + 17'd1) st <= T_IDLE;
            else begin pos <= pos + 17'd1; st <= T_FETCH; end
        end
        default: st <= T_IDLE;
        endcase
    end
end
endmodule
`default_nettype wire
