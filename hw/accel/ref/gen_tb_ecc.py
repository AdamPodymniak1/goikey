#!/usr/bin/env python3
"""Generate tb/tb_ecc_seq.v: run microprograms in RTL, compare registers with the Python interpreter."""
import random, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import ecc_asm as E
from ecc_model import *
random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 17)
A = E.build(); code = A.link(); R_ = A.regs
cases = []   # (name, entry, {reg: value}, [out regs], expect_flag)
def add(name, entry, inputs, outs):
    regs, flag, steps = E.run(code, A.entries[entry], {R_[k]: v for k, v in inputs.items()})
    cases.append((name, A.entries[entry], {R_[k]: v for k, v in inputs.items()}, {R_[o]: regs[R_[o]] for o in outs}, flag, steps))
sel = sys.argv[1].split(",") if len(sys.argv) > 1 else ["base"]
import hashlib
d = random.randrange(1, P256_N); k = random.randrange(1, P256_N)
z = int.from_bytes(hashlib.sha256(b"rtl test").digest(), "big")
if "base" in sel: add("p256_base", "P256_BASEMUL", {"K": random.randrange(1, P256_N)}, ["OX", "OY"])
if "oncurve" in sel:
    add("oncurve_ok", "P256_ONCURVE", {"PX": P256_GX, "PY": P256_GY}, [])
    add("oncurve_bad", "P256_ONCURVE", {"PX": P256_GX, "PY": P256_GY ^ 1}, [])
if "ecdh" in sel:
    qx, qy = p256_scalar_mul(random.randrange(1, P256_N), P256_GX, P256_GY)
    add("ecdh", "P256_ECDH", {"D": d, "QX": qx, "QY": qy}, ["OX"])
    add("ecdh_badpoint", "P256_ECDH", {"D": d, "QX": qx, "QY": qy ^ 2}, [])
if "sign" in sel:
    add("sign", "P256_SIGN", {"D": d, "Z": z, "K": k}, ["RR", "S"])
    add("sign_k0", "P256_SIGN", {"D": d, "Z": z, "K": 0}, [])
if "verify" in sel:
    regs, fl, _ = E.run(code, A.entries["P256_SIGN"], {R_["D"]: d, R_["Z"]: z, R_["K"]: k})
    qx, qy = p256_scalar_mul(d, P256_GX, P256_GY)
    add("verify_ok", "P256_VERIFY", {"Z": z, "RR": regs[R_["RR"]], "S": regs[R_["S"]], "QX": qx, "QY": qy}, [])
    add("verify_bad", "P256_VERIFY", {"Z": z ^ 4, "RR": regs[R_["RR"]], "S": regs[R_["S"]], "QX": qx, "QY": qy}, [])
if "ed" in sel:
    a_ = random.getrandbits(255) | (1 << 254)
    add("ed_base", "ED_BASEMUL", {"K": a_}, ["OX", "OY"])
    add("ed_reduce", "ED_REDUCE512", {"H0": random.getrandbits(256), "H1": random.getrandbits(256)}, ["RR"])
    add("ed_sign_s", "ED_SIGN_S", {"RR": random.randrange(ED_L), "KK": random.randrange(ED_L), "AA": a_}, ["S"])
o = ["`timescale 1ns/1ps", "module tb_ecc_seq;", "reg clk=0, rst_n=0; always #5 clk=~clk;",
     "reg h_we=0; reg [6:0] h_wreg=0; reg [3:0] h_wword=0; reg [15:0] h_wdata=0; reg [6:0] h_rreg=0; reg [3:0] h_rword=0;",
     "wire [15:0] h_q; reg h_go=0; reg [10:0] h_pc=0; wire h_busy, h_done, h_flag;",
     "wire [12:0] rx_a, tx_wa; wire tx_we; wire [7:0] tx_wd, f_status; wire [15:0] f_len; wire h5_begin, h5_in_valid, h5_end; wire [7:0] h5_in_byte;",
     "ecc_seq dut(.clk(clk),.rst_n(rst_n),.h_we(h_we),.h_wreg(h_wreg),.h_wword(h_wword),.h_wdata(h_wdata),.h_rreg(h_rreg),.h_rword(h_rword),.h_q(h_q),.h_go(h_go),.h_pc(h_pc),.h_busy(h_busy),.h_done(h_done),.h_flag(h_flag),",
     "  .plen(16'd0),.rx_a(rx_a),.rx_q(8'd0),.tx_we(tx_we),.tx_wa(tx_wa),.tx_wd(tx_wd),.f_status(f_status),.f_len(f_len),.trng_valid(1'b0),.trng_data(32'd0),",
     "  .h5_begin(h5_begin),.h5_in_valid(h5_in_valid),.h5_in_byte(h5_in_byte),.h5_in_ready(1'b1),.h5_end(h5_end),.h5_done(1'b0),.h5_ra(),.h5_q(64'd0));",
     "integer fails=0, w, c0, cyc=0; reg [255:0] got; reg seen=0; always @(posedge clk) cyc<=cyc+1; always @(posedge clk) if (h_done) seen<=1;",
     "task putreg(input [6:0] r, input [255:0] v); begin for (w=0; w<16; w=w+1) begin @(negedge clk); h_we=1; h_wreg=r; h_wword=w; h_wdata=v[16*w +: 16]; end @(negedge clk); h_we=0; end endtask",
     "task getreg(input [6:0] r); begin for (w=0; w<16; w=w+1) begin h_rreg=r; h_rword=w; @(negedge clk); @(negedge clk); got[16*w +: 16]=h_q; end end endtask",
     "task go(input [10:0] pc); begin seen=0; c0=cyc; @(negedge clk); h_pc=pc; h_go=1; @(negedge clk); h_go=0; wait(seen); @(negedge clk); end endtask",
     "initial begin #30 rst_n=1; #30;"]
for name, entry, ins, outs, flag, steps in cases:
    for r, v in ins.items(): o.append(f"  putreg({r}, 256'h{v:064x});")
    o.append(f"  go({entry}); $display(\"{name}: %0d clk, flag=%b (expect {flag}); {steps} instructions\", cyc-c0, h_flag);")
    o.append(f"  if (h_flag !== 1'b{flag}) begin fails=fails+1; $display(\"FAIL {name}: flag\"); end")
    for r, v in outs.items():
        o.append(f"  getreg({r}); if (got !== 256'h{v:064x}) begin fails=fails+1; $display(\"FAIL {name}: r{r} got %h exp {v:064x}\", got); end else $display(\"ok {name}: r{r}\");")
o += ['  if (fails==0) $display("ALL PASS"); else $display("FAILED %0d", fails);', "  $finish;", "end",
      "initial begin #2000000000 $display(\"TIMEOUT\"); $finish; end", "endmodule"]
open(os.path.join(os.path.dirname(__file__), "..", "tb", "tb_ecc_seq.v"), "w").write("\n".join(o) + "\n")
print(len(cases), "cases")
