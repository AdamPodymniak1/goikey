#!/usr/bin/env python3
"""tb_pq_smp.v: samplers fed by the real shake_unit, compared with pq_model."""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pq_model as M
random.seed(8)
def rb(n): return bytes(random.randrange(256) for _ in range(n))
cases = []
def add(name, mode, bits, seed, expect, tau=0): cases.append((name, mode, bits, seed, expect, tau))
for _ in range(2):
    seed = rb(34); st = M.Stream(128); st.absorb(seed); add("uniform", 0, 128, seed, M.op_sample_uniform(st))
for mode, eta in ((1, 2), (2, 4)):
    for _ in range(2):
        seed = rb(66); st = M.Stream(256); st.absorb(seed); add(f"eta{eta}", mode, 256, seed, M.op_sample_eta(st, eta))
for mode, g in ((3, 17), (4, 19)):
    seed = rb(66); st = M.Stream(256); st.absorb(seed); add(f"gamma1_{g}", mode, 256, seed, M.op_sample_gamma1(st, g))
for ct, tau in ((32, 39), (48, 49), (64, 60)):
    seed = rb(ct); st = M.Stream(256); st.absorb(seed); add(f"ball_tau{tau}", 5, 256, seed, M.op_sample_ball(st, tau), tau)
o = ["`timescale 1ns/1ps", "module tb_pq_smp;", "reg clk=0, rst_n=0; always #5 clk=~clk;",
     "reg sh_init=0, sh_mode=0, sh_in_valid=0, sh_fin=0; reg [7:0] sh_in_byte=0; wire sh_in_ready, out_ready, sh_idle; wire [7:0] out_byte; wire out_take;",
     "shake_unit sh(clk, rst_n, sh_init, sh_mode, sh_in_valid, sh_in_byte, sh_in_ready, sh_fin, out_take, out_ready, out_byte, sh_idle);",
     "reg start=0; reg [2:0] mode=0; reg [5:0] dst=0; reg [7:0] tau=0; wire busy, done; wire [13:0] ra, wa; wire we; wire [31:0] wd, rq;",
     "pq_pm pm(.clk(clk), .we(we), .wa(wa), .wd(wd), .ra(ra), .rq(rq));",
     "pq_smp dut(clk,rst_n,start,mode,dst,tau,busy,done,out_ready,out_byte,out_take,ra,we,wa,wd,rq);",
     "integer fails=0, n=0, i, j, c0, cyc=0; always @(posedge clk) cyc<=cyc+1; reg seen=0; always @(posedge clk) if (done) seen<=1;",
     "task run(input m256, input [2:0] md, input [1023:0] seed, input integer sl, input [7:0] t, input [8191:0] exp, input [127:0] nm); begin",
     "  for (i=0;i<256;i=i+1) pm.mem[7*256+i] = 0;",
     "  @(negedge clk); sh_mode=m256; sh_init=1; @(negedge clk); sh_init=0; repeat(4) @(negedge clk);",
     "  for (j=0;j<sl;j=j+1) begin while(!sh_in_ready) @(negedge clk); sh_in_valid=1; sh_in_byte=seed[1023-8*j -: 8]; @(negedge clk); sh_in_valid=0; end",
     "  while(!sh_in_ready) @(negedge clk); sh_fin=1; @(negedge clk); sh_fin=0;",
     "  seen=0; c0=cyc; mode=md; dst=7; tau=t; start=1; @(negedge clk); start=0; wait(seen); repeat(3) @(negedge clk);",
     "  n=n+1; for (i=0;i<256;i=i+1) if (pm.mem[7*256+i] !== exp[32*i +: 32]) begin if (fails<8) $display(\"FAIL %0s idx %0d got %h exp %h\", nm, i, pm.mem[7*256+i], exp[32*i +: 32]); fails=fails+1; end",
     "  $display(\"%0s: %0d clk\", nm, cyc-c0); end endtask",
     "initial begin #30 rst_n=1; #30;"]
def lit(vals):
    v = 0
    for i, x in enumerate(vals): v |= (x & 0xFFFFFFFF) << (32 * i)
    return f"8192'h{v:02048x}"
for name, mode, bits, seed, exp, tau in cases:
    o.append(f"  run({0 if bits == 128 else 1}, {mode}, 1024'h{(seed + bytes(128 - len(seed))).hex()}, {len(seed)}, {tau}, {lit(exp)}, \"{name}\");")
o += ['  if (fails==0) $display("ALL PASS (%0d samplers)", n); else $display("FAILED (%0d)", fails);', "  $finish;", "end",
      'initial begin #900000000 $display("TIMEOUT"); $finish; end', "endmodule"]
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tb", "tb_pq_smp.v"), "w").write("\n".join(o) + "\n")
print(len(cases), "cases")
