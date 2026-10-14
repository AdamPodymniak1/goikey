#!/usr/bin/env python3
"""Generate tb/tb_pq_poly.v: every pq_poly operation on random data, compared with pq_model."""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pq_model as M
random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 5)
Q = M.Q
def rnd_poly(lo, hi): return [random.randint(lo, hi) for _ in range(256)]
cases = []   # (name, op, (a,b,c), g2sel, bound, inputs{slot:poly}, expect{slot:poly}, flag, hint_cnt)
def add(name, op, abc, ins, outs, g2sel=0, bound=0, flag=0, hc=0): cases.append((name, op, abc, g2sel, bound, ins, outs, flag, hc))
p = rnd_poly(-Q, Q)
add("ntt", 0, (1, 0, 0), {1: p}, {1: M.op_ntt(p)})
p = rnd_poly(-2 * Q, 2 * Q); add("ntt_wide", 0, (2, 0, 0), {2: p}, {2: M.op_ntt(p)})
p = rnd_poly(-Q, Q); add("intt", 1, (3, 0, 0), {3: p}, {3: M.op_intt(p)})
a, b = rnd_poly(-Q, Q), rnd_poly(-Q, Q); add("pmul", 2, (4, 5, 6), {5: a, 6: b}, {4: M.op_pmul(a, b)})
acc = rnd_poly(-Q, Q); add("pmula", 3, (7, 5, 6), {7: acc, 5: a, 6: b}, {7: M.op_add(acc, M.op_pmul(a, b))})
add("padd", 4, (8, 5, 6), {5: a, 6: b}, {8: M.op_add(a, b)}); add("psub", 5, (9, 5, 6), {5: a, 6: b}, {9: M.op_sub(a, b)})
big = rnd_poly(-(1 << 30), 1 << 30); big[0] = (1 << 31) - 1 - (1 << 22); big[1] = -(1 << 31) + 5
add("pred", 6, (10, 0, 0), {10: big}, {10: M.op_reduce(big)})
cq = rnd_poly(-Q, Q); add("pcaddq", 7, (11, 0, 0), {11: cq}, {11: M.op_caddq(cq)})
add("pclr", 8, (12, 0, 0), {12: cq}, {12: [0] * 256})
add("pcopy", 9, (13, 5, 0), {5: a}, {13: list(a)})
t = rnd_poly(0, Q - 1); t[0] = 0; t[1] = Q - 1; hi, lo = M.op_power2round(t); add("p2r", 10, (14, 15, 16), {16: t}, {14: hi, 15: lo})
for g in (0, 1):
    div = 88 if g == 0 else 32
    w = rnd_poly(0, Q - 1); w[0] = 0; w[1] = Q - 1; w[2] = (Q - 1) // div * 2 * 3 + 5
    w1, w0 = M.op_decompose(w, div); add(f"pdec{div}", 11, (17, 18, 19), {19: w}, {17: w1, 18: w0}, g2sel=g)
    g2 = (Q - 1) // div
    x0 = rnd_poly(-g2 - 5, g2 + 5); x0[0] = -g2; x0[1] = g2; x0[2] = g2 + 1; x1 = rnd_poly(0, 15); x1[0] = 1; x1[1] = 0
    h, cnt = M.op_make_hint(x0, x1, div); add(f"mkhint{div}", 12, (20, 21, 22), {21: x0, 22: x1}, {20: h}, g2sel=g, hc=cnt)
n1 = rnd_poly(-100000, 100000); add("chkn_ok", 13, (23, 0, 0), {23: n1}, {}, bound=200000, flag=0)
n2 = list(n1); n2[200] = -250000; add("chkn_neg", 13, (24, 0, 0), {24: n2}, {}, bound=200000, flag=1)
n3 = list(n1); n3[255] = 200000; add("chkn_edge", 13, (25, 0, 0), {25: n3}, {}, bound=200000, flag=1)
add("chkn_bigbound", 13, (26, 0, 0), {26: n1}, {}, bound=2000000, flag=1)
o = ["`timescale 1ns/1ps", "module tb_pq_poly;", "reg clk=0, rst_n=0; always #5 clk=~clk;",
     "reg start=0; reg [4:0] op=0; reg [5:0] sa=0,sb=0,sc=0; reg g2sel=0; reg [31:0] bound=0;",
     "wire busy, done, flag_or; wire [8:0] hint_cnt; wire [13:0] ra, wa; wire we; wire [31:0] wd, rq;",
     "pq_pm pm(.clk(clk), .we(we), .wa(wa), .wd(wd), .ra(ra), .rq(rq));",
     "pq_poly dut(clk,rst_n,start,op,sa,sb,sc,g2sel,bound,busy,done,flag_or,hint_cnt,ra,we,wa,wd,rq);",
     "integer fails=0, n=0, i, c0, cyc=0; always @(posedge clk) cyc<=cyc+1; reg seen=0; always @(posedge clk) if (done) seen<=1;",
     "task setp(input [5:0] s, input [8191:0] v); begin for (i=0;i<256;i=i+1) pm.mem[s*256+i] = v[32*i +: 32]; end endtask",
     "task chk(input [5:0] s, input [8191:0] v, input [255:0] nm); begin for (i=0;i<256;i=i+1) if (pm.mem[s*256+i] !== v[32*i +: 32]) begin",
     "   if (fails < 10) $display(\"FAIL slot %0d idx %0d got %h exp %h\", s, i, pm.mem[s*256+i], v[32*i +: 32]); fails=fails+1; end end endtask",
     "task run(input [4:0] o, input [5:0] a, input [5:0] b, input [5:0] c, input g, input [31:0] bd); begin",
     "  seen=0; c0=cyc; @(negedge clk); op=o; sa=a; sb=b; sc=c; g2sel=g; bound=bd; start=1; @(negedge clk); start=0; wait(seen); repeat(3) @(negedge clk); end endtask",
     "initial begin #30 rst_n=1; #30;"]
def poly_lit(pl):
    v = 0
    for i, x in enumerate(pl): v |= (x & 0xFFFFFFFF) << (32 * i)
    return f"8192'h{v:02048x}"
for name, op, (a, b, c), g2sel, bound, ins, outs, flag, hc in cases:
    for s, pl in ins.items(): o.append(f"  setp({s}, {poly_lit(pl)});")
    o.append(f"  run({op},{a},{b},{c},{g2sel},{bound}); $display(\"{name}: %0d clk\", cyc-c0);")
    for s, pl in outs.items(): o.append(f"  chk({s}, {poly_lit(pl)}, \"{name}\");")
    if op == 13: o.append(f"  if (flag_or !== 1'b{flag}) begin fails=fails+1; $display(\"FAIL {name}: flag %b exp {flag}\", flag_or); end")
    if op == 12: o.append(f"  if (hint_cnt !== 9'd{hc}) begin fails=fails+1; $display(\"FAIL {name}: hints %0d exp {hc}\", hint_cnt); end")
    o.append("  n=n+1;")
o += ['  if (fails==0) $display("ALL PASS (%0d ops)", n); else $display("FAILED (%0d mismatches)", fails);', "  $finish;", "end",
      'initial begin #800000000 $display("TIMEOUT"); $finish; end', "endmodule"]
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tb", "tb_pq_poly.v"), "w").write("\n".join(o) + "\n")
print(len(cases), "cases")
