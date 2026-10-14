`timescale 1ns/1ps
module tb_ecc_seq;
reg clk=0, rst_n=0; always #5 clk=~clk;
reg h_we=0; reg [6:0] h_wreg=0; reg [3:0] h_wword=0; reg [15:0] h_wdata=0; reg [6:0] h_rreg=0; reg [3:0] h_rword=0;
wire [15:0] h_q; reg h_go=0; reg [10:0] h_pc=0; wire h_busy, h_done, h_flag;
wire [12:0] rx_a, tx_wa; wire tx_we; wire [7:0] tx_wd, f_status; wire [15:0] f_len; wire h5_begin, h5_in_valid, h5_end; wire [7:0] h5_in_byte;
wire e_start, e_done, e_lt; wire [3:0] e_op; wire [6:0] e_d, e_a, e_b; wire [1:0] e_msel; wire [10:0] x_ra, x_wa; wire x_we; wire [15:0] x_wd, x_rq;
bn_engine eng (.clk(clk), .rst_n(rst_n), .start(1'b0), .op(8'd0), .ra(6'd0), .rb(6'd0), .rc(6'd0), .rd(6'd0), .imm0(32'd0), .done(), .flag(), .bus_busy(),
    .bw_en(), .bw_space(), .bw_addr(), .bw_data(), .br_space(), .br_addr(), .br_data(8'd0), .trng_valid(1'b0), .trng_data(32'd0),
    .e_start(e_start), .e_op(e_op), .e_d(e_d), .e_a(e_a), .e_b(e_b), .e_msel(e_msel), .e_done(e_done), .e_lt(e_lt),
    .x_ra(x_ra), .x_we(x_we), .x_wa(x_wa), .x_wd(x_wd), .x_rq(x_rq), .busy_o());
ecc_seq dut(.clk(clk),.rst_n(rst_n),.h_we(h_we),.h_wreg(h_wreg),.h_wword(h_wword),.h_wdata(h_wdata),.h_rreg(h_rreg),.h_rword(h_rword),.h_q(h_q),.h_go(h_go),.h_pc(h_pc),.h_busy(h_busy),.h_done(h_done),.h_flag(h_flag),
  .plen(16'd0),.rx_a(rx_a),.rx_q(8'd0),.tx_we(tx_we),.tx_wa(tx_wa),.tx_wd(tx_wd),.f_status(f_status),.f_len(f_len),.trng_valid(1'b0),.trng_data(32'd0),
  .h5_begin(h5_begin),.h5_in_valid(h5_in_valid),.h5_in_byte(h5_in_byte),.h5_in_ready(1'b1),.h5_end(h5_end),.h5_done(1'b0),.h5_ra(),.h5_q(64'd0),
  .e_start(e_start),.e_op(e_op),.e_d(e_d),.e_a(e_a),.e_b(e_b),.e_msel(e_msel),.e_done(e_done),.e_lt(e_lt),.x_ra(x_ra),.x_we(x_we),.x_wa(x_wa),.x_wd(x_wd),.x_rq(x_rq));
integer fails=0, w, c0, cyc=0; reg [255:0] got; reg seen=0; always @(posedge clk) cyc<=cyc+1; always @(posedge clk) if (h_done) seen<=1;
task putreg(input [6:0] r, input [255:0] v); begin for (w=0; w<16; w=w+1) begin @(negedge clk); h_we=1; h_wreg=r; h_wword=w; h_wdata=v[16*w +: 16]; end @(negedge clk); h_we=0; end endtask
task getreg(input [6:0] r); begin for (w=0; w<16; w=w+1) begin h_rreg=r; h_rword=w; @(negedge clk); @(negedge clk); got[16*w +: 16]=h_q; end end endtask
task go(input [10:0] pc); begin seen=0; c0=cyc; @(negedge clk); h_pc=pc; h_go=1; @(negedge clk); h_go=0; wait(seen); @(negedge clk); end endtask
initial begin #30 rst_n=1; #30;
  putreg(1, 256'h6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296);
  putreg(2, 256'h4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5);
  go(111); $display("oncurve_ok: %0d clk, flag=%b (expect 0); 23 instructions", cyc-c0, h_flag);
  if (h_flag !== 1'b0) begin fails=fails+1; $display("FAIL oncurve_ok: flag"); end
  putreg(1, 256'h6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296);
  putreg(2, 256'h4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f4);
  go(111); $display("oncurve_bad: %0d clk, flag=%b (expect 1); 23 instructions", cyc-c0, h_flag);
  if (h_flag !== 1'b1) begin fails=fails+1; $display("FAIL oncurve_bad: flag"); end
  putreg(0, 256'h453ea1da78633074b7970386fee29476311624273bfd1d338d0038ec42650644);
  go(848); $display("ed_base: %0d clk, flag=%b (expect 0); 11541 instructions", cyc-c0, h_flag);
  if (h_flag !== 1'b0) begin fails=fails+1; $display("FAIL ed_base: flag"); end
  getreg(3); if (got !== 256'h01601abf51ff686ddef32e78f9b002b7b2a2e88b464d6b8baa4afdbfe9fbd6d7) begin fails=fails+1; $display("FAIL ed_base: r3 got %h exp 01601abf51ff686ddef32e78f9b002b7b2a2e88b464d6b8baa4afdbfe9fbd6d7", got); end else $display("ok ed_base: r3");
  getreg(4); if (got !== 256'h2a97fc5442834161d338c2a35074205fe14cd328764b9f7ce884c82e35acce22) begin fails=fails+1; $display("FAIL ed_base: r4 got %h exp 2a97fc5442834161d338c2a35074205fe14cd328764b9f7ce884c82e35acce22", got); end else $display("ok ed_base: r4");
  putreg(13, 256'h3b5f3d86268ecc45dc6bf1e1a399f82a65aa9c8279f248b08cb4a0d7d6225675);
  putreg(14, 256'h03e0a813bdc2ae9963d2e49085ef3430ed038db4de38378426d0b944a2863a7f);
  go(981); $display("ed_reduce: %0d clk, flag=%b (expect 0); 9 instructions", cyc-c0, h_flag);
  if (h_flag !== 1'b0) begin fails=fails+1; $display("FAIL ed_reduce: flag"); end
  getreg(7); if (got !== 256'h0361e262eca69f840025178b60a69a25ee5317ebc0c5b25c655c0cf3a0802a90) begin fails=fails+1; $display("FAIL ed_reduce: r7 got %h exp 0361e262eca69f840025178b60a69a25ee5317ebc0c5b25c655c0cf3a0802a90", got); end else $display("ok ed_reduce: r7");
  putreg(7, 256'h015e871a97524d6af51e8722c21b609228ce6f2410645d51c6f8da3eabe19f58);
  putreg(11, 256'h0da9735bebcd1f5ec9c18070b6d13089633a50eee0f9e038eb8f624fb804d820);
  putreg(12, 256'h453ea1da78633074b7970386fee29476311624273bfd1d338d0038ec42650644);
  go(990); $display("ed_sign_s: %0d clk, flag=%b (expect 0); 10 instructions", cyc-c0, h_flag);
  if (h_flag !== 1'b0) begin fails=fails+1; $display("FAIL ed_sign_s: flag"); end
  getreg(8); if (got !== 256'h0f3c5f38824cd00ef9d3f87bf22f01ad40a25b41fd4c61348fe7c10a752ca080) begin fails=fails+1; $display("FAIL ed_sign_s: r8 got %h exp 0f3c5f38824cd00ef9d3f87bf22f01ad40a25b41fd4c61348fe7c10a752ca080", got); end else $display("ok ed_sign_s: r8");
  if (fails==0) $display("ALL PASS"); else $display("FAILED %0d", fails);
  $finish;
end
initial begin #2000000000 $display("TIMEOUT"); $finish; end
endmodule
