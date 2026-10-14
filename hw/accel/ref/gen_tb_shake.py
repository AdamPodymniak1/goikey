#!/usr/bin/env python3
import hashlib, random
random.seed(21)
def rb(n): return bytes(random.randrange(256) for _ in range(n))
cases=[]
for mode,fn in ((0,hashlib.shake_128),(1,hashlib.shake_256)):
    for inl in (0,1,7,8,9,100,135,136,137,167,168,169,300):
        for outl in (1,32,200,500):
            if random.random()<0.5 or outl==32:
                d=rb(inl); cases.append((mode,d,fn(d).digest(outl),outl))
o=["`timescale 1ns/1ps","module tb_shake;","reg clk=0, rst_n=0; always #5 clk=~clk;",
"reg init=0, mode=0, in_valid=0, finalize=0, out_take=0; reg [7:0] in_byte=0; wire in_ready, out_ready, idle; wire [7:0] out_byte;",
"shake_unit dut(clk,rst_n,init,mode,in_valid,in_byte,in_ready,finalize,out_take,out_ready,out_byte,idle);",
"integer fails=0, n=0, j; reg [4095:0] got; reg [7:0] b;",
"task run(input m, input [4095:0] d, input integer il, input integer ol, input [4095:0] exp); begin",
"  @(negedge clk); mode=m; init=1; @(negedge clk); init=0; @(negedge clk);",
"  for (j=0;j<il;j=j+1) begin while(!in_ready) @(negedge clk); in_valid=1; in_byte=d[4095-8*j -: 8]; @(negedge clk); in_valid=0; end",
"  while(!in_ready) @(negedge clk); finalize=1; @(negedge clk); finalize=0;",
"  for (j=0;j<ol;j=j+1) begin while(!out_ready) @(negedge clk); got[4095-8*j -: 8]=out_byte; out_take=1; @(negedge clk); out_take=0; end",
"  n=n+1; if ((got >> (4096-8*ol)) !== (exp >> (4096-8*ol))) begin fails=fails+1; $display(\"FAIL mode=%0d il=%0d ol=%0d\",m,il,ol); end end endtask",
"initial begin #30 rst_n=1; #30;"]
for m,d,e,ol in cases:
    o.append(f"  run({m},4096'h{(d+bytes(512-len(d))).hex()},{len(d)},{ol},4096'h{(e+bytes(512-len(e))).hex()});")
o+=['  if (fails==0) $display("ALL PASS (%0d cases)", n); else $display("FAILED %0d", fails);',"  $finish;","end","initial begin #500000000 $display(\"TIMEOUT\"); $finish; end","endmodule"]
open("tb/tb_shake.v","w").write("\n".join(o)+"\n")
print(len(cases),"cases")
