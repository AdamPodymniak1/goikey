#!/usr/bin/env python3
"""Testbench for keccak_core: random state, one permutation, compare all 25 lanes with a Python Keccak-f[1600]."""
import random
M = (1 << 64) - 1
def rotl(x, n): return ((x << n) | (x >> (64 - n))) & M if n else x
RC = []; R = 1
for i in range(24):
    rc = 0
    for j in range(7):
        if R & 1: rc ^= 1 << ((1 << j) - 1)
        R = ((R << 1) ^ (0x171 if R & 0x80 else 0)) & 0xff
    RC.append(rc)
ROT = [[0] * 5 for _ in range(5)]; x, y = 1, 0
for t in range(24):
    ROT[x][y] = ((t + 1) * (t + 2) // 2) % 64; x, y = y, (2 * x + 3 * y) % 5
def keccak_f(a):                       # a[x+5y]
    a = list(a)
    for rnd in range(24):
        c = [a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] for x in range(5)]
        d = [c[(x - 1) % 5] ^ rotl(c[(x + 1) % 5], 1) for x in range(5)]
        a = [a[i] ^ d[i % 5] for i in range(25)]
        b = [0] * 25
        for x in range(5):
            for y in range(5): b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(a[x + 5 * y], ROT[x][y])
        a = [b[x + 5 * y] ^ (~b[(x + 1) % 5 + 5 * y] & b[(x + 2) % 5 + 5 * y]) & M for y in range(5) for x in range(5)]
        a[0] ^= RC[rnd]
    return a
random.seed(3)
st = [random.getrandbits(64) for _ in range(25)]
out = keccak_f(st); out2 = keccak_f(out)
o = ["`timescale 1ns/1ps", "module tb_keccak;", "reg clk=0, rst_n=0; always #5 clk=~clk;",
     "reg clear=0, xor_en=0, perm=0; reg [4:0] xor_lane=0, rd_lane=0; reg [63:0] xor_val=0; wire busy, done; wire [63:0] rd_val;",
     "keccak_core dut(clk,rst_n,clear,xor_en,xor_lane,xor_val,perm,busy,done,rd_lane,rd_val);",
     "integer fails=0, i, c0, cyc=0; always @(posedge clk) cyc<=cyc+1; reg seen=0; always @(posedge clk) if (done) seen<=1;",
     "task setl(input [4:0] l, input [63:0] v); begin @(negedge clk); xor_lane=l; xor_val=v; xor_en=1; @(negedge clk); xor_en=0; while (busy) @(negedge clk); end endtask",
     "task chk(input [4:0] l, input [63:0] v); begin rd_lane=l; repeat(4) @(negedge clk); if (rd_val !== v) begin fails=fails+1; $display(\"FAIL lane %0d got %h exp %h\", l, rd_val, v); end end endtask",
     "task doperm; begin seen=0; c0=cyc; @(negedge clk); perm=1; @(negedge clk); perm=0; wait(seen); @(negedge clk); end endtask",
     "initial begin #30 rst_n=1; #30; @(negedge clk); clear=1; @(negedge clk); clear=0; while (busy) @(negedge clk);"]
for i, v in enumerate(st): o.append(f"  setl({i}, 64'h{v:016x});")
o.append("  doperm; $display(\"perm clk = %0d\", cyc-c0);")
for i, v in enumerate(out): o.append(f"  chk({i}, 64'h{v:016x});")
o.append("  doperm;")
for i, v in enumerate(out2): o.append(f"  chk({i}, 64'h{v:016x});")
o += ['  if (fails==0) $display("ALL PASS"); else $display("FAILED %0d", fails);', "  $finish;", "end",
      'initial begin #50000000 $display("TIMEOUT"); $finish; end', "endmodule"]
open("tb/tb_keccak.v", "w").write("\n".join(o) + "\n")
