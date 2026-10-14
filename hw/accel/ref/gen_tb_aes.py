#!/usr/bin/env python3
"""Generate tb/tb_aes_core.v from the `cryptography` package (AES-256 ECB)."""
import random
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
random.seed(7)
def rb(n): return bytes(random.randrange(256) for _ in range(n))
vec=[(bytes.fromhex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4"),
      bytes.fromhex("6bc1bee22e409f96e93d7e117393172a"))]   # NIST SP800-38A F.1.5
for _ in range(20): vec.append((rb(32), rb(16)))
o=["`timescale 1ns/1ps","module tb_aes_core;",
"reg clk=0, rst_n=0; always #5 clk=~clk;",
"reg key_we=0; reg [2:0] key_wi=0; reg [31:0] key_wd=0; reg key_go=0; wire key_ready;",
"reg blk_start=0, dec=0, sh_en=0; reg [7:0] sh_in=0; wire blk_done, busy; wire [7:0] sh_out; wire [127:0] state;",
"aes_core dut(.clk(clk),.rst_n(rst_n),.key_we(key_we),.key_wi(key_wi),.key_wd(key_wd),.key_go(key_go),.key_ready(key_ready),",
"  .blk_start(blk_start),.dec(dec),.blk_done(blk_done),.sh_en(sh_en),.sh_in(sh_in),.sh_out(sh_out),.state(state),.busy(busy));",
"integer fails=0, n=0, j, c0, cyc=0; reg [127:0] got; always @(posedge clk) cyc<=cyc+1;",
"task setkey(input [255:0] k); begin",
"  for (j=0;j<8;j=j+1) begin @(negedge clk); key_we=1; key_wi=j; key_wd=k[255-32*j -: 32]; end",
"  @(negedge clk); key_we=0; @(negedge clk); key_go=1; c0=cyc; @(negedge clk); key_go=0; wait(key_ready); @(negedge clk);",
"  if (n==0) $display(\"key expansion: %0d clk\", cyc-c0); end endtask",
"task blk(input d, input [127:0] i, input [127:0] exp); begin",
"  for (j=0;j<16;j=j+1) begin @(negedge clk); sh_en=1; sh_in=i[127-8*j -: 8]; end @(negedge clk); sh_en=0;",
"  @(negedge clk); dec=d; blk_start=1; c0=cyc; @(negedge clk); blk_start=0; wait(blk_done); @(negedge clk);",
"  if (n==0) $display(\"block: %0d clk\", cyc-c0);",
"  for (j=0;j<16;j=j+1) begin got[127-8*j -: 8]=sh_out; @(negedge clk); sh_en=1; sh_in=8'h00; @(negedge clk); sh_en=0; end",
"  if (got!==exp) begin fails=fails+1; $display(\"FAIL dec=%0b in=%h got %h exp %h\",d,i,got,exp); end n=n+1; end endtask",
"initial begin #30 rst_n=1; #30;"]
for k,p in vec:
    c=Cipher(algorithms.AES(k),modes.ECB()).encryptor().update(p)
    o.append(f"  setkey(256'h{k.hex()});")
    o.append(f"  blk(0,128'h{p.hex()},128'h{c.hex()}); blk(1,128'h{c.hex()},128'h{p.hex()});")
o+=['  if (fails==0) $display("ALL PASS (%0d blocks)", n); else $display("FAILED %0d", fails);','  $finish;','end','initial begin #50000000 $display("TIMEOUT"); $finish; end','endmodule']
open("tb/tb_aes_core.v","w").write("\n".join(o)+"\n")
