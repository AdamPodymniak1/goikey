#!/usr/bin/env python3
"""tb_pq_pack.v: pack/unpack/PKH against pq_model (bytes in TX/SC spaces, plus absorb into a real shake_unit)."""
import hashlib, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pq_model as M
random.seed(4)
Q = M.Q
def rp(lo, hi): return [random.randint(lo, hi) for _ in range(256)]
cases = []   # (name, op, slot, space, base, params(eta4,g1sel,g2sel,omega,hidx), poly_in, expect_bytes or None, expect_poly, ...)
def add(**k): cases.append(k)
t1 = rp(0, 1023); add(name="pkt1", op=0, slot=3, space=2, base=100, par=(0, 0, 0, 80, 0), poly=t1, ebytes=M.pk_t1(t1))
t0 = rp(-4095, 4096); add(name="pkt0", op=1, slot=3, space=1, base=7, par=(0, 0, 0, 80, 0), poly=t0, ebytes=M.pk_t0(t0))
for eta4, eta in ((0, 2), (1, 4)):
    e = rp(-eta, eta); add(name=f"pketa{eta}", op=2, slot=3, space=2, base=0, par=(eta4, 0, 0, 80, 0), poly=e, ebytes=M.pk_eta(e, eta))
for g1sel, g in ((0, 17), (1, 19)):
    z = rp(-(1 << g) + 1, 1 << g); add(name=f"pkz{g}", op=3, slot=3, space=1, base=300, par=(0, g1sel, 0, 80, 0), poly=z, ebytes=M.pk_z(z, g))
for g2sel, d in ((0, 88), (1, 32)):
    w = rp(0, 43 if d == 88 else 15); add(name=f"pkw1_{d}", op=4, slot=3, space=2, base=40, par=(0, 0, g2sel, 80, 0), poly=w, ebytes=M.pk_w1(w, d))
w = rp(0, 15); add(name="pkw1_shake", op=4, slot=3, space=3, base=0, par=(0, 0, 1, 80, 0), poly=w, shake=M.pk_w1(w, 32))
for eta4, eta in ((0, 2), (1, 4)):
    e = rp(-eta, eta); b = M.pk_eta(e, eta); add(name=f"upketa{eta}", op=5, slot=5, space=2, base=64, par=(eta4, 0, 0, 80, 0), inbytes=(2, 64, b), epoly=e)
t = rp(-4095, 4096); add(name="upkt0", op=6, slot=5, space=0, base=9, par=(0, 0, 0, 80, 0), inbytes=(0, 9, M.pk_t0(t)), epoly=t)
h = [0] * 256
for j in random.sample(range(256), 7): h[j] = 1
add(name="pkh", op=7, slot=3, space=1, base=500, par=(0, 0, 0, 20, 2), poly=h, hint=(h, 20, 2))
o = ["`timescale 1ns/1ps", "module tb_pq_pack;", "reg clk=0, rst_n=0; always #5 clk=~clk;",
     "reg start=0; reg [3:0] op=0; reg [5:0] slot=0; reg [1:0] space=0; reg [12:0] base=0; reg eta4=0,g1sel=0,g2sel=0; reg [7:0] omega=80; reg [5:0] hidx=0; reg hk_clr=0;",
     "wire busy, done, hk_over, bw_en, sh_in_valid; wire [13:0] ra, wa; wire we; wire [31:0] wd, rq; wire [1:0] bw_space, br_space; wire [12:0] bw_addr, br_addr; wire [7:0] bw_data, sh_in_byte; reg [7:0] br_data;",
     "pq_pm pm(.clk(clk), .we(we), .wa(wa), .wd(wd), .ra(ra), .rq(rq));",
     "reg [7:0] bm [0:3*8192-1]; always @(posedge clk) begin if (bw_en) bm[bw_space*8192+bw_addr] <= bw_data; br_data <= bm[br_space*8192+br_addr]; end",
     "wire sh_ready; reg sh_init=0, sh_fin=0, sh_take=0; wire sh_oready; wire [7:0] sh_obyte; wire sh_idle;",
     "shake_unit sh(clk, rst_n, sh_init, 1'b1, sh_in_valid, sh_in_byte, sh_ready, sh_fin, sh_take, sh_oready, sh_obyte, sh_idle);",
     "pq_pack dut(clk,rst_n,start,op,slot,space,base,eta4,g1sel,g2sel,omega,hidx,hk_clr,busy,done,hk_over,ra,we,wa,wd,rq,bw_en,bw_space,bw_addr,bw_data,br_space,br_addr,br_data,sh_in_valid,sh_in_byte,sh_ready);",
     "reg [8191:0] expv; integer fails=0, n=0, i, j, c0, cyc=0; always @(posedge clk) cyc<=cyc+1; reg seen=0; always @(posedge clk) if (done) seen<=1;",
     "task go(input [3:0] o, input [5:0] s, input [1:0] sp, input [12:0] b, input e4, input g1, input g2, input [7:0] om, input [5:0] hx); begin",
     "  seen=0; c0=cyc; @(negedge clk); op=o; slot=s; space=sp; base=b; eta4=e4; g1sel=g1; g2sel=g2; omega=om; hidx=hx; start=1; @(negedge clk); start=0; wait(seen); repeat(4) @(negedge clk); end endtask",
     "initial begin #30 rst_n=1; #30; hk_clr=1; @(negedge clk); hk_clr=0;"]
