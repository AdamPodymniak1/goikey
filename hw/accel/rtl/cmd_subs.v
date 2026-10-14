`default_nettype none
// ---------------------------------------------------------------------------
// Subroutines used by the command dispatcher. All take a 1-clk `start`, run, and
// raise a 1-clk `done`. mem_q is the RX-RAM read data (1-clk latency).
// ---------------------------------------------------------------------------

// Read n (1..7) bytes starting at ptr_i; acc = {b0, b1, ... b(n-1)} right-aligned (bits above 8n: stale).
module sub_rdn (
    input  wire clk, input wire rst_n,
    input  wire start, input wire [12:0] ptr_i, input wire [5:0] n,
    output reg  [12:0] a, input wire [7:0] mem_q,
    output reg  [55:0] acc, output reg done, output reg active
);
reg [1:0] s; reg [5:0] c;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin s<=0; done<=0; active<=0; a<=0; c<=0; end
    else begin
        done <= 0;
        case (s)
        0: if (start) begin a <= ptr_i; c <= n; active <= 1; s <= 1; end
        1: s <= 2;                                  // BRAM read latency
        2: begin
            acc <= {acc[47:0], mem_q}; c <= c - 1; a <= a + 1;
            if (c == 1) begin done <= 1; active <= 0; s <= 0; end else s <= 1;
        end
        endcase
    end
end
endmodule

// Stream n bytes from RX RAM to the hash unit: message bytes (key_i=0, only while `ready`) or key bytes (key_i=1).
module sub_feed (
    input  wire clk, input wire rst_n,
    input  wire start, input wire [12:0] ptr_i, input wire [15:0] n, input wire key_i,
    output reg  [12:0] a, input wire [7:0] mem_q,
    input  wire ready,                             // the sink can take a byte
    output reg  ob_valid, output reg [7:0] ob_byte, output reg ob_key,
    output reg  done, output reg active
);
reg [1:0] s; reg [15:0] r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin s<=0; done<=0; active<=0; ob_valid<=0; a<=0; r<=0; ob_key<=0; end
    else begin
        done <= 0; ob_valid <= 0;
        case (s)
        0: if (start) begin
               a <= ptr_i; r <= n; ob_key <= key_i; active <= 1;
               if (n == 0) begin done <= 1; active <= 0; end else s <= 1;
           end
        1: s <= 2;
        2: if (ready) begin
               ob_valid <= 1; ob_byte <= mem_q; a <= a + 1; r <= r - 1;
               if (r == 1) begin s <= 3; end else s <= 1;
           end
        3: begin done <= 1; active <= 0; s <= 0; end
        endcase
    end
end
endmodule

// Write the top n (1..16) bytes of `d` (MSB first) to TX RAM at base.
module sub_emit (
    input  wire clk, input wire rst_n,
    input  wire start, input wire [12:0] base, input wire [127:0] d, input wire [5:0] n,
    output reg  we, output reg [12:0] wa, output reg [7:0] wd,
    output reg  done
);
reg act; reg [127:0] sh; reg [5:0] c;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin act<=0; done<=0; we<=0; wa<=0; wd<=0; c<=0; end
    else begin
        done <= 0; we <= 0;
        if (start) begin act <= 1; sh <= d; c <= n; wa <= base - 13'd1; end
        else if (act) begin
            if (c == 0) begin act <= 0; done <= 1; end
            else begin we <= 1; wa <= wa + 13'd1; wd <= sh[127:120]; sh <= {sh[119:0], 8'd0}; c <= c - 1; end
        end
    end
end
endmodule
`default_nettype wire
