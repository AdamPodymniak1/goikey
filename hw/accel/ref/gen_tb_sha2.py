#!/usr/bin/env python3
"""Generate tb/tb_sha2_unit.v: SHA-256 / HMAC-SHA256 / PBKDF2 / SHA-512 through sha2_unit against hashlib/hmac."""
import hashlib, hmac, random
random.seed(1234)
def rb(n): return bytes(random.randrange(256) for _ in range(n))
cases = []
for n in [0, 1, 3, 55, 56, 57, 63, 64, 65, 100, 119, 120, 128, 200]:
    m = rb(n); cases.append(("sha", b"", m, 0, 0, hashlib.sha256(m).digest()))
for n in [0, 1, 3, 111, 112, 113, 127, 128, 129, 200, 255, 256, 300]:
    m = rb(n); cases.append(("sha512", b"", m, 0, 0, hashlib.sha512(m).digest()))
for kl in [1, 20, 32, 64]:
    for ml in [0, 10, 64, 100]:
        k, m = rb(kl), rb(ml)
        cases.append(("hmac", k, m, 0, 0, hmac.new(k, m, hashlib.sha256).digest()))
for pl, sl, it, idx in [(8,16,1,1),(32,16,2,1),(32,60,5,1),(64,60,3,1),(32,64,4,2),(16,59,7,2),(20,28,1000,1),(32,16,50,2)]:
    p, s = rb(pl), rb(sl)
    dk = hashlib.pbkdf2_hmac("sha256", p, s, it, 64)
    cases.append(("pbkdf2", p, s, it, idx, dk[32*(idx-1):32*idx]))
# a SHA-256 right after SHA-512 and vice versa (mode switching)
m = rb(70); cases.append(("sha", b"", m, 0, 0, hashlib.sha256(m).digest()))
m = rb(70); cases.append(("sha512", b"", m, 0, 0, hashlib.sha512(m).digest()))

o = ["`timescale 1ns/1ps", "module tb_sha2_unit;",
"reg clk=0, rst_n=0; always #5 clk=~clk;",
"reg begin_op=0; reg [1:0] mode=0; reg [31:0] iters=0, pb_idx=0;",
"reg key_wr=0; reg [7:0] key_byte=0; reg key_done=0;",
"reg in_valid=0; reg [7:0] in_byte=0; reg msg_end=0; reg [2:0] dg_ra=0;",
"wire busy, done, overrun, in_ready; wire [63:0] dg_q;",
"sha2_unit dut(.clk(clk),.rst_n(rst_n),.begin_op(begin_op),.mode(mode),.iters(iters),.pb_idx(pb_idx),.key_wr(key_wr),.key_byte(key_byte),",
"  .key_done(key_done),.in_valid(in_valid),.in_byte(in_byte),.in_ready(in_ready),.msg_end(msg_end),.busy(busy),.done(done),.overrun(overrun),",
"  .dg_ra(dg_ra),.dg_q(dg_q));",
"integer fails=0, total_cases=0, i; reg [511:0] got; integer t0, cyc=0; always @(posedge clk) cyc<=cyc+1;",
"task feed(input [8191:0] data, input integer n);",
"  integer j; begin for (j=0;j<n;j=j+1) begin",
"    @(negedge clk); while(!in_ready) @(negedge clk); in_valid=1; in_byte=data[8191-8*j -: 8]; @(negedge clk); in_valid=0; repeat(1) @(negedge clk); end end endtask",
"task keyin(input [8191:0] data, input integer n);",
"  integer j; begin for (j=0;j<n;j=j+1) begin @(negedge clk); key_wr=1; key_byte=data[8191-8*j -: 8]; end",
"    @(negedge clk); key_wr=0; key_done=1; @(negedge clk); key_done=0; end endtask",
"task run(input [1:0] m, input [8191:0] key, input integer kn, input [8191:0] msg, input integer mn, input [31:0] it, input [31:0] ix, input [511:0] exp, input [127:0] name);",
"  begin total_cases=total_cases+1;",
"    @(negedge clk); mode=m; iters=it; begin_op=1; @(negedge clk); begin_op=0;",
"    if (m==1 || m==2) keyin(key,kn);",
"    if (m==1 || m==2) repeat(150) @(negedge clk);",
"    feed(msg,mn);",
"    @(negedge clk); while(!in_ready) @(negedge clk); pb_idx=ix; msg_end=1; t0=cyc; @(negedge clk); msg_end=0;",
"    wait(done); @(negedge clk);",
"    got = 512'd0;",
"    for (i=0;i<8;i=i+1) begin dg_ra=i; @(negedge clk); @(negedge clk);",
"      if (m==3) got[511-64*i -: 64] = dg_q; else got[511-32*i -: 32] = dg_q[31:0]; end",
"    if (got!==exp || overrun) begin fails=fails+1; $display(\"FAIL %0s kn=%0d mn=%0d it=%0d got %h exp %h ov=%b\",name,kn,mn,it,got,exp,overrun); end",
"    else if (it>=1000) $display(\"PBKDF2 %0d iters: %0d clk (%0d clk/iter)\", it, cyc-t0, (cyc-t0)/it);",
"  end endtask",
"initial begin #30 rst_n=1; #30;"]
def pad(b): return f"8192'h{(b + bytes(1024-len(b))).hex()}"
for kind, k, m, it, ix, exp in cases:
    mode = {"sha": 0, "hmac": 1, "pbkdf2": 2, "sha512": 3}[kind]
    e = exp + bytes(64 - len(exp))
    o.append(f"  run({mode}, {pad(k)}, {len(k)}, {pad(m)}, {len(m)}, {it}, {ix}, 512'h{e.hex()}, \"{kind}\");")
o += ['  if (fails==0) $display("ALL PASS (%0d cases)", total_cases); else $display("FAILED %0d of %0d", fails, total_cases);',
      '  $finish;', 'end', 'initial begin #400000000 $display("TIMEOUT"); $finish; end', 'endmodule']
open("tb/tb_sha2_unit.v", "w").write("\n".join(o) + "\n")
print(len(cases), "cases")
