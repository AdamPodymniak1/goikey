`default_nettype none
// SPI slave, mode 0 (CPOL=0, CPHA=0), MSB first, byte oriented. Runs in the system clock domain
// (SCK is sampled; keep SCK <= clk/6, i.e. <= 4 MHz for the 27 MHz clock).
//   rx_valid/rx_byte : one pulse per received byte
//   tx_data/tx_have  : byte for the next byte slot (0x00 filler when !tx_have); tx_take pulses on the first SCK edge of that byte
//                      (so a byte is never lost when CS is released between transactions), giving the producer the
//                      8 bit times of the current byte to prepare the next one
module spi_slave (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sck,
    input  wire       mosi,
    input  wire       cs_n,
    output reg        miso,
    output reg        rx_valid,
    output reg  [7:0] rx_byte,
    input  wire [7:0] tx_data,
    input  wire       tx_have,
    output reg        tx_take
);
reg [2:0] sck_s, cs_s; reg [1:0] mosi_s;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin sck_s <= 3'b000; cs_s <= 3'b111; mosi_s <= 2'b00; end
    else begin sck_s <= {sck_s[1:0], sck}; cs_s <= {cs_s[1:0], cs_n}; mosi_s <= {mosi_s[0], mosi}; end
end
wire sck_rise = (sck_s[2:1] == 2'b01);
wire sck_fall = (sck_s[2:1] == 2'b10);
wire csn      = cs_s[1];

reg [7:0] rx_sh, tx_sh; reg [2:0] bitcnt; reg csn_d; reg cur_real;               // the byte being shifted out is a real tx byte (not filler)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin cur_real <= 1'b0; miso <= 1'b0; rx_valid <= 1'b0; rx_byte <= 8'd0; tx_take <= 1'b0; bitcnt <= 3'd0; rx_sh <= 8'd0; tx_sh <= 8'd0; end
    else begin
        rx_valid <= 1'b0; tx_take <= 1'b0; csn_d <= csn;
        if (csn) begin
            // idle: keep the first bit of the next byte ready on MISO
            bitcnt <= 3'd0;
            miso <= tx_have ? tx_data[7] : 1'b0;
            tx_sh <= tx_have ? {tx_data[6:0], 1'b0} : 8'd0;
            cur_real <= tx_have;
        end else begin
            if (sck_rise) begin
                if (bitcnt == 3'd0) tx_take <= cur_real;              // first clock of a byte: if it is a real byte it is now being sent -> commit it
                rx_sh <= {rx_sh[6:0], mosi_s[1]};
                bitcnt <= bitcnt + 3'd1;
                if (bitcnt == 3'd7) begin rx_valid <= 1'b1; rx_byte <= {rx_sh[6:0], mosi_s[1]}; end
            end
            if (sck_fall) begin
                if (bitcnt == 3'd0) begin                     // first falling edge after a byte boundary: load the next byte
                    miso <= tx_have ? tx_data[7] : 1'b0;
                    tx_sh <= tx_have ? {tx_data[6:0], 1'b0} : 8'd0;
                    cur_real <= tx_have;
                end else begin
                    miso <= tx_sh[7]; tx_sh <= {tx_sh[6:0], 1'b0};
                end
            end
        end
    end
end
endmodule

// uart_tx-compatible byte sender (start/data -> busy/done) that feeds spi_slave's tx slot.
module spi_tx_if (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] data,
    output wire       busy,
    output reg        done,
    output wire [7:0] spi_data,
    output wire       spi_have,
    input  wire       spi_take
);
reg [7:0] hold; reg have;
assign spi_data = hold; assign spi_have = have; assign busy = have;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin have <= 1'b0; done <= 1'b0; hold <= 8'd0; end
    else begin
        done <= 1'b0;
        if (start && !have) begin hold <= data; have <= 1'b1; end
        else if (spi_take && have) begin have <= 1'b0; done <= 1'b1; end
    end
end
endmodule
`default_nettype wire
