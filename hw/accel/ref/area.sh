#!/usr/bin/env bash
# Per-module LUT/FF estimate: ref/area.sh <top> [extra files...]   (run in nix-shell, from hw/accel)
top=$1; shift
yosys -q -p "read_verilog -I rtl rtl/*.v ../tro/root_of_trust.v; synth_gowin -top $top; tee -o /dev/stdout stat" 2>/dev/null | awk -v t=$top '/LUT[1-4]|MUX2_LUT|ALU|DFF|BSRAM/ {n[$2]+=$1} END{lut=n["LUT1"]+n["LUT2"]+n["LUT3"]+n["LUT4"]+n["MUX2_LUT5"]*0.5+n["MUX2_LUT6"]*0.5; ff=0; for(k in n) if(k ~ /DFF/) ff+=n[k]; printf "%-14s LUT~%6d  ALU %5d  FF %6d\n", t, lut, n["ALU"], ff}'
