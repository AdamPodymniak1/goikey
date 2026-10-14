`default_nettype none

//============================================================================
// Tang Nano 20k top-level wrapper for the Root of Trust
//============================================================================
// Board: Sipeed Tang Nano 20k (GW2AR-18C, QFN88)
//   clk      : 27 MHz onboard crystal (pin 4)
//   btn_s1   : onboard button S1 (pin 88, ACTIVE HIGH) + power-on reset
//   leds     : 3 onboard LEDs (pins 15,16,17, active low)
//   uart_tx  : onboard USB-UART bridge (pin 69)
//
// The root_of_trust core is instantiated with its provisioning /
// read ports tied off, and periodically streams:
//   - a banner
//   - the 128-bit device UUID
//   - 32-bit TRNG words
// over the UART at 115200 baud, so the design can be verified on
// real hardware with nothing but a serial terminal.
//============================================================================

module tangnano20k_top (
    input  wire clk,       // 27 MHz
    input  wire btn_s1,    // button S1, ACTIVE HIGH on Tang Nano 20k
    output wire led0,      // boot_ok     (active low)
    output wire led1,      // trng_valid  (active low, heartbeat)
    output wire led2,      // jtag_locked (active low)
    output wire uart_tx
);

//----------------------------------------------------------------------
// Reset: power-on reset (~2.4 ms) OR S1 pressed (active high on the board)
//----------------------------------------------------------------------

reg [16:0] por_cnt = 17'd0;
always @(posedge clk) begin
    if (btn_s1)
        por_cnt <= 17'd0;
    else if (!por_cnt[16])
        por_cnt <= por_cnt + 17'd1;
end
wire rst_n = por_cnt[16];

//----------------------------------------------------------------------
// Root of Trust core
//----------------------------------------------------------------------

wire [127:0] uid;
wire         uid_valid;
wire [31:0]  trng_data;
wire         trng_valid;
wire [255:0] key_dout;
wire         boot_ok;
wire [31:0]  counter;
wire         jtag_locked;

root_of_trust u_tro (
    .clk            (clk),
    .rst_n          (rst_n),
    .zeroize_n      (1'b1),

    .jtag_tck       (1'b0),
    .jtag_tms       (1'b0),
    .jtag_tdi       (1'b0),
    .jtag_tdo       (),
    .jtag_locked    (jtag_locked),

    .uid_o          (uid),
    .uid_valid      (uid_valid),

    .trng_o         (trng_data),
    .trng_valid     (trng_valid),

    .write_slot_idx (4'd0),
    .write_key_data (256'd0),
    .write_en       (1'b0),
    .write_auth     (1'b0),

    .read_slot_idx  (4'd0),
    .read_en        (1'b0),
    .read_auth      (1'b0),
    .key_o          (key_dout),

    .boot_ok        (boot_ok),
    .counter_o      (counter)
);

//----------------------------------------------------------------------
// LEDs (active low on Tang Nano 20k)
//----------------------------------------------------------------------

reg [23:0] heartbeat = 24'd0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        heartbeat <= 24'd0;
    else
        heartbeat <= heartbeat + 24'd1;
end

assign led0 = ~boot_ok;          // lit when boot integrity OK
assign led1 = ~heartbeat[23];    // ~1.6 Hz heartbeat from 27 MHz
assign led2 = ~jtag_locked;      // lit when JTAG is locked

//----------------------------------------------------------------------
// UART transmitter (115200 baud @ 27 MHz)
//----------------------------------------------------------------------

localparam CLKS_PER_BIT = 27_000_000 / 115200; // 234

reg  [7:0]  tx_data  = 8'h00;
reg         tx_start = 1'b0;
wire        tx_busy;
wire        tx_done;

uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
    .clk      (clk),
    .rst_n    (rst_n),
    .tx_start (tx_start),
    .tx_data  (tx_data),
    .tx_busy  (tx_busy),
    .tx_done  (tx_done),
    .tx       (uart_tx)
);

//----------------------------------------------------------------------
// Periodic reporter, 4 lines-pairs per second:
//   "TRO UID: <32 hex>\r\n"
//   "TRO RND: <64 hex>\r\n"     (256 fresh TRNG bits)
//----------------------------------------------------------------------

localparam LINE_LEN = 118;               // 43 + 75 characters
localparam TICK_MAX = 27_000_000 / 4;    // 250 ms

reg [24:0] tick = 25'd0;
wire       tick_go = (tick == TICK_MAX);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)       tick <= 25'd0;
    else if (tick_go) tick <= 25'd0;
    else              tick <= tick + 25'd1;
end

// Rolling 256-bit pool of TRNG words; snapshotted at the start of a report
reg [255:0] rnd_pool = 256'd0;
reg [255:0] rnd_snap = 256'd0;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)          rnd_pool <= 256'd0;
    else if (trng_valid) rnd_pool <= {rnd_pool[223:0], trng_data};
end

function [7:0] hex_char(input [3:0] nib);
    hex_char = (nib < 4'd10) ? (8'h30 + {4'd0, nib}) : (8'h57 + {4'd0, nib});
endfunction

localparam [71:0] HDR_UID = "TRO UID: ";
localparam [71:0] HDR_RND = "TRO RND: ";

reg [6:0] idx = 7'd0;
reg [7:0] tx_byte;
always @(*) begin
    if      (idx <= 7'd8)   tx_byte = HDR_UID[71 - 8*idx -: 8];
    else if (idx <= 7'd40)  tx_byte = hex_char(uid[127 - 4*(idx - 7'd9) -: 4]);
    else if (idx == 7'd41)  tx_byte = 8'h0D;
    else if (idx == 7'd42)  tx_byte = 8'h0A;
    else if (idx <= 7'd51)  tx_byte = HDR_RND[71 - 8*(idx - 7'd43) -: 8];
    else if (idx <= 7'd115) tx_byte = hex_char(rnd_snap[255 - 4*(idx - 7'd52) -: 4]);
    else if (idx == 7'd116) tx_byte = 8'h0D;
    else                    tx_byte = 8'h0A;
end

localparam ST_IDLE = 2'd0, ST_LOAD = 2'd1, ST_SEND = 2'd2;
reg [1:0] st = ST_IDLE;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st <= ST_IDLE; idx <= 7'd0; tx_data <= 8'h00; tx_start <= 1'b0;
        rnd_snap <= 256'd0;
    end else begin
        tx_start <= 1'b0;
        case (st)
            ST_IDLE: if (tick_go) begin
                idx <= 7'd0;
                rnd_snap <= rnd_pool;
                st <= ST_LOAD;
            end
            ST_LOAD: begin
                tx_data <= tx_byte; tx_start <= 1'b1; st <= ST_SEND;
            end
            ST_SEND: if (tx_done) begin
                if (idx == LINE_LEN - 1) st <= ST_IDLE;
                else begin idx <= idx + 7'd1; st <= ST_LOAD; end
            end
            default: st <= ST_IDLE;
        endcase
    end
end

endmodule

//============================================================================
// Minimal UART transmitter
//============================================================================
module uart_tx #(
    parameter CLKS_PER_BIT = 234
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx_busy,
    output reg        tx_done,
    output reg        tx
);

localparam ST_IDLE  = 2'd0;
localparam ST_START = 2'd1;
localparam ST_DATA  = 2'd2;
localparam ST_STOP  = 2'd3;

reg [1:0]  st     = ST_IDLE;
reg [15:0] clk_cnt = 16'd0;
reg [2:0]  bit_idx = 3'd0;
reg [7:0]  data_r  = 8'h00;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st      <= ST_IDLE;
        tx      <= 1'b1;
        tx_busy <= 1'b0;
        tx_done <= 1'b0;
        clk_cnt <= 16'd0;
        bit_idx <= 3'd0;
    end else begin
        tx_done <= 1'b0;

        case (st)
            ST_IDLE: begin
                tx      <= 1'b1;
                tx_busy <= 1'b0;
                clk_cnt <= 16'd0;
                bit_idx <= 3'd0;
                if (tx_start) begin
                    tx_busy <= 1'b1;
                    data_r  <= tx_data;
                    st      <= ST_START;
                end
            end

            ST_START: begin
                tx <= 1'b0;
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 16'd0;
                    st      <= ST_DATA;
                end else
                    clk_cnt <= clk_cnt + 16'd1;
            end

            ST_DATA: begin
                tx <= data_r[bit_idx];
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 16'd0;
                    if (bit_idx == 3'd7) begin
                        bit_idx <= 3'd0;
                        st      <= ST_STOP;
                    end else
                        bit_idx <= bit_idx + 3'd1;
                end else
                    clk_cnt <= clk_cnt + 16'd1;
            end

            ST_STOP: begin
                tx <= 1'b1;
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 16'd0;
                    tx_done <= 1'b1;
                    tx_busy <= 1'b0;
                    st      <= ST_IDLE;
                end else
                    clk_cnt <= clk_cnt + 16'd1;
            end
        endcase
    end
end

endmodule

`default_nettype wire