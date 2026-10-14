`timescale 1ns/1ps
// Unit test of pq_rsa: executes an op list (ops.hex: 6 words per op = op,a,b,c,d,imm; word 0 = op count) against byte memories.
module tb_pq_rsa;
reg clk = 0, rst_n = 0; always #5 clk = ~clk;
reg start = 0; reg [7:0] op; reg [5:0] ra, rb, rc, rd; reg [31:0] imm;
wire done, flag, bus_busy, bw_en; wire [1:0] bw_space, br_space; wire [12:0] bw_addr, br_addr; wire [7:0] bw_data; reg [7:0] br_data;
reg trng_valid = 0; reg [31:0] trng_data = 0;
bn_engine dut (.clk(clk), .rst_n(rst_n), .start(start), .op(op), .ra(ra), .rb(rb), .rc(rc), .rd(rd), .imm0(imm), .done(done), .flag(flag), .bus_busy(bus_busy),
    .bw_en(bw_en), .bw_space(bw_space), .bw_addr(bw_addr), .bw_data(bw_data), .br_space(br_space), .br_addr(br_addr), .br_data(br_data),
    .trng_valid(trng_valid), .trng_data(trng_data),
    .e_start(1'b0), .e_op(4'd0), .e_d(7'd0), .e_a(7'd0), .e_b(7'd0), .e_msel(2'd0), .e_done(), .e_lt(),
    .x_ra(11'd0), .x_we(1'b0), .x_wa(11'd0), .x_wd(16'd0), .x_rq(), .busy_o());
reg [7:0] rxm [0:8191]; reg [7:0] txm [0:8191]; reg [7:0] scm [0:2047];
always @(posedge clk) begin
    br_data <= (br_space == 2'd0) ? rxm[br_addr] : (br_space == 2'd1) ? txm[br_addr] : scm[br_addr[10:0]];
    if (bw_en) case (bw_space) 2'd0: rxm[bw_addr] <= bw_data; 2'd1: txm[bw_addr] <= bw_data; default: scm[bw_addr[10:0]] <= bw_data; endcase
end
// TRNG model: a new 32-bit word every 40 clocks (word k = 0x9E3779B1*(k+1))
reg [31:0] tk = 0; reg [5:0] tc = 0; reg in_rrng = 0;
always @(posedge clk) begin
    trng_valid <= 0; tc <= tc + 1;
    if (tc == 6'd39 && in_rrng) begin tc <= 0; tk <= tk + 1; trng_data <= 32'h9E3779B1 * (tk + 1); trng_valid <= 1; end
end
reg [31:0] ops [0:65535]; integer n, i, f, cycles, ft, r, w;
initial begin
    for (i = 0; i < 8192; i = i + 1) begin rxm[i] = 0; txm[i] = 0; end
    $readmemh("ops.hex", ops); $readmemh("rx.hex", rxm); for (i = 0; i < 2048; i = i + 1) scm[i] = 0; $readmemh("sc.hex", scm);
    n = ops[0];
    #50 rst_n = 1; #50;
    f = $fopen("flags.txt", "w"); ft = $fopen("trace.txt", "w");
    for (i = 0; i < n; i = i + 1) begin
        @(posedge clk); op <= ops[1 + 6*i]; ra <= ops[2 + 6*i]; rb <= ops[3 + 6*i]; rc <= ops[4 + 6*i]; rd <= ops[5 + 6*i]; imm <= ops[6 + 6*i]; start <= 1; in_rrng <= (ops[1 + 6*i] == 32'hA2);
        @(posedge clk); start <= 0;
        cycles = 0;
        while (!done) begin @(posedge clk); cycles = cycles + 1; if (cycles > 40000000) begin $display("TIMEOUT op %0d (%h)", i, ops[1 + 6*i]); $finish; end end
        in_rrng <= 0;
        for (r = 0; r < 20; r = r + 1) begin for (w = 63; w >= 0; w = w - 1) $fwrite(ft, "%04h", dut.rf[r*64 + w]); $fwrite(ft, "\n"); end
        $fwrite(f, "%0d %h %0d %0d\n", i, ops[1 + 6*i], flag, cycles);
    end
    $fclose(f); $fclose(ft);
    $writememh("tx_out.hex", txm);
    $display("DONE");
    $finish;
end
endmodule
