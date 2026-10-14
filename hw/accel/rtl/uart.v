`default_nettype none
// UART 8N1 transmitter / receiver, parameterised by clocks-per-bit.
module uart_tx #(parameter CPB = 18)(
    input  wire clk, input wire rst_n,
    input  wire start, input wire [7:0] data,
    output reg  busy, output reg done, output reg tx
);
reg [15:0] c; reg [3:0] n; reg [9:0] sh;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin busy<=0; done<=0; tx<=1; c<=0; n<=0; sh<=10'h3ff; end
    else begin
        done <= 0;
        if (!busy) begin
            tx <= 1;
            if (start) begin sh <= {1'b1, data, 1'b0}; busy <= 1; c <= 0; n <= 0; end
        end else begin
            tx <= sh[0];
            if (c == CPB-1) begin
                c <= 0; sh <= {1'b1, sh[9:1]}; n <= n + 1;
                if (n == 4'd9) begin busy <= 0; done <= 1; tx <= 1; end
            end else c <= c + 1;
        end
    end
end
endmodule

module uart_rx #(parameter CPB = 18)(
    input  wire clk, input wire rst_n, input wire rx,
    output reg  valid, output reg [7:0] data
);
reg r0, r1; reg [15:0] c; reg [3:0] n; reg act; reg [7:0] sh;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin r0<=1; r1<=1; valid<=0; act<=0; c<=0; n<=0; data<=0; sh<=0; end
    else begin
        r0 <= rx; r1 <= r0; valid <= 0;
        if (!act) begin
            if (!r1) begin act <= 1; c <= CPB/2; n <= 0; end   // start edge: wait to mid-bit
        end else begin
            if (c == CPB-1) begin
                c <= 0;
                if (n == 4'd0) begin if (r1) act <= 0; end      // false start
                else if (n <= 4'd8) sh <= {r1, sh[7:1]};
                else begin                                       // stop bit
                    act <= 0;
                    if (r1) begin valid <= 1; data <= sh; end
                end
                n <= n + 1;
            end else c <= c + 1;
        end
    end
end
endmodule
`default_nettype wire
