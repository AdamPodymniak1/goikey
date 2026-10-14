#!/usr/bin/env bash
# Quick synthesis-only area estimate: ref/area_top.sh <HAS_AES> <HAS_ECC>   (run in nix-shell, from hw/accel)
yosys -q -p "verilog_defines -DUID_VAL=128'h0 -DMASTER_VAL=256'h0; read_verilog -Irtl $(ls rtl/*.v | tr '\n' ' ') ../tro/root_of_trust.v; chparam -set HAS_AES $1 -set HAS_ECC $2 accel_top; synth_gowin -top accel_top; tee -o /dev/stdout stat" 2>&1 \
 | awk -v a=$1 -v e=$2 '/^ +[0-9]+ +[A-Z]/ {n[$2]+=$1} END{l=n["LUT1"]+n["LUT2"]+n["LUT3"]+n["LUT4"]; ff=0; for(k in n) if (k ~ /DFF/) ff+=n[k]; printf "HAS_AES=%s HAS_ECC=%s: LUT %d + MUX2_LUT5 %d(~0) + ALU %d  = ~%d cells; FF %d; BSRAM %d\n", a, e, l, n["MUX2_LUT5"], n["ALU"], l+n["ALU"], ff, n["SP"]+n["SDP"]+n["DP"]+n["SDPB"]+n["DPB"]}'