def plit(pl):
    v = 0
    for i, x in enumerate(pl): v |= (x & 0xFFFFFFFF) << (32 * i)
    return f"8192'h{v:02048x}"
for c in cases:
    name, op = c["name"], c["op"]; e4, g1, g2, om, hx = c["par"]
    if "poly" in c:
        o.append(f"  expv = {plit(c['poly'])};")
        o.append(f"  for (i=0;i<256;i=i+1) pm.mem[{c['slot']}*256+i] = expv[32*i +: 32];")
    if "inbytes" in c:
        sp, off, data = c["inbytes"]
        for k, b in enumerate(data): o.append(f"  bm[{sp}*8192+{off + k}] = 8'h{b:02x};")
    if "shake" in c: o.append("  sh_init=1; @(negedge clk); sh_init=0; repeat(6) @(negedge clk);")
    o.append(f"  go({op},{c['slot']},{c['space']},{c['base']},{e4},{g1},{g2},{om},{hx}); $display(\"{name}: %0d clk\", cyc-c0); n=n+1;")
    if "ebytes" in c:
        for k, b in enumerate(c["ebytes"]): o.append(f"  if (bm[{c['space']}*8192+{c['base'] + k}] !== 8'h{b:02x}) begin fails=fails+1; if (fails<6) $display(\"FAIL {name} byte {k}\"); end")
    if "epoly" in c:
        o.append(f"  expv = {plit(c['epoly'])};")
        o.append(f"  for (i=0;i<256;i=i+1) if (pm.mem[{c['slot']}*256+i] !== expv[32*i +: 32]) begin fails=fails+1; if (fails<6) $display(\"FAIL {name} coeff %0d got %h exp %h\", i, pm.mem[{c['slot']}*256+i], expv[32*i +: 32]); end")
    if "shake" in c:
        d = hashlib.shake_256(c["shake"]).digest(32)
        o.append("  while(!sh_ready) @(negedge clk); sh_fin=1; @(negedge clk); sh_fin=0;")
        for k in range(32):
            o.append(f"  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h{d[k]:02x}) begin fails=fails+1; $display(\"FAIL shake digest byte {k}\"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);")
    if "hint" in c:
        h, om, hxx = c["hint"]; pos = [j for j in range(256) if h[j]]
        for k, p in enumerate(pos): o.append(f"  if (bm[{c['space']}*8192+{c['base'] + k}] !== 8'h{p:02x}) begin fails=fails+1; $display(\"FAIL pkh pos {k}\"); end")
        o.append(f"  if (bm[{c['space']}*8192+{c['base'] + om + hxx}] !== 8'd{len(pos)}) begin fails=fails+1; $display(\"FAIL pkh count\"); end")
o += ['  if (fails==0) $display("ALL PASS (%0d ops)", n); else $display("FAILED (%0d)", fails);', "  $finish;", "end",
      'initial begin #400000000 $display("TIMEOUT"); $finish; end', "endmodule"]
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tb", "tb_pq_pack.v"), "w").write("\n".join(o) + "\n")
print(len(cases), "cases")
