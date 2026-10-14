`timescale 1ns/1ps
module tb_pq_pack;
reg clk=0, rst_n=0; always #5 clk=~clk;
reg start=0; reg [3:0] op=0; reg [5:0] slot=0; reg [1:0] space=0; reg [12:0] base=0; reg eta4=0,g1sel=0,g2sel=0; reg [7:0] omega=80; reg [5:0] hidx=0; reg hk_clr=0;
wire busy, done, hk_over, bw_en, sh_in_valid; wire [13:0] ra, wa; wire we; wire [31:0] wd, rq; wire [1:0] bw_space, br_space; wire [12:0] bw_addr, br_addr; wire [7:0] bw_data, sh_in_byte; reg [7:0] br_data;
pq_pm pm(.clk(clk), .we(we), .wa(wa), .wd(wd), .ra(ra), .rq(rq));
reg [7:0] bm [0:3*8192-1]; always @(posedge clk) begin if (bw_en) bm[bw_space*8192+bw_addr] <= bw_data; br_data <= bm[br_space*8192+br_addr]; end
wire sh_ready; reg sh_init=0, sh_fin=0, sh_take=0; wire sh_oready; wire [7:0] sh_obyte; wire sh_idle;
shake_unit sh(clk, rst_n, sh_init, 1'b1, sh_in_valid, sh_in_byte, sh_ready, sh_fin, sh_take, sh_oready, sh_obyte, sh_idle);
pq_pack dut(clk,rst_n,start,op,slot,space,base,eta4,g1sel,g2sel,omega,hidx,hk_clr,busy,done,hk_over,ra,we,wa,wd,rq,bw_en,bw_space,bw_addr,bw_data,br_space,br_addr,br_data,sh_in_valid,sh_in_byte,sh_ready);
reg [8191:0] expv; integer fails=0, n=0, i, j, c0, cyc=0; always @(posedge clk) cyc<=cyc+1; reg seen=0; always @(posedge clk) if (done) seen<=1;
task go(input [3:0] o, input [5:0] s, input [1:0] sp, input [12:0] b, input e4, input g1, input g2, input [7:0] om, input [5:0] hx); begin
  seen=0; c0=cyc; @(negedge clk); op=o; slot=s; space=sp; base=b; eta4=e4; g1sel=g1; g2sel=g2; omega=om; hidx=hx; start=1; @(negedge clk); start=0; wait(seen); repeat(4) @(negedge clk); end endtask
initial begin #30 rst_n=1; #30; hk_clr=1; @(negedge clk); hk_clr=0;
  expv = 8192'h000000f70000027e0000000b000001590000000900000211000002b5000003f40000029c00000131000001690000014d000002f900000156000000f200000361000003d40000026b00000191000000890000038d0000035300000378000002ed000000ea0000009e000000c200000333000003e4000001de0000031b0000027d000001a40000030c000003a1000000ae00000099000002c60000026000000015000000a3000002e6000000540000011c0000020e000003e9000000e700000046000000a10000003600000384000003c5000002a50000014b0000019d0000006d000001c70000030c0000032a000000ed0000020f0000001a00000141000001b000000006000001bf0000031f0000033a000003c7000003b7000001560000007b0000022700000105000003280000005b000001870000023d00000098000003f800000323000002b500000225000001b80000035c00000285000003c50000025e000002b100000152000001af00000370000000be00000319000003f40000005200000339000000ef000002840000006900000299000001220000021700000356000001da000001aa000001f000000206000002080000004b0000004000000180000003fd000001b90000036c000001fd0000038c0000035e000001c00000004b000003ef0000034800000382000001ef0000019d000003d20000019a0000034600000257000000fa0000004800000292000001fe000003ec000000530000013200000159000000710000007f00000079000000e8000001a900000364000001a800000383000000c600000252000002e6000002eb0000015b000003a30000005b000002e800000013000002a6000001450000030d0000020000000117000002560000038d00000188000002580000009f0000034800000139000002920000024f00000295000000250000029d00000249000000a9000002db0000005700000034000003ac000002530000016b000002a6000000fa000001e600000238000001d40000007e000000ce0000029600000196000002900000037c000002d80000017800000235000003870000019f0000034d000000880000019000000129000002be000003c50000023e000003b30000005e000000a6000000580000021300000270000001dd0000014a0000039c000003720000024e000003630000034f0000018f0000027e000002550000000e00000266000000b60000023d000003c9000001fa0000016c000001fd0000031a000002b3000000b1000002fa000002510000027a000001510000018c0000022c0000021500000034000001b700000218000000d90000016100000236000002e1000001c60000007800000250000003360000002800000088000000b80000013d000003d40000032b000000d30000026d000001e3;
  for (i=0;i<256;i=i+1) pm.mem[3*256+i] = expv[32*i +: 32];
  go(0,3,2,100,0,0,0,80,0); $display("pkt1: %0d clk", cyc-c0); n=n+1;
  if (bm[2*8192+100] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 0"); end
  if (bm[2*8192+101] !== 8'hb5) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 1"); end
  if (bm[2*8192+102] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 2"); end
  if (bm[2*8192+103] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 3"); end
  if (bm[2*8192+104] !== 8'hca) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 4"); end
  if (bm[2*8192+105] !== 8'hd4) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 5"); end
  if (bm[2*8192+106] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 6"); end
  if (bm[2*8192+107] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 7"); end
  if (bm[2*8192+108] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 8"); end
  if (bm[2*8192+109] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 9"); end
  if (bm[2*8192+110] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 10"); end
  if (bm[2*8192+111] !== 8'hd8) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 11"); end
  if (bm[2*8192+112] !== 8'h0c) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 12"); end
  if (bm[2*8192+113] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 13"); end
  if (bm[2*8192+114] !== 8'h1e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 14"); end
  if (bm[2*8192+115] !== 8'hc6) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 15"); end
  if (bm[2*8192+116] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 16"); end
  if (bm[2*8192+117] !== 8'h6b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 17"); end
  if (bm[2*8192+118] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 18"); end
  if (bm[2*8192+119] !== 8'h58) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 19"); end
  if (bm[2*8192+120] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 20"); end
  if (bm[2*8192+121] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 21"); end
  if (bm[2*8192+122] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 22"); end
  if (bm[2*8192+123] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 23"); end
  if (bm[2*8192+124] !== 8'h0d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 24"); end
  if (bm[2*8192+125] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 25"); end
  if (bm[2*8192+126] !== 8'hb2) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 26"); end
  if (bm[2*8192+127] !== 8'hc8) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 27"); end
  if (bm[2*8192+128] !== 8'h58) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 28"); end
  if (bm[2*8192+129] !== 8'h54) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 29"); end
  if (bm[2*8192+130] !== 8'h7a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 30"); end
  if (bm[2*8192+131] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 31"); end
  if (bm[2*8192+132] !== 8'ha9) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 32"); end
  if (bm[2*8192+133] !== 8'h6f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 33"); end
  if (bm[2*8192+134] !== 8'h2c) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 34"); end
  if (bm[2*8192+135] !== 8'hb3) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 35"); end
  if (bm[2*8192+136] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 36"); end
  if (bm[2*8192+137] !== 8'hdc) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 37"); end
  if (bm[2*8192+138] !== 8'h1f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 38"); end
  if (bm[2*8192+139] !== 8'h5b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 39"); end
  if (bm[2*8192+140] !== 8'hfa) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 40"); end
  if (bm[2*8192+141] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 41"); end
  if (bm[2*8192+142] !== 8'hdf) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 42"); end
  if (bm[2*8192+143] !== 8'ha3) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 43"); end
  if (bm[2*8192+144] !== 8'h2d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 44"); end
  if (bm[2*8192+145] !== 8'h66) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 45"); end
  if (bm[2*8192+146] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 46"); end
  if (bm[2*8192+147] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 47"); end
  if (bm[2*8192+148] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 48"); end
  if (bm[2*8192+149] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 49"); end
  if (bm[2*8192+150] !== 8'h8f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 50"); end
  if (bm[2*8192+151] !== 8'h3d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 51"); end
  if (bm[2*8192+152] !== 8'h3d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 52"); end
  if (bm[2*8192+153] !== 8'hb6) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 53"); end
  if (bm[2*8192+154] !== 8'h93) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 54"); end
  if (bm[2*8192+155] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 55"); end
  if (bm[2*8192+156] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 56"); end
  if (bm[2*8192+157] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 57"); end
  if (bm[2*8192+158] !== 8'h54) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 58"); end
  if (bm[2*8192+159] !== 8'h77) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 59"); end
  if (bm[2*8192+160] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 60"); end
  if (bm[2*8192+161] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 61"); end
  if (bm[2*8192+162] !== 8'h88) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 62"); end
  if (bm[2*8192+163] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 63"); end
  if (bm[2*8192+164] !== 8'h29) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 64"); end
  if (bm[2*8192+165] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 65"); end
  if (bm[2*8192+166] !== 8'hcc) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 66"); end
  if (bm[2*8192+167] !== 8'hee) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 67"); end
  if (bm[2*8192+168] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 68"); end
  if (bm[2*8192+169] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 69"); end
  if (bm[2*8192+170] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 70"); end
  if (bm[2*8192+171] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 71"); end
  if (bm[2*8192+172] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 72"); end
  if (bm[2*8192+173] !== 8'h19) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 73"); end
  if (bm[2*8192+174] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 74"); end
  if (bm[2*8192+175] !== 8'h4d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 75"); end
  if (bm[2*8192+176] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 76"); end
  if (bm[2*8192+177] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 77"); end
  if (bm[2*8192+178] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 78"); end
  if (bm[2*8192+179] !== 8'h8d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 79"); end
  if (bm[2*8192+180] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 80"); end
  if (bm[2*8192+181] !== 8'h61) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 81"); end
  if (bm[2*8192+182] !== 8'hcb) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 82"); end
  if (bm[2*8192+183] !== 8'h37) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 83"); end
  if (bm[2*8192+184] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 84"); end
  if (bm[2*8192+185] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 85"); end
  if (bm[2*8192+186] !== 8'h59) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 86"); end
  if (bm[2*8192+187] !== 8'hea) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 87"); end
  if (bm[2*8192+188] !== 8'h8c) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 88"); end
  if (bm[2*8192+189] !== 8'h1f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 89"); end
  if (bm[2*8192+190] !== 8'hd4) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 90"); end
  if (bm[2*8192+191] !== 8'he1) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 91"); end
  if (bm[2*8192+192] !== 8'h68) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 92"); end
  if (bm[2*8192+193] !== 8'h9e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 93"); end
  if (bm[2*8192+194] !== 8'h3e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 94"); end
  if (bm[2*8192+195] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 95"); end
  if (bm[2*8192+196] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 96"); end
  if (bm[2*8192+197] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 97"); end
  if (bm[2*8192+198] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 98"); end
  if (bm[2*8192+199] !== 8'heb) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 99"); end
  if (bm[2*8192+200] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 100"); end
  if (bm[2*8192+201] !== 8'h5c) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 101"); end
  if (bm[2*8192+202] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 102"); end
  if (bm[2*8192+203] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 103"); end
  if (bm[2*8192+204] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 104"); end
  if (bm[2*8192+205] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 105"); end
  if (bm[2*8192+206] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 106"); end
  if (bm[2*8192+207] !== 8'h5a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 107"); end
  if (bm[2*8192+208] !== 8'h42) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 108"); end
  if (bm[2*8192+209] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 109"); end
  if (bm[2*8192+210] !== 8'h4f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 110"); end
  if (bm[2*8192+211] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 111"); end
  if (bm[2*8192+212] !== 8'h9a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 112"); end
  if (bm[2*8192+213] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 113"); end
  if (bm[2*8192+214] !== 8'hd2) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 114"); end
  if (bm[2*8192+215] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 115"); end
  if (bm[2*8192+216] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 116"); end
  if (bm[2*8192+217] !== 8'h89) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 117"); end
  if (bm[2*8192+218] !== 8'h58) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 118"); end
  if (bm[2*8192+219] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 119"); end
  if (bm[2*8192+220] !== 8'h56) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 120"); end
  if (bm[2*8192+221] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 121"); end
  if (bm[2*8192+222] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 122"); end
  if (bm[2*8192+223] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 123"); end
  if (bm[2*8192+224] !== 8'hc3) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 124"); end
  if (bm[2*8192+225] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 125"); end
  if (bm[2*8192+226] !== 8'h99) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 126"); end
  if (bm[2*8192+227] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 127"); end
  if (bm[2*8192+228] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 128"); end
  if (bm[2*8192+229] !== 8'hba) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 129"); end
  if (bm[2*8192+230] !== 8'h5b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 130"); end
  if (bm[2*8192+231] !== 8'h8c) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 131"); end
  if (bm[2*8192+232] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 132"); end
  if (bm[2*8192+233] !== 8'hd5) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 133"); end
  if (bm[2*8192+234] !== 8'hba) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 134"); end
  if (bm[2*8192+235] !== 8'he6) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 135"); end
  if (bm[2*8192+236] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 136"); end
  if (bm[2*8192+237] !== 8'h69) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 137"); end
  if (bm[2*8192+238] !== 8'hcc) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 138"); end
  if (bm[2*8192+239] !== 8'he0) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 139"); end
  if (bm[2*8192+240] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 140"); end
  if (bm[2*8192+241] !== 8'h91) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 141"); end
  if (bm[2*8192+242] !== 8'h9d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 142"); end
  if (bm[2*8192+243] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 143"); end
  if (bm[2*8192+244] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 144"); end
  if (bm[2*8192+245] !== 8'h79) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 145"); end
  if (bm[2*8192+246] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 146"); end
  if (bm[2*8192+247] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 147"); end
  if (bm[2*8192+248] !== 8'h47) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 148"); end
  if (bm[2*8192+249] !== 8'h56) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 149"); end
  if (bm[2*8192+250] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 150"); end
  if (bm[2*8192+251] !== 8'h4d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 151"); end
  if (bm[2*8192+252] !== 8'hc1) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 152"); end
  if (bm[2*8192+253] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 153"); end
  if (bm[2*8192+254] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 154"); end
  if (bm[2*8192+255] !== 8'h92) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 155"); end
  if (bm[2*8192+256] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 156"); end
  if (bm[2*8192+257] !== 8'ha1) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 157"); end
  if (bm[2*8192+258] !== 8'hcf) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 158"); end
  if (bm[2*8192+259] !== 8'h95) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 159"); end
  if (bm[2*8192+260] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 160"); end
  if (bm[2*8192+261] !== 8'h6b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 161"); end
  if (bm[2*8192+262] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 162"); end
  if (bm[2*8192+263] !== 8'h7d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 163"); end
  if (bm[2*8192+264] !== 8'h67) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 164"); end
  if (bm[2*8192+265] !== 8'hef) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 165"); end
  if (bm[2*8192+266] !== 8'h09) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 166"); end
  if (bm[2*8192+267] !== 8'h8e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 167"); end
  if (bm[2*8192+268] !== 8'hf4) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 168"); end
  if (bm[2*8192+269] !== 8'hfb) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 169"); end
  if (bm[2*8192+270] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 170"); end
  if (bm[2*8192+271] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 171"); end
  if (bm[2*8192+272] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 172"); end
  if (bm[2*8192+273] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 173"); end
  if (bm[2*8192+274] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 174"); end
  if (bm[2*8192+275] !== 8'hfd) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 175"); end
  if (bm[2*8192+276] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 176"); end
  if (bm[2*8192+277] !== 8'h9d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 177"); end
  if (bm[2*8192+278] !== 8'h5b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 178"); end
  if (bm[2*8192+279] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 179"); end
  if (bm[2*8192+280] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 180"); end
  if (bm[2*8192+281] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 181"); end
  if (bm[2*8192+282] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 182"); end
  if (bm[2*8192+283] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 183"); end
  if (bm[2*8192+284] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 184"); end
  if (bm[2*8192+285] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 185"); end
  if (bm[2*8192+286] !== 8'hc2) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 186"); end
  if (bm[2*8192+287] !== 8'ha7) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 187"); end
  if (bm[2*8192+288] !== 8'h9a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 188"); end
  if (bm[2*8192+289] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 189"); end
  if (bm[2*8192+290] !== 8'h56) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 190"); end
  if (bm[2*8192+291] !== 8'h5f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 191"); end
  if (bm[2*8192+292] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 192"); end
  if (bm[2*8192+293] !== 8'h52) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 193"); end
  if (bm[2*8192+294] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 194"); end
  if (bm[2*8192+295] !== 8'h69) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 195"); end
  if (bm[2*8192+296] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 196"); end
  if (bm[2*8192+297] !== 8'hfa) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 197"); end
  if (bm[2*8192+298] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 198"); end
  if (bm[2*8192+299] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 199"); end
  if (bm[2*8192+300] !== 8'h52) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 200"); end
  if (bm[2*8192+301] !== 8'hd0) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 201"); end
  if (bm[2*8192+302] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 202"); end
  if (bm[2*8192+303] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 203"); end
  if (bm[2*8192+304] !== 8'h2f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 204"); end
  if (bm[2*8192+305] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 205"); end
  if (bm[2*8192+306] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 206"); end
  if (bm[2*8192+307] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 207"); end
  if (bm[2*8192+308] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 208"); end
  if (bm[2*8192+309] !== 8'hac) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 209"); end
  if (bm[2*8192+310] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 210"); end
  if (bm[2*8192+311] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 211"); end
  if (bm[2*8192+312] !== 8'h5f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 212"); end
  if (bm[2*8192+313] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 213"); end
  if (bm[2*8192+314] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 214"); end
  if (bm[2*8192+315] !== 8'hb8) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 215"); end
  if (bm[2*8192+316] !== 8'h95) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 216"); end
  if (bm[2*8192+317] !== 8'h58) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 217"); end
  if (bm[2*8192+318] !== 8'heb) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 218"); end
  if (bm[2*8192+319] !== 8'hc8) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 219"); end
  if (bm[2*8192+320] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 220"); end
  if (bm[2*8192+321] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 221"); end
  if (bm[2*8192+322] !== 8'hd2) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 222"); end
  if (bm[2*8192+323] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 223"); end
  if (bm[2*8192+324] !== 8'h61) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 224"); end
  if (bm[2*8192+325] !== 8'h5b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 225"); end
  if (bm[2*8192+326] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 226"); end
  if (bm[2*8192+327] !== 8'h5c) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 227"); end
  if (bm[2*8192+328] !== 8'hd0) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 228"); end
  if (bm[2*8192+329] !== 8'h89) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 229"); end
  if (bm[2*8192+330] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 230"); end
  if (bm[2*8192+331] !== 8'h58) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 231"); end
  if (bm[2*8192+332] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 232"); end
  if (bm[2*8192+333] !== 8'hfb) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 233"); end
  if (bm[2*8192+334] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 234"); end
  if (bm[2*8192+335] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 235"); end
  if (bm[2*8192+336] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 236"); end
  if (bm[2*8192+337] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 237"); end
  if (bm[2*8192+338] !== 8'h9b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 238"); end
  if (bm[2*8192+339] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 239"); end
  if (bm[2*8192+340] !== 8'hb0) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 240"); end
  if (bm[2*8192+341] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 241"); end
  if (bm[2*8192+342] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 242"); end
  if (bm[2*8192+343] !== 8'hc1) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 243"); end
  if (bm[2*8192+344] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 244"); end
  if (bm[2*8192+345] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 245"); end
  if (bm[2*8192+346] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 246"); end
  if (bm[2*8192+347] !== 8'hcc) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 247"); end
  if (bm[2*8192+348] !== 8'hf0) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 248"); end
  if (bm[2*8192+349] !== 8'h71) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 249"); end
  if (bm[2*8192+350] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 250"); end
  if (bm[2*8192+351] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 251"); end
  if (bm[2*8192+352] !== 8'hb6) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 252"); end
  if (bm[2*8192+353] !== 8'h54) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 253"); end
  if (bm[2*8192+354] !== 8'ha9) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 254"); end
  if (bm[2*8192+355] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 255"); end
  if (bm[2*8192+356] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 256"); end
  if (bm[2*8192+357] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 257"); end
  if (bm[2*8192+358] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 258"); end
  if (bm[2*8192+359] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 259"); end
  if (bm[2*8192+360] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 260"); end
  if (bm[2*8192+361] !== 8'h9c) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 261"); end
  if (bm[2*8192+362] !== 8'h93) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 262"); end
  if (bm[2*8192+363] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 263"); end
  if (bm[2*8192+364] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 264"); end
  if (bm[2*8192+365] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 265"); end
  if (bm[2*8192+366] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 266"); end
  if (bm[2*8192+367] !== 8'h61) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 267"); end
  if (bm[2*8192+368] !== 8'hee) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 268"); end
  if (bm[2*8192+369] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 269"); end
  if (bm[2*8192+370] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 270"); end
  if (bm[2*8192+371] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 271"); end
  if (bm[2*8192+372] !== 8'h69) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 272"); end
  if (bm[2*8192+373] !== 8'h6c) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 273"); end
  if (bm[2*8192+374] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 274"); end
  if (bm[2*8192+375] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 275"); end
  if (bm[2*8192+376] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 276"); end
  if (bm[2*8192+377] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 277"); end
  if (bm[2*8192+378] !== 8'h30) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 278"); end
  if (bm[2*8192+379] !== 8'h69) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 279"); end
  if (bm[2*8192+380] !== 8'h7d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 280"); end
  if (bm[2*8192+381] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 281"); end
  if (bm[2*8192+382] !== 8'hec) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 282"); end
  if (bm[2*8192+383] !== 8'h1d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 283"); end
  if (bm[2*8192+384] !== 8'hf9) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 284"); end
  if (bm[2*8192+385] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 285"); end
  if (bm[2*8192+386] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 286"); end
  if (bm[2*8192+387] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 287"); end
  if (bm[2*8192+388] !== 8'h89) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 288"); end
  if (bm[2*8192+389] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 289"); end
  if (bm[2*8192+390] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 290"); end
  if (bm[2*8192+391] !== 8'he2) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 291"); end
  if (bm[2*8192+392] !== 8'h3d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 292"); end
  if (bm[2*8192+393] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 293"); end
  if (bm[2*8192+394] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 294"); end
  if (bm[2*8192+395] !== 8'h89) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 295"); end
  if (bm[2*8192+396] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 296"); end
  if (bm[2*8192+397] !== 8'hb6) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 297"); end
  if (bm[2*8192+398] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 298"); end
  if (bm[2*8192+399] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 299"); end
  if (bm[2*8192+400] !== 8'h61) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 300"); end
  if (bm[2*8192+401] !== 8'hcb) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 301"); end
  if (bm[2*8192+402] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 302"); end
  if (bm[2*8192+403] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 303"); end
  if (bm[2*8192+404] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 304"); end
  if (bm[2*8192+405] !== 8'h4d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 305"); end
  if (bm[2*8192+406] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 306"); end
  if (bm[2*8192+407] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 307"); end
  if (bm[2*8192+408] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 308"); end
  if (bm[2*8192+409] !== 8'ha7) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 309"); end
  if (bm[2*8192+410] !== 8'hf4) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 310"); end
  if (bm[2*8192+411] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 311"); end
  if (bm[2*8192+412] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 312"); end
  if (bm[2*8192+413] !== 8'h61) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 313"); end
  if (bm[2*8192+414] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 314"); end
  if (bm[2*8192+415] !== 8'h59) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 315"); end
  if (bm[2*8192+416] !== 8'h2d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 316"); end
  if (bm[2*8192+417] !== 8'he0) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 317"); end
  if (bm[2*8192+418] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 318"); end
  if (bm[2*8192+419] !== 8'h3d) begin fails=fails+1; if (fails<6) $display("FAIL pkt1 byte 319"); end
  expv = 8192'hfffffd32fffffb97fffff1befffffb7afffff4d9fffff9a7000002fc0000043bfffff74cfffff61affffffa1fffff5fdfffffaa8fffffd0a00000d29fffff083000005cbfffff74d00000ff4fffffdd50000003bfffffd8bfffff5e6fffffaa0fffff58e00000405fffff87a00000261000000df000009ccfffff1edfffff58c000001e600000063fffffd740000048f00000a3700000a0f00000535000001aa00000bfc00000ea2fffff127fffffdbefffffb320000049a00000bfffffffd4a0000021b00000320fffff41800000f9900000a64fffffb11fffff22e000009c5000008dd0000031500000614fffffff400000708fffffda5fffff94600000e99fffff0adfffff232fffff12c0000018dfffffe79fffff494fffff00ffffff77a000003c0fffff8d300000588fffff491fffffcdbfffff27ffffffffe00000fe1fffff2c4fffffb57fffff5380000069900000e7a000004a2fffff273fffff6a10000043affffff1cfffff555000005b500000e90000003ad0000005dfffffd92fffff26200000a7600000388000006d600000e65fffff6dcfffffc08fffffb0c000005850000084a00000cf3fffffbd900000e83fffff08efffffecefffffedafffff0fcfffff76cfffffa07fffff57ffffff9c300000375fffff138000001d5fffff1cc00000b14fffff3f7000008c2fffffae600000505000009a4000003630000090c00000064fffffa76fffffac200000810fffff45700000efd00000315fffffdc4fffff9df00000a5dfffff9f9fffff02b00000751fffff535fffff85200000a8ffffff98dfffffb0800000280fffff3ec00000152fffff7ccfffff53f00000442fffff209fffffd27fffff632fffffa15ffffffb5fffff130000000cb00000978fffffa74fffff301fffff87e00000327fffff46cffffff42fffff985fffff43f00000e85fffffe3800000ef100000082fffff5d9000003fc0000063c00000d54fffff456fffff9fdfffff1ca000008e0000009df0000075100000d59fffffbc500000016fffff0d800000a5800000c0d0000022a0000040b000009a50000099e00000cec000004e8fffffebf00000788000003d2fffffe2700000f5affffff33000009fe00000363fffffe3900000eabfffffb03fffff77bfffff4ec00000fb3fffffbadfffffa25fffff64d000006fbfffff5aefffff14afffff17c0000033dfffffb2e000004e9000007ce00000519fffffb80000009c4fffff4effffff5fc0000066efffffca4000007cf00000244fffffb5ffffff937fffff54900000bbdfffff888000005c40000072e0000001cfffff9010000091400000c4b00000c360000039000000de40000040dfffff364fffff01cfffffb8cfffffeac000006d6000002c800000a51ffffffb6fffff4d900000efe00000f23fffff718;
  for (i=0;i<256;i=i+1) pm.mem[3*256+i] = expv[32*i +: 32];
  go(1,3,1,7,0,0,0,80,0); $display("pkt0: %0d clk", cyc-c0); n=n+1;
  if (bm[1*8192+7] !== 8'he8) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 0"); end
  if (bm[1*8192+8] !== 8'hb8) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 1"); end
  if (bm[1*8192+9] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 2"); end
  if (bm[1*8192+10] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 3"); end
  if (bm[1*8192+11] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 4"); end
  if (bm[1*8192+12] !== 8'h93) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 5"); end
  if (bm[1*8192+13] !== 8'had) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 6"); end
  if (bm[1*8192+14] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 7"); end
  if (bm[1*8192+15] !== 8'h5f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 8"); end
  if (bm[1*8192+16] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 9"); end
  if (bm[1*8192+17] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 10"); end
  if (bm[1*8192+18] !== 8'h53) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 11"); end
  if (bm[1*8192+19] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 12"); end
  if (bm[1*8192+20] !== 8'h54) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 13"); end
  if (bm[1*8192+21] !== 8'h91) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 14"); end
  if (bm[1*8192+22] !== 8'h8e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 15"); end
  if (bm[1*8192+23] !== 8'h92) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 16"); end
  if (bm[1*8192+24] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 17"); end
  if (bm[1*8192+25] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 18"); end
  if (bm[1*8192+26] !== 8'h3e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 19"); end
  if (bm[1*8192+27] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 20"); end
  if (bm[1*8192+28] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 21"); end
  if (bm[1*8192+29] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 22"); end
  if (bm[1*8192+30] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 23"); end
  if (bm[1*8192+31] !== 8'h53) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 24"); end
  if (bm[1*8192+32] !== 8'h1e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 25"); end
  if (bm[1*8192+33] !== 8'hb5) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 26"); end
  if (bm[1*8192+34] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 27"); end
  if (bm[1*8192+35] !== 8'hdd) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 28"); end
  if (bm[1*8192+36] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 29"); end
  if (bm[1*8192+37] !== 8'h5b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 30"); end
  if (bm[1*8192+38] !== 8'hf2) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 31"); end
  if (bm[1*8192+39] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 32"); end
  if (bm[1*8192+40] !== 8'h8d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 33"); end
  if (bm[1*8192+41] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 34"); end
  if (bm[1*8192+42] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 35"); end
  if (bm[1*8192+43] !== 8'hde) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 36"); end
  if (bm[1*8192+44] !== 8'h1d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 37"); end
  if (bm[1*8192+45] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 38"); end
  if (bm[1*8192+46] !== 8'hb7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 39"); end
  if (bm[1*8192+47] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 40"); end
  if (bm[1*8192+48] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 41"); end
  if (bm[1*8192+49] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 42"); end
  if (bm[1*8192+50] !== 8'h52) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 43"); end
  if (bm[1*8192+51] !== 8'hde) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 44"); end
  if (bm[1*8192+52] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 45"); end
  if (bm[1*8192+53] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 46"); end
  if (bm[1*8192+54] !== 8'hb8) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 47"); end
  if (bm[1*8192+55] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 48"); end
  if (bm[1*8192+56] !== 8'h64) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 49"); end
  if (bm[1*8192+57] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 50"); end
  if (bm[1*8192+58] !== 8'hd0) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 51"); end
  if (bm[1*8192+59] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 52"); end
  if (bm[1*8192+60] !== 8'h9b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 53"); end
  if (bm[1*8192+61] !== 8'hc7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 54"); end
  if (bm[1*8192+62] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 55"); end
  if (bm[1*8192+63] !== 8'hd2) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 56"); end
  if (bm[1*8192+64] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 57"); end
  if (bm[1*8192+65] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 58"); end
  if (bm[1*8192+66] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 59"); end
  if (bm[1*8192+67] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 60"); end
  if (bm[1*8192+68] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 61"); end
  if (bm[1*8192+69] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 62"); end
  if (bm[1*8192+70] !== 8'h1d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 63"); end
  if (bm[1*8192+71] !== 8'h66) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 64"); end
  if (bm[1*8192+72] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 65"); end
  if (bm[1*8192+73] !== 8'hde) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 66"); end
  if (bm[1*8192+74] !== 8'hd6) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 67"); end
  if (bm[1*8192+75] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 68"); end
  if (bm[1*8192+76] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 69"); end
  if (bm[1*8192+77] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 70"); end
  if (bm[1*8192+78] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 71"); end
  if (bm[1*8192+79] !== 8'h9b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 72"); end
  if (bm[1*8192+80] !== 8'hb7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 73"); end
  if (bm[1*8192+81] !== 8'heb) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 74"); end
  if (bm[1*8192+82] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 75"); end
  if (bm[1*8192+83] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 76"); end
  if (bm[1*8192+84] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 77"); end
  if (bm[1*8192+85] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 78"); end
  if (bm[1*8192+86] !== 8'hbb) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 79"); end
  if (bm[1*8192+87] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 80"); end
  if (bm[1*8192+88] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 81"); end
  if (bm[1*8192+89] !== 8'hd3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 82"); end
  if (bm[1*8192+90] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 83"); end
  if (bm[1*8192+91] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 84"); end
  if (bm[1*8192+92] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 85"); end
  if (bm[1*8192+93] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 86"); end
  if (bm[1*8192+94] !== 8'h99) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 87"); end
  if (bm[1*8192+95] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 88"); end
  if (bm[1*8192+96] !== 8'h69) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 89"); end
  if (bm[1*8192+97] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 90"); end
  if (bm[1*8192+98] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 91"); end
  if (bm[1*8192+99] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 92"); end
  if (bm[1*8192+100] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 93"); end
  if (bm[1*8192+101] !== 8'hba) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 94"); end
  if (bm[1*8192+102] !== 8'h30) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 95"); end
  if (bm[1*8192+103] !== 8'h3c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 96"); end
  if (bm[1*8192+104] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 97"); end
  if (bm[1*8192+105] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 98"); end
  if (bm[1*8192+106] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 99"); end
  if (bm[1*8192+107] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 100"); end
  if (bm[1*8192+108] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 101"); end
  if (bm[1*8192+109] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 102"); end
  if (bm[1*8192+110] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 103"); end
  if (bm[1*8192+111] !== 8'h5b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 104"); end
  if (bm[1*8192+112] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 105"); end
  if (bm[1*8192+113] !== 8'h7e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 106"); end
  if (bm[1*8192+114] !== 8'h59) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 107"); end
  if (bm[1*8192+115] !== 8'hb7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 108"); end
  if (bm[1*8192+116] !== 8'hf9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 109"); end
  if (bm[1*8192+117] !== 8'h81) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 110"); end
  if (bm[1*8192+118] !== 8'h5a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 111"); end
  if (bm[1*8192+119] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 112"); end
  if (bm[1*8192+120] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 113"); end
  if (bm[1*8192+121] !== 8'hfa) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 114"); end
  if (bm[1*8192+122] !== 8'hdb) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 115"); end
  if (bm[1*8192+123] !== 8'ha1) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 116"); end
  if (bm[1*8192+124] !== 8'ha7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 117"); end
  if (bm[1*8192+125] !== 8'he2) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 118"); end
  if (bm[1*8192+126] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 119"); end
  if (bm[1*8192+127] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 120"); end
  if (bm[1*8192+128] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 121"); end
  if (bm[1*8192+129] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 122"); end
  if (bm[1*8192+130] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 123"); end
  if (bm[1*8192+131] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 124"); end
  if (bm[1*8192+132] !== 8'h07) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 125"); end
  if (bm[1*8192+133] !== 8'hac) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 126"); end
  if (bm[1*8192+134] !== 8'hea) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 127"); end
  if (bm[1*8192+135] !== 8'h66) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 128"); end
  if (bm[1*8192+136] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 129"); end
  if (bm[1*8192+137] !== 8'hc4) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 130"); end
  if (bm[1*8192+138] !== 8'h89) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 131"); end
  if (bm[1*8192+139] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 132"); end
  if (bm[1*8192+140] !== 8'h9d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 133"); end
  if (bm[1*8192+141] !== 8'h68) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 134"); end
  if (bm[1*8192+142] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 135"); end
  if (bm[1*8192+143] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 136"); end
  if (bm[1*8192+144] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 137"); end
  if (bm[1*8192+145] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 138"); end
  if (bm[1*8192+146] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 139"); end
  if (bm[1*8192+147] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 140"); end
  if (bm[1*8192+148] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 141"); end
  if (bm[1*8192+149] !== 8'hde) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 142"); end
  if (bm[1*8192+150] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 143"); end
  if (bm[1*8192+151] !== 8'hd6) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 144"); end
  if (bm[1*8192+152] !== 8'h17) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 145"); end
  if (bm[1*8192+153] !== 8'h52) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 146"); end
  if (bm[1*8192+154] !== 8'hee) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 147"); end
  if (bm[1*8192+155] !== 8'h6c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 148"); end
  if (bm[1*8192+156] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 149"); end
  if (bm[1*8192+157] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 150"); end
  if (bm[1*8192+158] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 151"); end
  if (bm[1*8192+159] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 152"); end
  if (bm[1*8192+160] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 153"); end
  if (bm[1*8192+161] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 154"); end
  if (bm[1*8192+162] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 155"); end
  if (bm[1*8192+163] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 156"); end
  if (bm[1*8192+164] !== 8'h0f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 157"); end
  if (bm[1*8192+165] !== 8'hda) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 158"); end
  if (bm[1*8192+166] !== 8'h2f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 159"); end
  if (bm[1*8192+167] !== 8'hc1) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 160"); end
  if (bm[1*8192+168] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 161"); end
  if (bm[1*8192+169] !== 8'hea) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 162"); end
  if (bm[1*8192+170] !== 8'h9c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 163"); end
  if (bm[1*8192+171] !== 8'hb3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 164"); end
  if (bm[1*8192+172] !== 8'he5) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 165"); end
  if (bm[1*8192+173] !== 8'h7d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 166"); end
  if (bm[1*8192+174] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 167"); end
  if (bm[1*8192+175] !== 8'h5d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 168"); end
  if (bm[1*8192+176] !== 8'hc1) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 169"); end
  if (bm[1*8192+177] !== 8'h9a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 170"); end
  if (bm[1*8192+178] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 171"); end
  if (bm[1*8192+179] !== 8'hbb) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 172"); end
  if (bm[1*8192+180] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 173"); end
  if (bm[1*8192+181] !== 8'h0a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 174"); end
  if (bm[1*8192+182] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 175"); end
  if (bm[1*8192+183] !== 8'hd8) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 176"); end
  if (bm[1*8192+184] !== 8'hf0) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 177"); end
  if (bm[1*8192+185] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 178"); end
  if (bm[1*8192+186] !== 8'h9c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 179"); end
  if (bm[1*8192+187] !== 8'h8d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 180"); end
  if (bm[1*8192+188] !== 8'h2b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 181"); end
  if (bm[1*8192+189] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 182"); end
  if (bm[1*8192+190] !== 8'h77) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 183"); end
  if (bm[1*8192+191] !== 8'h59) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 184"); end
  if (bm[1*8192+192] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 185"); end
  if (bm[1*8192+193] !== 8'ha2) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 186"); end
  if (bm[1*8192+194] !== 8'hea) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 187"); end
  if (bm[1*8192+195] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 188"); end
  if (bm[1*8192+196] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 189"); end
  if (bm[1*8192+197] !== 8'h47) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 190"); end
  if (bm[1*8192+198] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 191"); end
  if (bm[1*8192+199] !== 8'h88) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 192"); end
  if (bm[1*8192+200] !== 8'he5) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 193"); end
  if (bm[1*8192+201] !== 8'h91) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 194"); end
  if (bm[1*8192+202] !== 8'heb) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 195"); end
  if (bm[1*8192+203] !== 8'h6c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 196"); end
  if (bm[1*8192+204] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 197"); end
  if (bm[1*8192+205] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 198"); end
  if (bm[1*8192+206] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 199"); end
  if (bm[1*8192+207] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 200"); end
  if (bm[1*8192+208] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 201"); end
  if (bm[1*8192+209] !== 8'h53) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 202"); end
  if (bm[1*8192+210] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 203"); end
  if (bm[1*8192+211] !== 8'h2b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 204"); end
  if (bm[1*8192+212] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 205"); end
  if (bm[1*8192+213] !== 8'ha3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 206"); end
  if (bm[1*8192+214] !== 8'h37) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 207"); end
  if (bm[1*8192+215] !== 8'h9d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 208"); end
  if (bm[1*8192+216] !== 8'h8c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 209"); end
  if (bm[1*8192+217] !== 8'hcb) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 210"); end
  if (bm[1*8192+218] !== 8'hec) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 211"); end
  if (bm[1*8192+219] !== 8'h2b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 212"); end
  if (bm[1*8192+220] !== 8'h8d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 213"); end
  if (bm[1*8192+221] !== 8'hea) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 214"); end
  if (bm[1*8192+222] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 215"); end
  if (bm[1*8192+223] !== 8'h12) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 216"); end
  if (bm[1*8192+224] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 217"); end
  if (bm[1*8192+225] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 218"); end
  if (bm[1*8192+226] !== 8'ha1) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 219"); end
  if (bm[1*8192+227] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 220"); end
  if (bm[1*8192+228] !== 8'h2b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 221"); end
  if (bm[1*8192+229] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 222"); end
  if (bm[1*8192+230] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 223"); end
  if (bm[1*8192+231] !== 8'h2f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 224"); end
  if (bm[1*8192+232] !== 8'hb2) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 225"); end
  if (bm[1*8192+233] !== 8'h1e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 226"); end
  if (bm[1*8192+234] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 227"); end
  if (bm[1*8192+235] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 228"); end
  if (bm[1*8192+236] !== 8'hf3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 229"); end
  if (bm[1*8192+237] !== 8'h2b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 230"); end
  if (bm[1*8192+238] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 231"); end
  if (bm[1*8192+239] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 232"); end
  if (bm[1*8192+240] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 233"); end
  if (bm[1*8192+241] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 234"); end
  if (bm[1*8192+242] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 235"); end
  if (bm[1*8192+243] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 236"); end
  if (bm[1*8192+244] !== 8'hca) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 237"); end
  if (bm[1*8192+245] !== 8'hfd) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 238"); end
  if (bm[1*8192+246] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 239"); end
  if (bm[1*8192+247] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 240"); end
  if (bm[1*8192+248] !== 8'h42) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 241"); end
  if (bm[1*8192+249] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 242"); end
  if (bm[1*8192+250] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 243"); end
  if (bm[1*8192+251] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 244"); end
  if (bm[1*8192+252] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 245"); end
  if (bm[1*8192+253] !== 8'h53) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 246"); end
  if (bm[1*8192+254] !== 8'hf4) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 247"); end
  if (bm[1*8192+255] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 248"); end
  if (bm[1*8192+256] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 249"); end
  if (bm[1*8192+257] !== 8'h92) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 250"); end
  if (bm[1*8192+258] !== 8'he4) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 251"); end
  if (bm[1*8192+259] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 252"); end
  if (bm[1*8192+260] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 253"); end
  if (bm[1*8192+261] !== 8'h92) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 254"); end
  if (bm[1*8192+262] !== 8'hf0) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 255"); end
  if (bm[1*8192+263] !== 8'h98) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 256"); end
  if (bm[1*8192+264] !== 8'h62) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 257"); end
  if (bm[1*8192+265] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 258"); end
  if (bm[1*8192+266] !== 8'hec) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 259"); end
  if (bm[1*8192+267] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 260"); end
  if (bm[1*8192+268] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 261"); end
  if (bm[1*8192+269] !== 8'hf4) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 262"); end
  if (bm[1*8192+270] !== 8'h4d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 263"); end
  if (bm[1*8192+271] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 264"); end
  if (bm[1*8192+272] !== 8'hb8) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 265"); end
  if (bm[1*8192+273] !== 8'hb0) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 266"); end
  if (bm[1*8192+274] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 267"); end
  if (bm[1*8192+275] !== 8'h56) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 268"); end
  if (bm[1*8192+276] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 269"); end
  if (bm[1*8192+277] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 270"); end
  if (bm[1*8192+278] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 271"); end
  if (bm[1*8192+279] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 272"); end
  if (bm[1*8192+280] !== 8'h5f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 273"); end
  if (bm[1*8192+281] !== 8'hb9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 274"); end
  if (bm[1*8192+282] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 275"); end
  if (bm[1*8192+283] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 276"); end
  if (bm[1*8192+284] !== 8'h2d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 277"); end
  if (bm[1*8192+285] !== 8'hc3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 278"); end
  if (bm[1*8192+286] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 279"); end
  if (bm[1*8192+287] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 280"); end
  if (bm[1*8192+288] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 281"); end
  if (bm[1*8192+289] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 282"); end
  if (bm[1*8192+290] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 283"); end
  if (bm[1*8192+291] !== 8'he5) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 284"); end
  if (bm[1*8192+292] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 285"); end
  if (bm[1*8192+293] !== 8'h1f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 286"); end
  if (bm[1*8192+294] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 287"); end
  if (bm[1*8192+295] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 288"); end
  if (bm[1*8192+296] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 289"); end
  if (bm[1*8192+297] !== 8'hf6) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 290"); end
  if (bm[1*8192+298] !== 8'h92) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 291"); end
  if (bm[1*8192+299] !== 8'hf9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 292"); end
  if (bm[1*8192+300] !== 8'hb6) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 293"); end
  if (bm[1*8192+301] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 294"); end
  if (bm[1*8192+302] !== 8'h54) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 295"); end
  if (bm[1*8192+303] !== 8'hcb) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 296"); end
  if (bm[1*8192+304] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 297"); end
  if (bm[1*8192+305] !== 8'h62) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 298"); end
  if (bm[1*8192+306] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 299"); end
  if (bm[1*8192+307] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 300"); end
  if (bm[1*8192+308] !== 8'hfe) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 301"); end
  if (bm[1*8192+309] !== 8'hb3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 302"); end
  if (bm[1*8192+310] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 303"); end
  if (bm[1*8192+311] !== 8'hc3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 304"); end
  if (bm[1*8192+312] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 305"); end
  if (bm[1*8192+313] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 306"); end
  if (bm[1*8192+314] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 307"); end
  if (bm[1*8192+315] !== 8'hbd) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 308"); end
  if (bm[1*8192+316] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 309"); end
  if (bm[1*8192+317] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 310"); end
  if (bm[1*8192+318] !== 8'hfa) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 311"); end
  if (bm[1*8192+319] !== 8'h67) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 312"); end
  if (bm[1*8192+320] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 313"); end
  if (bm[1*8192+321] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 314"); end
  if (bm[1*8192+322] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 315"); end
  if (bm[1*8192+323] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 316"); end
  if (bm[1*8192+324] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 317"); end
  if (bm[1*8192+325] !== 8'hc4) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 318"); end
  if (bm[1*8192+326] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 319"); end
  if (bm[1*8192+327] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 320"); end
  if (bm[1*8192+328] !== 8'hd3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 321"); end
  if (bm[1*8192+329] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 322"); end
  if (bm[1*8192+330] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 323"); end
  if (bm[1*8192+331] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 324"); end
  if (bm[1*8192+332] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 325"); end
  if (bm[1*8192+333] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 326"); end
  if (bm[1*8192+334] !== 8'hba) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 327"); end
  if (bm[1*8192+335] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 328"); end
  if (bm[1*8192+336] !== 8'h53) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 329"); end
  if (bm[1*8192+337] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 330"); end
  if (bm[1*8192+338] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 331"); end
  if (bm[1*8192+339] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 332"); end
  if (bm[1*8192+340] !== 8'hd0) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 333"); end
  if (bm[1*8192+341] !== 8'h37) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 334"); end
  if (bm[1*8192+342] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 335"); end
  if (bm[1*8192+343] !== 8'h2b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 336"); end
  if (bm[1*8192+344] !== 8'h6f) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 337"); end
  if (bm[1*8192+345] !== 8'hb6) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 338"); end
  if (bm[1*8192+346] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 339"); end
  if (bm[1*8192+347] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 340"); end
  if (bm[1*8192+348] !== 8'h98) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 341"); end
  if (bm[1*8192+349] !== 8'h2d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 342"); end
  if (bm[1*8192+350] !== 8'h67) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 343"); end
  if (bm[1*8192+351] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 344"); end
  if (bm[1*8192+352] !== 8'h24) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 345"); end
  if (bm[1*8192+353] !== 8'hb3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 346"); end
  if (bm[1*8192+354] !== 8'hbd) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 347"); end
  if (bm[1*8192+355] !== 8'h57) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 348"); end
  if (bm[1*8192+356] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 349"); end
  if (bm[1*8192+357] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 350"); end
  if (bm[1*8192+358] !== 8'h56) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 351"); end
  if (bm[1*8192+359] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 352"); end
  if (bm[1*8192+360] !== 8'h59) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 353"); end
  if (bm[1*8192+361] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 354"); end
  if (bm[1*8192+362] !== 8'h97) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 355"); end
  if (bm[1*8192+363] !== 8'he4) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 356"); end
  if (bm[1*8192+364] !== 8'h12) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 357"); end
  if (bm[1*8192+365] !== 8'hb7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 358"); end
  if (bm[1*8192+366] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 359"); end
  if (bm[1*8192+367] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 360"); end
  if (bm[1*8192+368] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 361"); end
  if (bm[1*8192+369] !== 8'hd3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 362"); end
  if (bm[1*8192+370] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 363"); end
  if (bm[1*8192+371] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 364"); end
  if (bm[1*8192+372] !== 8'h7a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 365"); end
  if (bm[1*8192+373] !== 8'hc2) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 366"); end
  if (bm[1*8192+374] !== 8'hd3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 367"); end
  if (bm[1*8192+375] !== 8'h98) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 368"); end
  if (bm[1*8192+376] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 369"); end
  if (bm[1*8192+377] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 370"); end
  if (bm[1*8192+378] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 371"); end
  if (bm[1*8192+379] !== 8'h0c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 372"); end
  if (bm[1*8192+380] !== 8'hef) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 373"); end
  if (bm[1*8192+381] !== 8'hfe) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 374"); end
  if (bm[1*8192+382] !== 8'h92) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 375"); end
  if (bm[1*8192+383] !== 8'hd3) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 376"); end
  if (bm[1*8192+384] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 377"); end
  if (bm[1*8192+385] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 378"); end
  if (bm[1*8192+386] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 379"); end
  if (bm[1*8192+387] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 380"); end
  if (bm[1*8192+388] !== 8'hc9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 381"); end
  if (bm[1*8192+389] !== 8'he2) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 382"); end
  if (bm[1*8192+390] !== 8'hb7) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 383"); end
  if (bm[1*8192+391] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 384"); end
  if (bm[1*8192+392] !== 8'h19) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 385"); end
  if (bm[1*8192+393] !== 8'hc0) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 386"); end
  if (bm[1*8192+394] !== 8'h2c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 387"); end
  if (bm[1*8192+395] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 388"); end
  if (bm[1*8192+396] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 389"); end
  if (bm[1*8192+397] !== 8'h7d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 390"); end
  if (bm[1*8192+398] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 391"); end
  if (bm[1*8192+399] !== 8'h5a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 392"); end
  if (bm[1*8192+400] !== 8'hd8) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 393"); end
  if (bm[1*8192+401] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 394"); end
  if (bm[1*8192+402] !== 8'hac) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 395"); end
  if (bm[1*8192+403] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 396"); end
  if (bm[1*8192+404] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 397"); end
  if (bm[1*8192+405] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 398"); end
  if (bm[1*8192+406] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 399"); end
  if (bm[1*8192+407] !== 8'h79) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 400"); end
  if (bm[1*8192+408] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 401"); end
  if (bm[1*8192+409] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 402"); end
  if (bm[1*8192+410] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 403"); end
  if (bm[1*8192+411] !== 8'h8b) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 404"); end
  if (bm[1*8192+412] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 405"); end
  if (bm[1*8192+413] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 406"); end
  if (bm[1*8192+414] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 407"); end
  if (bm[1*8192+415] !== 8'h93) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 408"); end
  if (bm[1*8192+416] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 409"); end
  if (bm[1*8192+417] !== 8'h48) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 410"); end
  if (bm[1*8192+418] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 411"); end
  if (bm[1*8192+419] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 412"); end
  if (bm[1*8192+420] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 413"); end
  if (bm[1*8192+421] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 414"); end
  if (bm[1*8192+422] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkt0 byte 415"); end
  expv = 8192'h0000000100000002ffffffff000000000000000000000000ffffffff00000000ffffffff000000000000000100000002000000020000000200000000ffffffff000000020000000200000002fffffffe000000020000000200000001ffffffff0000000100000002ffffffff00000001000000020000000000000002ffffffff000000000000000200000000000000010000000200000000fffffffefffffffffffffffe00000002fffffffe0000000200000002fffffffe0000000200000002ffffffff0000000000000000000000020000000000000002fffffffeffffffff00000001fffffffffffffffefffffffefffffffe0000000200000002ffffffffffffffff0000000000000002fffffffefffffffe0000000100000002000000020000000200000000fffffffefffffffefffffffefffffffeffffffffffffffffffffffffffffffff00000000fffffffe00000001fffffffe00000001fffffffffffffffe00000000000000020000000200000000fffffffefffffffe0000000100000000fffffffffffffffe000000020000000000000001ffffffff000000000000000100000000fffffffe0000000200000000ffffffff00000002ffffffff00000002fffffffefffffffe0000000000000002fffffffe00000002ffffffff00000002ffffffffffffffffffffffff00000002fffffffefffffffe0000000100000001ffffffff0000000200000000ffffffff00000002fffffffe0000000200000000000000020000000000000000000000020000000200000000ffffffff00000000000000020000000000000001ffffffff0000000000000002fffffffffffffffffffffffe00000002ffffffff00000002ffffffff0000000100000001fffffffefffffffe000000020000000000000002ffffffff00000002fffffffffffffffe00000002ffffffff00000001fffffffefffffffe00000002000000020000000000000000fffffffeffffffff00000001fffffffe00000001ffffffff00000001fffffffe0000000000000000000000010000000200000001ffffffffffffffff0000000100000000fffffffe00000001000000020000000000000000fffffffffffffffefffffffefffffffeffffffff00000002ffffffff00000000fffffffffffffffffffffffe0000000200000000000000010000000000000002ffffffff0000000200000000ffffffff00000000ffffffff00000000fffffffffffffffffffffffefffffffe00000001000000010000000000000000000000020000000100000002000000020000000100000001fffffffffffffffffffffffe0000000100000000fffffffefffffffffffffffefffffffeffffffffffffffffffffffff0000000000000002000000000000000000000002fffffffe00000000;
  for (i=0;i<256;i=i+1) pm.mem[3*256+i] = expv[32*i +: 32];
  go(2,3,2,0,0,0,0,80,0); $display("pketa2: %0d clk", cyc-c0); n=n+1;
  if (bm[2*8192+0] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 0"); end
  if (bm[2*8192+1] !== 8'h24) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 1"); end
  if (bm[2*8192+2] !== 8'h68) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 2"); end
  if (bm[2*8192+3] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 3"); end
  if (bm[2*8192+4] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 4"); end
  if (bm[2*8192+5] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 5"); end
  if (bm[2*8192+6] !== 8'hdc) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 6"); end
  if (bm[2*8192+7] !== 8'h12) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 7"); end
  if (bm[2*8192+8] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 8"); end
  if (bm[2*8192+9] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 9"); end
  if (bm[2*8192+10] !== 8'h12) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 10"); end
  if (bm[2*8192+11] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 11"); end
  if (bm[2*8192+12] !== 8'hd3) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 12"); end
  if (bm[2*8192+13] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 13"); end
  if (bm[2*8192+14] !== 8'h61) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 14"); end
  if (bm[2*8192+15] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 15"); end
  if (bm[2*8192+16] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 16"); end
  if (bm[2*8192+17] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 17"); end
  if (bm[2*8192+18] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 18"); end
  if (bm[2*8192+19] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 19"); end
  if (bm[2*8192+20] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 20"); end
  if (bm[2*8192+21] !== 8'h12) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 21"); end
  if (bm[2*8192+22] !== 8'h42) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 22"); end
  if (bm[2*8192+23] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 23"); end
  if (bm[2*8192+24] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 24"); end
  if (bm[2*8192+25] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 25"); end
  if (bm[2*8192+26] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 26"); end
  if (bm[2*8192+27] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 27"); end
  if (bm[2*8192+28] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 28"); end
  if (bm[2*8192+29] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 29"); end
  if (bm[2*8192+30] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 30"); end
  if (bm[2*8192+31] !== 8'h99) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 31"); end
  if (bm[2*8192+32] !== 8'h81) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 32"); end
  if (bm[2*8192+33] !== 8'hc3) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 33"); end
  if (bm[2*8192+34] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 34"); end
  if (bm[2*8192+35] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 35"); end
  if (bm[2*8192+36] !== 8'hc9) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 36"); end
  if (bm[2*8192+37] !== 8'h30) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 37"); end
  if (bm[2*8192+38] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 38"); end
  if (bm[2*8192+39] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 39"); end
  if (bm[2*8192+40] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 40"); end
  if (bm[2*8192+41] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 41"); end
  if (bm[2*8192+42] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 42"); end
  if (bm[2*8192+43] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 43"); end
  if (bm[2*8192+44] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 44"); end
  if (bm[2*8192+45] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 45"); end
  if (bm[2*8192+46] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 46"); end
  if (bm[2*8192+47] !== 8'h2c) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 47"); end
  if (bm[2*8192+48] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 48"); end
  if (bm[2*8192+49] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 49"); end
  if (bm[2*8192+50] !== 8'h0d) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 50"); end
  if (bm[2*8192+51] !== 8'h03) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 51"); end
  if (bm[2*8192+52] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 52"); end
  if (bm[2*8192+53] !== 8'h12) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 53"); end
  if (bm[2*8192+54] !== 8'hc3) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 54"); end
  if (bm[2*8192+55] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 55"); end
  if (bm[2*8192+56] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 56"); end
  if (bm[2*8192+57] !== 8'h5a) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 57"); end
  if (bm[2*8192+58] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 58"); end
  if (bm[2*8192+59] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 59"); end
  if (bm[2*8192+60] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 60"); end
  if (bm[2*8192+61] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 61"); end
  if (bm[2*8192+62] !== 8'h88) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 62"); end
  if (bm[2*8192+63] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 63"); end
  if (bm[2*8192+64] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 64"); end
  if (bm[2*8192+65] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 65"); end
  if (bm[2*8192+66] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 66"); end
  if (bm[2*8192+67] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 67"); end
  if (bm[2*8192+68] !== 8'h0a) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 68"); end
  if (bm[2*8192+69] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 69"); end
  if (bm[2*8192+70] !== 8'h48) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 70"); end
  if (bm[2*8192+71] !== 8'h68) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 71"); end
  if (bm[2*8192+72] !== 8'h03) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 72"); end
  if (bm[2*8192+73] !== 8'h48) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 73"); end
  if (bm[2*8192+74] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 74"); end
  if (bm[2*8192+75] !== 8'h23) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 75"); end
  if (bm[2*8192+76] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 76"); end
  if (bm[2*8192+77] !== 8'h69) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 77"); end
  if (bm[2*8192+78] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 78"); end
  if (bm[2*8192+79] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 79"); end
  if (bm[2*8192+80] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 80"); end
  if (bm[2*8192+81] !== 8'ha3) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 81"); end
  if (bm[2*8192+82] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 82"); end
  if (bm[2*8192+83] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 83"); end
  if (bm[2*8192+84] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 84"); end
  if (bm[2*8192+85] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 85"); end
  if (bm[2*8192+86] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 86"); end
  if (bm[2*8192+87] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 87"); end
  if (bm[2*8192+88] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 88"); end
  if (bm[2*8192+89] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 89"); end
  if (bm[2*8192+90] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 90"); end
  if (bm[2*8192+91] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 91"); end
  if (bm[2*8192+92] !== 8'h68) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 92"); end
  if (bm[2*8192+93] !== 8'h9a) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 93"); end
  if (bm[2*8192+94] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 94"); end
  if (bm[2*8192+95] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pketa2 byte 95"); end
  expv = 8192'hfffffffe0000000100000002fffffffdfffffffc0000000000000004000000000000000200000000fffffffdffffffffffffffff0000000000000000fffffffc00000004fffffffd0000000300000004fffffffdfffffffc00000000fffffffd00000004fffffffd00000004fffffffffffffffefffffffe0000000400000002fffffffeffffffff00000004fffffffefffffffd00000000000000010000000200000000fffffffc0000000000000000ffffffff00000002000000010000000300000003000000040000000400000003fffffffefffffffcfffffffefffffffefffffffd00000002000000040000000200000003fffffffefffffffdfffffffd000000010000000200000003fffffffcfffffffffffffffffffffffd00000002fffffffc00000001fffffffcfffffffd0000000000000000fffffffd00000001fffffffe000000020000000000000001000000010000000300000004fffffffcffffffffffffffff00000004fffffffffffffffcfffffffffffffffefffffffe00000004fffffffd0000000400000003fffffffffffffffffffffffd00000003fffffffcfffffffdfffffffc00000000ffffffff000000030000000100000001fffffffe00000001fffffffffffffffcfffffffcfffffffe0000000000000003fffffffcfffffffe00000004fffffffe0000000000000002fffffffc0000000400000001000000030000000200000003fffffffe000000030000000400000000fffffffe0000000100000001fffffffeffffffff00000000000000030000000100000002fffffffc00000003fffffffd000000040000000200000003000000020000000100000004ffffffff00000003fffffffeffffffff00000004fffffffc0000000400000001fffffffd0000000000000002fffffffeffffffff000000010000000200000003fffffffd000000040000000200000001fffffffd0000000200000000000000020000000100000002000000010000000300000003fffffffefffffffefffffffd00000000fffffffdfffffffcffffffff000000040000000200000003fffffffdfffffffe00000002fffffffd00000004000000020000000100000003ffffffff00000002fffffffd0000000100000001fffffffcfffffffe00000001000000040000000100000001ffffffff00000004fffffffc00000002fffffffe00000002fffffffc00000002fffffffcfffffffefffffffdfffffffc00000001fffffffd00000004000000000000000200000003ffffffff000000020000000200000001fffffffffffffffffffffffe00000004fffffffcfffffffcfffffffc00000004fffffffc00000000fffffffd00000003fffffffeffffffff00000001fffffffffffffffd00000001fffffffe000000010000000000000000;
  for (i=0;i<256;i=i+1) pm.mem[3*256+i] = expv[32*i +: 32];
  go(2,3,2,0,1,0,0,80,0); $display("pketa4: %0d clk", cyc-c0); n=n+1;
  if (bm[2*8192+0] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 0"); end
  if (bm[2*8192+1] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 1"); end
  if (bm[2*8192+2] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 2"); end
  if (bm[2*8192+3] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 3"); end
  if (bm[2*8192+4] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 4"); end
  if (bm[2*8192+5] !== 8'h71) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 5"); end
  if (bm[2*8192+6] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 6"); end
  if (bm[2*8192+7] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 7"); end
  if (bm[2*8192+8] !== 8'h88) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 8"); end
  if (bm[2*8192+9] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 9"); end
  if (bm[2*8192+10] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 10"); end
  if (bm[2*8192+11] !== 8'h23) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 11"); end
  if (bm[2*8192+12] !== 8'h52) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 12"); end
  if (bm[2*8192+13] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 13"); end
  if (bm[2*8192+14] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 14"); end
  if (bm[2*8192+15] !== 8'h37) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 15"); end
  if (bm[2*8192+16] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 16"); end
  if (bm[2*8192+17] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 17"); end
  if (bm[2*8192+18] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 18"); end
  if (bm[2*8192+19] !== 8'h62) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 19"); end
  if (bm[2*8192+20] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 20"); end
  if (bm[2*8192+21] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 21"); end
  if (bm[2*8192+22] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 22"); end
  if (bm[2*8192+23] !== 8'h30) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 23"); end
  if (bm[2*8192+24] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 24"); end
  if (bm[2*8192+25] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 25"); end
  if (bm[2*8192+26] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 26"); end
  if (bm[2*8192+27] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 27"); end
  if (bm[2*8192+28] !== 8'h23) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 28"); end
  if (bm[2*8192+29] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 29"); end
  if (bm[2*8192+30] !== 8'h62) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 30"); end
  if (bm[2*8192+31] !== 8'h17) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 31"); end
  if (bm[2*8192+32] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 32"); end
  if (bm[2*8192+33] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 33"); end
  if (bm[2*8192+34] !== 8'h47) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 34"); end
  if (bm[2*8192+35] !== 8'h67) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 35"); end
  if (bm[2*8192+36] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 36"); end
  if (bm[2*8192+37] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 37"); end
  if (bm[2*8192+38] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 38"); end
  if (bm[2*8192+39] !== 8'h42) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 39"); end
  if (bm[2*8192+40] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 40"); end
  if (bm[2*8192+41] !== 8'h23) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 41"); end
  if (bm[2*8192+42] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 42"); end
  if (bm[2*8192+43] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 43"); end
  if (bm[2*8192+44] !== 8'h53) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 44"); end
  if (bm[2*8192+45] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 45"); end
  if (bm[2*8192+46] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 46"); end
  if (bm[2*8192+47] !== 8'h03) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 47"); end
  if (bm[2*8192+48] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 48"); end
  if (bm[2*8192+49] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 49"); end
  if (bm[2*8192+50] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 50"); end
  if (bm[2*8192+51] !== 8'h30) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 51"); end
  if (bm[2*8192+52] !== 8'h12) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 52"); end
  if (bm[2*8192+53] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 53"); end
  if (bm[2*8192+54] !== 8'h17) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 54"); end
  if (bm[2*8192+55] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 55"); end
  if (bm[2*8192+56] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 56"); end
  if (bm[2*8192+57] !== 8'h54) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 57"); end
  if (bm[2*8192+58] !== 8'h36) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 58"); end
  if (bm[2*8192+59] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 59"); end
  if (bm[2*8192+60] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 60"); end
  if (bm[2*8192+61] !== 8'h61) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 61"); end
  if (bm[2*8192+62] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 62"); end
  if (bm[2*8192+63] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 63"); end
  if (bm[2*8192+64] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 64"); end
  if (bm[2*8192+65] !== 8'h42) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 65"); end
  if (bm[2*8192+66] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 66"); end
  if (bm[2*8192+67] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 67"); end
  if (bm[2*8192+68] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 68"); end
  if (bm[2*8192+69] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 69"); end
  if (bm[2*8192+70] !== 8'h58) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 70"); end
  if (bm[2*8192+71] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 71"); end
  if (bm[2*8192+72] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 72"); end
  if (bm[2*8192+73] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 73"); end
  if (bm[2*8192+74] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 74"); end
  if (bm[2*8192+75] !== 8'h87) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 75"); end
  if (bm[2*8192+76] !== 8'h71) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 76"); end
  if (bm[2*8192+77] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 77"); end
  if (bm[2*8192+78] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 78"); end
  if (bm[2*8192+79] !== 8'h07) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 79"); end
  if (bm[2*8192+80] !== 8'h66) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 80"); end
  if (bm[2*8192+81] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 81"); end
  if (bm[2*8192+82] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 82"); end
  if (bm[2*8192+83] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 83"); end
  if (bm[2*8192+84] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 84"); end
  if (bm[2*8192+85] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 85"); end
  if (bm[2*8192+86] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 86"); end
  if (bm[2*8192+87] !== 8'h62) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 87"); end
  if (bm[2*8192+88] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 88"); end
  if (bm[2*8192+89] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 89"); end
  if (bm[2*8192+90] !== 8'h87) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 90"); end
  if (bm[2*8192+91] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 91"); end
  if (bm[2*8192+92] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 92"); end
  if (bm[2*8192+93] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 93"); end
  if (bm[2*8192+94] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 94"); end
  if (bm[2*8192+95] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 95"); end
  if (bm[2*8192+96] !== 8'h77) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 96"); end
  if (bm[2*8192+97] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 97"); end
  if (bm[2*8192+98] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 98"); end
  if (bm[2*8192+99] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 99"); end
  if (bm[2*8192+100] !== 8'h66) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 100"); end
  if (bm[2*8192+101] !== 8'h68) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 101"); end
  if (bm[2*8192+102] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 102"); end
  if (bm[2*8192+103] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 103"); end
  if (bm[2*8192+104] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 104"); end
  if (bm[2*8192+105] !== 8'h52) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 105"); end
  if (bm[2*8192+106] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 106"); end
  if (bm[2*8192+107] !== 8'h48) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 107"); end
  if (bm[2*8192+108] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 108"); end
  if (bm[2*8192+109] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 109"); end
  if (bm[2*8192+110] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 110"); end
  if (bm[2*8192+111] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 111"); end
  if (bm[2*8192+112] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 112"); end
  if (bm[2*8192+113] !== 8'h66) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 113"); end
  if (bm[2*8192+114] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 114"); end
  if (bm[2*8192+115] !== 8'h07) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 115"); end
  if (bm[2*8192+116] !== 8'h47) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 116"); end
  if (bm[2*8192+117] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 117"); end
  if (bm[2*8192+118] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 118"); end
  if (bm[2*8192+119] !== 8'h07) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 119"); end
  if (bm[2*8192+120] !== 8'h48) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 120"); end
  if (bm[2*8192+121] !== 8'h54) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 121"); end
  if (bm[2*8192+122] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 122"); end
  if (bm[2*8192+123] !== 8'h24) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 123"); end
  if (bm[2*8192+124] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 124"); end
  if (bm[2*8192+125] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 125"); end
  if (bm[2*8192+126] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 126"); end
  if (bm[2*8192+127] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pketa4 byte 127"); end
  expv = 8192'h00008580fffee3d2ffff317f0001c90f0001bf1c00002fb1000086de0000b6e3fffe621affff5d4f00001be7ffff6a61fffe9225ffff1a15ffff17c4fffe3d9cfffebc9600008414fffe8f44ffff5e1dffffa21200004e9bfffec7f600018267ffff5c0d0000649e0000c11afffe5186fffecd8e00016d5800008520ffffd1bdffff3d2b0000af14ffffec01ffff45ea00007a07fffe3dabffff09d5000142b9ffff854c000182deffffcf30ffff637bffff54a60001b6c0000065baffff0eb20001459000008d61ffff00f3ffff7c490001e0c9000185ee0001baa5fffedfc60000dd72fffeb0790000e8110000c5b8ffff4be80000f6bf0001bea7fffe7d5cfffea0c7ffff1e920000eecb0000a14c00012ea400008b9dffff3053fffe230800000c3dfffe8005ffff43bc0001f596fffecf460001d4ecffff9d33ffffb6f5000184af00000bcfffff1c670000809f000043ec00011ff2ffffc678000135deffff5c240001549300004f16000196c300015f31000010aefffe9ba20000f15effffdd55ffffc305ffff22300000c7050000fd110001b14100009bfdfffe7ded0000ad400001bf71000016d7000116ec00005dacffff8805000186abfffe902a00003a510000cca9000048ddffff64580001cff6ffff4ff4000195110001be0200017fdd00011dd3fffefdbf000146190000371f0001f6cffffecb81fffed396ffffe5e7fffecfe700001eed00016b36ffff6b3cfffe7a490000bca7000118b70000160800000c00000006890000bab7fffe2d5affff5e49000182e0000012fe00009940fffe946b00019d0d0000305c000142dcffff1775fffedfa6fffe3ae4ffff559f0001fea70000296c0001411500017311fffe0594ffff9baf00003d64fffe4f7f0001f1fafffe80bbffff397a00006fc3ffff2f50ffff71bbfffed2760000f0bf0000e5f500018e9bffff5a20000002210001419c0001c589ffff1af2ffff07ec00011b11fffe375b00012f370000ef48000181880000c996fffffdf60000fb6b00015a1e00013735fffe698e0000fed1ffff0395fffe74ff00000e0d0000abda0001f24dfffe4588ffff8787fffe70a1fffe4a85ffffa80200017d450000abb400002d08000119f1000068fe0001aad70001c014ffff879bffff57f7000130e0fffff03fffffc24700008ee0fffe438effff6ea80001daf90001124bffff68450001107affff4455fffe12b200006b3bfffecba10000ff8500002663fffeafaa0001a8900001e9410001824200000b72fffee560ffff3aa2000014c400002e110001e07f0001acfcfffe9ffe00009f980000ea3700019813000170170000ebecffff5fa5ffff05ee000094e20001b8bbffff8298ffffaffafffe41510000ab9fffff582cffff51cafffff56f0001ecd0ffff85d60000bfa10001ee77;
  for (i=0;i<256;i=i+1) pm.mem[3*256+i] = expv[32*i +: 32];
  go(3,3,1,300,0,0,0,80,0); $display("pkz17: %0d clk", cyc-c0); n=n+1;
  if (bm[1*8192+300] !== 8'h89) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 0"); end
  if (bm[1*8192+301] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 1"); end
  if (bm[1*8192+302] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 2"); end
  if (bm[1*8192+303] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 3"); end
  if (bm[1*8192+304] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 4"); end
  if (bm[1*8192+305] !== 8'ha2) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 5"); end
  if (bm[1*8192+306] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 6"); end
  if (bm[1*8192+307] !== 8'hcc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 7"); end
  if (bm[1*8192+308] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 8"); end
  if (bm[1*8192+309] !== 8'h91) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 9"); end
  if (bm[1*8192+310] !== 8'h0a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 10"); end
  if (bm[1*8192+311] !== 8'hda) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 11"); end
  if (bm[1*8192+312] !== 8'hb8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 12"); end
  if (bm[1*8192+313] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 13"); end
  if (bm[1*8192+314] !== 8'h7d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 14"); end
  if (bm[1*8192+315] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 15"); end
  if (bm[1*8192+316] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 16"); end
  if (bm[1*8192+317] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 17"); end
  if (bm[1*8192+318] !== 8'haf) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 18"); end
  if (bm[1*8192+319] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 19"); end
  if (bm[1*8192+320] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 20"); end
  if (bm[1*8192+321] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 21"); end
  if (bm[1*8192+322] !== 8'h89) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 22"); end
  if (bm[1*8192+323] !== 8'hd6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 23"); end
  if (bm[1*8192+324] !== 8'h67) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 24"); end
  if (bm[1*8192+325] !== 8'hd1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 25"); end
  if (bm[1*8192+326] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 26"); end
  if (bm[1*8192+327] !== 8'h1e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 27"); end
  if (bm[1*8192+328] !== 8'h6b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 28"); end
  if (bm[1*8192+329] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 29"); end
  if (bm[1*8192+330] !== 8'he8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 30"); end
  if (bm[1*8192+331] !== 8'hbb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 31"); end
  if (bm[1*8192+332] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 32"); end
  if (bm[1*8192+333] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 33"); end
  if (bm[1*8192+334] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 34"); end
  if (bm[1*8192+335] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 35"); end
  if (bm[1*8192+336] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 36"); end
  if (bm[1*8192+337] !== 8'h8f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 37"); end
  if (bm[1*8192+338] !== 8'hb4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 38"); end
  if (bm[1*8192+339] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 39"); end
  if (bm[1*8192+340] !== 8'h91) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 40"); end
  if (bm[1*8192+341] !== 8'h5c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 41"); end
  if (bm[1*8192+342] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 42"); end
  if (bm[1*8192+343] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 43"); end
  if (bm[1*8192+344] !== 8'h58) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 44"); end
  if (bm[1*8192+345] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 45"); end
  if (bm[1*8192+346] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 46"); end
  if (bm[1*8192+347] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 47"); end
  if (bm[1*8192+348] !== 8'h4c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 48"); end
  if (bm[1*8192+349] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 49"); end
  if (bm[1*8192+350] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 50"); end
  if (bm[1*8192+351] !== 8'hc1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 51"); end
  if (bm[1*8192+352] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 52"); end
  if (bm[1*8192+353] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 53"); end
  if (bm[1*8192+354] !== 8'h3c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 54"); end
  if (bm[1*8192+355] !== 8'heb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 55"); end
  if (bm[1*8192+356] !== 8'h79) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 56"); end
  if (bm[1*8192+357] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 57"); end
  if (bm[1*8192+358] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 58"); end
  if (bm[1*8192+359] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 59"); end
  if (bm[1*8192+360] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 60"); end
  if (bm[1*8192+361] !== 8'h23) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 61"); end
  if (bm[1*8192+362] !== 8'h7d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 62"); end
  if (bm[1*8192+363] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 63"); end
  if (bm[1*8192+364] !== 8'h7d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 64"); end
  if (bm[1*8192+365] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 65"); end
  if (bm[1*8192+366] !== 8'h5a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 66"); end
  if (bm[1*8192+367] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 67"); end
  if (bm[1*8192+368] !== 8'h77) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 68"); end
  if (bm[1*8192+369] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 69"); end
  if (bm[1*8192+370] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 70"); end
  if (bm[1*8192+371] !== 8'hd4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 71"); end
  if (bm[1*8192+372] !== 8'h9d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 72"); end
  if (bm[1*8192+373] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 73"); end
  if (bm[1*8192+374] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 74"); end
  if (bm[1*8192+375] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 75"); end
  if (bm[1*8192+376] !== 8'hf4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 76"); end
  if (bm[1*8192+377] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 77"); end
  if (bm[1*8192+378] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 78"); end
  if (bm[1*8192+379] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 79"); end
  if (bm[1*8192+380] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 80"); end
  if (bm[1*8192+381] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 81"); end
  if (bm[1*8192+382] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 82"); end
  if (bm[1*8192+383] !== 8'haf) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 83"); end
  if (bm[1*8192+384] !== 8'hee) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 84"); end
  if (bm[1*8192+385] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 85"); end
  if (bm[1*8192+386] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 86"); end
  if (bm[1*8192+387] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 87"); end
  if (bm[1*8192+388] !== 8'hee) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 88"); end
  if (bm[1*8192+389] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 89"); end
  if (bm[1*8192+390] !== 8'hb5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 90"); end
  if (bm[1*8192+391] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 91"); end
  if (bm[1*8192+392] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 92"); end
  if (bm[1*8192+393] !== 8'h94) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 93"); end
  if (bm[1*8192+394] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 94"); end
  if (bm[1*8192+395] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 95"); end
  if (bm[1*8192+396] !== 8'ha9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 96"); end
  if (bm[1*8192+397] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 97"); end
  if (bm[1*8192+398] !== 8'hef) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 98"); end
  if (bm[1*8192+399] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 99"); end
  if (bm[1*8192+400] !== 8'h71) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 100"); end
  if (bm[1*8192+401] !== 8'he5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 101"); end
  if (bm[1*8192+402] !== 8'hf6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 102"); end
  if (bm[1*8192+403] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 103"); end
  if (bm[1*8192+404] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 104"); end
  if (bm[1*8192+405] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 105"); end
  if (bm[1*8192+406] !== 8'hc8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 106"); end
  if (bm[1*8192+407] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 107"); end
  if (bm[1*8192+408] !== 8'h09) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 108"); end
  if (bm[1*8192+409] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 109"); end
  if (bm[1*8192+410] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 110"); end
  if (bm[1*8192+411] !== 8'he1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 111"); end
  if (bm[1*8192+412] !== 8'hc9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 112"); end
  if (bm[1*8192+413] !== 8'hfe) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 113"); end
  if (bm[1*8192+414] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 114"); end
  if (bm[1*8192+415] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 115"); end
  if (bm[1*8192+416] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 116"); end
  if (bm[1*8192+417] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 117"); end
  if (bm[1*8192+418] !== 8'h97) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 118"); end
  if (bm[1*8192+419] !== 8'h3d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 119"); end
  if (bm[1*8192+420] !== 8'h98) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 120"); end
  if (bm[1*8192+421] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 121"); end
  if (bm[1*8192+422] !== 8'h2f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 122"); end
  if (bm[1*8192+423] !== 8'h1d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 123"); end
  if (bm[1*8192+424] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 124"); end
  if (bm[1*8192+425] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 125"); end
  if (bm[1*8192+426] !== 8'hbb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 126"); end
  if (bm[1*8192+427] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 127"); end
  if (bm[1*8192+428] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 128"); end
  if (bm[1*8192+429] !== 8'h5f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 129"); end
  if (bm[1*8192+430] !== 8'hb9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 130"); end
  if (bm[1*8192+431] !== 8'h57) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 131"); end
  if (bm[1*8192+432] !== 8'hfb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 132"); end
  if (bm[1*8192+433] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 133"); end
  if (bm[1*8192+434] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 134"); end
  if (bm[1*8192+435] !== 8'h79) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 135"); end
  if (bm[1*8192+436] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 136"); end
  if (bm[1*8192+437] !== 8'he2) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 137"); end
  if (bm[1*8192+438] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 138"); end
  if (bm[1*8192+439] !== 8'h3e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 139"); end
  if (bm[1*8192+440] !== 8'hdb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 140"); end
  if (bm[1*8192+441] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 141"); end
  if (bm[1*8192+442] !== 8'h09) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 142"); end
  if (bm[1*8192+443] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 143"); end
  if (bm[1*8192+444] !== 8'hf3) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 144"); end
  if (bm[1*8192+445] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 145"); end
  if (bm[1*8192+446] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 146"); end
  if (bm[1*8192+447] !== 8'h2c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 147"); end
  if (bm[1*8192+448] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 148"); end
  if (bm[1*8192+449] !== 8'hc6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 149"); end
  if (bm[1*8192+450] !== 8'hef) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 150"); end
  if (bm[1*8192+451] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 151"); end
  if (bm[1*8192+452] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 152"); end
  if (bm[1*8192+453] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 153"); end
  if (bm[1*8192+454] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 154"); end
  if (bm[1*8192+455] !== 8'h2f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 155"); end
  if (bm[1*8192+456] !== 8'h23) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 156"); end
  if (bm[1*8192+457] !== 8'h23) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 157"); end
  if (bm[1*8192+458] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 158"); end
  if (bm[1*8192+459] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 159"); end
  if (bm[1*8192+460] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 160"); end
  if (bm[1*8192+461] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 161"); end
  if (bm[1*8192+462] !== 8'h0a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 162"); end
  if (bm[1*8192+463] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 163"); end
  if (bm[1*8192+464] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 164"); end
  if (bm[1*8192+465] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 165"); end
  if (bm[1*8192+466] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 166"); end
  if (bm[1*8192+467] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 167"); end
  if (bm[1*8192+468] !== 8'h07) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 168"); end
  if (bm[1*8192+469] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 169"); end
  if (bm[1*8192+470] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 170"); end
  if (bm[1*8192+471] !== 8'hc9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 171"); end
  if (bm[1*8192+472] !== 8'hd0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 172"); end
  if (bm[1*8192+473] !== 8'h94) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 173"); end
  if (bm[1*8192+474] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 174"); end
  if (bm[1*8192+475] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 175"); end
  if (bm[1*8192+476] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 176"); end
  if (bm[1*8192+477] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 177"); end
  if (bm[1*8192+478] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 178"); end
  if (bm[1*8192+479] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 179"); end
  if (bm[1*8192+480] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 180"); end
  if (bm[1*8192+481] !== 8'he5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 181"); end
  if (bm[1*8192+482] !== 8'hde) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 182"); end
  if (bm[1*8192+483] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 183"); end
  if (bm[1*8192+484] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 184"); end
  if (bm[1*8192+485] !== 8'he6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 185"); end
  if (bm[1*8192+486] !== 8'hcb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 186"); end
  if (bm[1*8192+487] !== 8'h77) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 187"); end
  if (bm[1*8192+488] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 188"); end
  if (bm[1*8192+489] !== 8'he0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 189"); end
  if (bm[1*8192+490] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 190"); end
  if (bm[1*8192+491] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 191"); end
  if (bm[1*8192+492] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 192"); end
  if (bm[1*8192+493] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 193"); end
  if (bm[1*8192+494] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 194"); end
  if (bm[1*8192+495] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 195"); end
  if (bm[1*8192+496] !== 8'hd0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 196"); end
  if (bm[1*8192+497] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 197"); end
  if (bm[1*8192+498] !== 8'h8a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 198"); end
  if (bm[1*8192+499] !== 8'h2d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 199"); end
  if (bm[1*8192+500] !== 8'h17) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 200"); end
  if (bm[1*8192+501] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 201"); end
  if (bm[1*8192+502] !== 8'h0a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 202"); end
  if (bm[1*8192+503] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 203"); end
  if (bm[1*8192+504] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 204"); end
  if (bm[1*8192+505] !== 8'h0f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 205"); end
  if (bm[1*8192+506] !== 8'h64) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 206"); end
  if (bm[1*8192+507] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 207"); end
  if (bm[1*8192+508] !== 8'hc6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 208"); end
  if (bm[1*8192+509] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 209"); end
  if (bm[1*8192+510] !== 8'hfd) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 210"); end
  if (bm[1*8192+511] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 211"); end
  if (bm[1*8192+512] !== 8'he0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 212"); end
  if (bm[1*8192+513] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 213"); end
  if (bm[1*8192+514] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 214"); end
  if (bm[1*8192+515] !== 8'hec) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 215"); end
  if (bm[1*8192+516] !== 8'h9c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 216"); end
  if (bm[1*8192+517] !== 8'hc2) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 217"); end
  if (bm[1*8192+518] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 218"); end
  if (bm[1*8192+519] !== 8'h91) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 219"); end
  if (bm[1*8192+520] !== 8'hc9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 220"); end
  if (bm[1*8192+521] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 221"); end
  if (bm[1*8192+522] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 222"); end
  if (bm[1*8192+523] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 223"); end
  if (bm[1*8192+524] !== 8'h23) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 224"); end
  if (bm[1*8192+525] !== 8'heb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 225"); end
  if (bm[1*8192+526] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 226"); end
  if (bm[1*8192+527] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 227"); end
  if (bm[1*8192+528] !== 8'h5a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 228"); end
  if (bm[1*8192+529] !== 8'h97) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 229"); end
  if (bm[1*8192+530] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 230"); end
  if (bm[1*8192+531] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 231"); end
  if (bm[1*8192+532] !== 8'h98) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 232"); end
  if (bm[1*8192+533] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 233"); end
  if (bm[1*8192+534] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 234"); end
  if (bm[1*8192+535] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 235"); end
  if (bm[1*8192+536] !== 8'h6b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 236"); end
  if (bm[1*8192+537] !== 8'h81) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 237"); end
  if (bm[1*8192+538] !== 8'hbc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 238"); end
  if (bm[1*8192+539] !== 8'h88) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 239"); end
  if (bm[1*8192+540] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 240"); end
  if (bm[1*8192+541] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 241"); end
  if (bm[1*8192+542] !== 8'h2f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 242"); end
  if (bm[1*8192+543] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 243"); end
  if (bm[1*8192+544] !== 8'hcf) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 244"); end
  if (bm[1*8192+545] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 245"); end
  if (bm[1*8192+546] !== 8'h8b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 246"); end
  if (bm[1*8192+547] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 247"); end
  if (bm[1*8192+548] !== 8'hb9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 248"); end
  if (bm[1*8192+549] !== 8'h36) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 249"); end
  if (bm[1*8192+550] !== 8'hb0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 250"); end
  if (bm[1*8192+551] !== 8'h59) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 251"); end
  if (bm[1*8192+552] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 252"); end
  if (bm[1*8192+553] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 253"); end
  if (bm[1*8192+554] !== 8'h81) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 254"); end
  if (bm[1*8192+555] !== 8'hf4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 255"); end
  if (bm[1*8192+556] !== 8'h71) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 256"); end
  if (bm[1*8192+557] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 257"); end
  if (bm[1*8192+558] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 258"); end
  if (bm[1*8192+559] !== 8'ha9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 259"); end
  if (bm[1*8192+560] !== 8'hf4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 260"); end
  if (bm[1*8192+561] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 261"); end
  if (bm[1*8192+562] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 262"); end
  if (bm[1*8192+563] !== 8'hdd) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 263"); end
  if (bm[1*8192+564] !== 8'he5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 264"); end
  if (bm[1*8192+565] !== 8'h07) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 265"); end
  if (bm[1*8192+566] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 266"); end
  if (bm[1*8192+567] !== 8'h1f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 267"); end
  if (bm[1*8192+568] !== 8'h7e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 268"); end
  if (bm[1*8192+569] !== 8'h7a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 269"); end
  if (bm[1*8192+570] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 270"); end
  if (bm[1*8192+571] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 271"); end
  if (bm[1*8192+572] !== 8'h64) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 272"); end
  if (bm[1*8192+573] !== 8'h0d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 273"); end
  if (bm[1*8192+574] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 274"); end
  if (bm[1*8192+575] !== 8'h5b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 275"); end
  if (bm[1*8192+576] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 276"); end
  if (bm[1*8192+577] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 277"); end
  if (bm[1*8192+578] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 278"); end
  if (bm[1*8192+579] !== 8'hca) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 279"); end
  if (bm[1*8192+580] !== 8'h94) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 280"); end
  if (bm[1*8192+581] !== 8'h4c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 281"); end
  if (bm[1*8192+582] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 282"); end
  if (bm[1*8192+583] !== 8'h97) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 283"); end
  if (bm[1*8192+584] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 284"); end
  if (bm[1*8192+585] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 285"); end
  if (bm[1*8192+586] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 286"); end
  if (bm[1*8192+587] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 287"); end
  if (bm[1*8192+588] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 288"); end
  if (bm[1*8192+589] !== 8'h2c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 289"); end
  if (bm[1*8192+590] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 290"); end
  if (bm[1*8192+591] !== 8'hd1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 291"); end
  if (bm[1*8192+592] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 292"); end
  if (bm[1*8192+593] !== 8'h93) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 293"); end
  if (bm[1*8192+594] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 294"); end
  if (bm[1*8192+595] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 295"); end
  if (bm[1*8192+596] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 296"); end
  if (bm[1*8192+597] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 297"); end
  if (bm[1*8192+598] !== 8'hb9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 298"); end
  if (bm[1*8192+599] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 299"); end
  if (bm[1*8192+600] !== 8'h09) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 300"); end
  if (bm[1*8192+601] !== 8'hdc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 301"); end
  if (bm[1*8192+602] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 302"); end
  if (bm[1*8192+603] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 303"); end
  if (bm[1*8192+604] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 304"); end
  if (bm[1*8192+605] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 305"); end
  if (bm[1*8192+606] !== 8'hfe) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 306"); end
  if (bm[1*8192+607] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 307"); end
  if (bm[1*8192+608] !== 8'hbc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 308"); end
  if (bm[1*8192+609] !== 8'hab) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 309"); end
  if (bm[1*8192+610] !== 8'hc1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 310"); end
  if (bm[1*8192+611] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 311"); end
  if (bm[1*8192+612] !== 8'hab) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 312"); end
  if (bm[1*8192+613] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 313"); end
  if (bm[1*8192+614] !== 8'h0c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 314"); end
  if (bm[1*8192+615] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 315"); end
  if (bm[1*8192+616] !== 8'h9b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 316"); end
  if (bm[1*8192+617] !== 8'h8e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 317"); end
  if (bm[1*8192+618] !== 8'hdc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 318"); end
  if (bm[1*8192+619] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 319"); end
  if (bm[1*8192+620] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 320"); end
  if (bm[1*8192+621] !== 8'hd3) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 321"); end
  if (bm[1*8192+622] !== 8'h6b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 322"); end
  if (bm[1*8192+623] !== 8'h71) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 323"); end
  if (bm[1*8192+624] !== 8'hd6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 324"); end
  if (bm[1*8192+625] !== 8'h6f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 325"); end
  if (bm[1*8192+626] !== 8'h57) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 326"); end
  if (bm[1*8192+627] !== 8'he5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 327"); end
  if (bm[1*8192+628] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 328"); end
  if (bm[1*8192+629] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 329"); end
  if (bm[1*8192+630] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 330"); end
  if (bm[1*8192+631] !== 8'h95) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 331"); end
  if (bm[1*8192+632] !== 8'h68) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 332"); end
  if (bm[1*8192+633] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 333"); end
  if (bm[1*8192+634] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 334"); end
  if (bm[1*8192+635] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 335"); end
  if (bm[1*8192+636] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 336"); end
  if (bm[1*8192+637] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 337"); end
  if (bm[1*8192+638] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 338"); end
  if (bm[1*8192+639] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 339"); end
  if (bm[1*8192+640] !== 8'hb0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 340"); end
  if (bm[1*8192+641] !== 8'h54) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 341"); end
  if (bm[1*8192+642] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 342"); end
  if (bm[1*8192+643] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 343"); end
  if (bm[1*8192+644] !== 8'h0f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 344"); end
  if (bm[1*8192+645] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 345"); end
  if (bm[1*8192+646] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 346"); end
  if (bm[1*8192+647] !== 8'heb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 347"); end
  if (bm[1*8192+648] !== 8'hc4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 348"); end
  if (bm[1*8192+649] !== 8'hbb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 349"); end
  if (bm[1*8192+650] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 350"); end
  if (bm[1*8192+651] !== 8'hfb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 351"); end
  if (bm[1*8192+652] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 352"); end
  if (bm[1*8192+653] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 353"); end
  if (bm[1*8192+654] !== 8'h77) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 354"); end
  if (bm[1*8192+655] !== 8'hbb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 355"); end
  if (bm[1*8192+656] !== 8'hcf) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 356"); end
  if (bm[1*8192+657] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 357"); end
  if (bm[1*8192+658] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 358"); end
  if (bm[1*8192+659] !== 8'h88) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 359"); end
  if (bm[1*8192+660] !== 8'ha2) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 360"); end
  if (bm[1*8192+661] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 361"); end
  if (bm[1*8192+662] !== 8'h79) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 362"); end
  if (bm[1*8192+663] !== 8'h91) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 363"); end
  if (bm[1*8192+664] !== 8'h2d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 364"); end
  if (bm[1*8192+665] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 365"); end
  if (bm[1*8192+666] !== 8'hde) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 366"); end
  if (bm[1*8192+667] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 367"); end
  if (bm[1*8192+668] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 368"); end
  if (bm[1*8192+669] !== 8'h3d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 369"); end
  if (bm[1*8192+670] !== 8'h69) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 370"); end
  if (bm[1*8192+671] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 371"); end
  if (bm[1*8192+672] !== 8'hc3) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 372"); end
  if (bm[1*8192+673] !== 8'hd6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 373"); end
  if (bm[1*8192+674] !== 8'hb6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 374"); end
  if (bm[1*8192+675] !== 8'h0a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 375"); end
  if (bm[1*8192+676] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 376"); end
  if (bm[1*8192+677] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 377"); end
  if (bm[1*8192+678] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 378"); end
  if (bm[1*8192+679] !== 8'hca) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 379"); end
  if (bm[1*8192+680] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 380"); end
  if (bm[1*8192+681] !== 8'he6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 381"); end
  if (bm[1*8192+682] !== 8'he8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 382"); end
  if (bm[1*8192+683] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 383"); end
  if (bm[1*8192+684] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 384"); end
  if (bm[1*8192+685] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 385"); end
  if (bm[1*8192+686] !== 8'h6f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 386"); end
  if (bm[1*8192+687] !== 8'h61) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 387"); end
  if (bm[1*8192+688] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 388"); end
  if (bm[1*8192+689] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 389"); end
  if (bm[1*8192+690] !== 8'h8e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 390"); end
  if (bm[1*8192+691] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 391"); end
  if (bm[1*8192+692] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 392"); end
  if (bm[1*8192+693] !== 8'h5f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 393"); end
  if (bm[1*8192+694] !== 8'hd4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 394"); end
  if (bm[1*8192+695] !== 8'h1e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 395"); end
  if (bm[1*8192+696] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 396"); end
  if (bm[1*8192+697] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 397"); end
  if (bm[1*8192+698] !== 8'h36) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 398"); end
  if (bm[1*8192+699] !== 8'h8b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 399"); end
  if (bm[1*8192+700] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 400"); end
  if (bm[1*8192+701] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 401"); end
  if (bm[1*8192+702] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 402"); end
  if (bm[1*8192+703] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 403"); end
  if (bm[1*8192+704] !== 8'hcc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 404"); end
  if (bm[1*8192+705] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 405"); end
  if (bm[1*8192+706] !== 8'h0a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 406"); end
  if (bm[1*8192+707] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 407"); end
  if (bm[1*8192+708] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 408"); end
  if (bm[1*8192+709] !== 8'hba) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 409"); end
  if (bm[1*8192+710] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 410"); end
  if (bm[1*8192+711] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 411"); end
  if (bm[1*8192+712] !== 8'hf0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 412"); end
  if (bm[1*8192+713] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 413"); end
  if (bm[1*8192+714] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 414"); end
  if (bm[1*8192+715] !== 8'hdc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 415"); end
  if (bm[1*8192+716] !== 8'hb7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 416"); end
  if (bm[1*8192+717] !== 8'h3e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 417"); end
  if (bm[1*8192+718] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 418"); end
  if (bm[1*8192+719] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 419"); end
  if (bm[1*8192+720] !== 8'h17) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 420"); end
  if (bm[1*8192+721] !== 8'h57) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 421"); end
  if (bm[1*8192+722] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 422"); end
  if (bm[1*8192+723] !== 8'hb4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 423"); end
  if (bm[1*8192+724] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 424"); end
  if (bm[1*8192+725] !== 8'hd5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 425"); end
  if (bm[1*8192+726] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 426"); end
  if (bm[1*8192+727] !== 8'he4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 427"); end
  if (bm[1*8192+728] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 428"); end
  if (bm[1*8192+729] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 429"); end
  if (bm[1*8192+730] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 430"); end
  if (bm[1*8192+731] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 431"); end
  if (bm[1*8192+732] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 432"); end
  if (bm[1*8192+733] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 433"); end
  if (bm[1*8192+734] !== 8'h67) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 434"); end
  if (bm[1*8192+735] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 435"); end
  if (bm[1*8192+736] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 436"); end
  if (bm[1*8192+737] !== 8'h94) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 437"); end
  if (bm[1*8192+738] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 438"); end
  if (bm[1*8192+739] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 439"); end
  if (bm[1*8192+740] !== 8'had) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 440"); end
  if (bm[1*8192+741] !== 8'h48) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 441"); end
  if (bm[1*8192+742] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 442"); end
  if (bm[1*8192+743] !== 8'hbd) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 443"); end
  if (bm[1*8192+744] !== 8'h5f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 444"); end
  if (bm[1*8192+745] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 445"); end
  if (bm[1*8192+746] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 446"); end
  if (bm[1*8192+747] !== 8'hb4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 447"); end
  if (bm[1*8192+748] !== 8'ha3) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 448"); end
  if (bm[1*8192+749] !== 8'h48) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 449"); end
  if (bm[1*8192+750] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 450"); end
  if (bm[1*8192+751] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 451"); end
  if (bm[1*8192+752] !== 8'h6f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 452"); end
  if (bm[1*8192+753] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 453"); end
  if (bm[1*8192+754] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 454"); end
  if (bm[1*8192+755] !== 8'ha1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 455"); end
  if (bm[1*8192+756] !== 8'hc7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 456"); end
  if (bm[1*8192+757] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 457"); end
  if (bm[1*8192+758] !== 8'h07) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 458"); end
  if (bm[1*8192+759] !== 8'hb7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 459"); end
  if (bm[1*8192+760] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 460"); end
  if (bm[1*8192+761] !== 8'h36) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 461"); end
  if (bm[1*8192+762] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 462"); end
  if (bm[1*8192+763] !== 8'hfb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 463"); end
  if (bm[1*8192+764] !== 8'h29) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 464"); end
  if (bm[1*8192+765] !== 8'h17) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 465"); end
  if (bm[1*8192+766] !== 8'h9c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 466"); end
  if (bm[1*8192+767] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 467"); end
  if (bm[1*8192+768] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 468"); end
  if (bm[1*8192+769] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 469"); end
  if (bm[1*8192+770] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 470"); end
  if (bm[1*8192+771] !== 8'h69) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 471"); end
  if (bm[1*8192+772] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 472"); end
  if (bm[1*8192+773] !== 8'h94) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 473"); end
  if (bm[1*8192+774] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 474"); end
  if (bm[1*8192+775] !== 8'hd6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 475"); end
  if (bm[1*8192+776] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 476"); end
  if (bm[1*8192+777] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 477"); end
  if (bm[1*8192+778] !== 8'h9c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 478"); end
  if (bm[1*8192+779] !== 8'h42) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 479"); end
  if (bm[1*8192+780] !== 8'hc3) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 480"); end
  if (bm[1*8192+781] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 481"); end
  if (bm[1*8192+782] !== 8'hd2) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 482"); end
  if (bm[1*8192+783] !== 8'h07) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 483"); end
  if (bm[1*8192+784] !== 8'had) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 484"); end
  if (bm[1*8192+785] !== 8'h9e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 485"); end
  if (bm[1*8192+786] !== 8'h47) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 486"); end
  if (bm[1*8192+787] !== 8'hbd) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 487"); end
  if (bm[1*8192+788] !== 8'hac) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 488"); end
  if (bm[1*8192+789] !== 8'hd8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 489"); end
  if (bm[1*8192+790] !== 8'h5b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 490"); end
  if (bm[1*8192+791] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 491"); end
  if (bm[1*8192+792] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 492"); end
  if (bm[1*8192+793] !== 8'h7e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 493"); end
  if (bm[1*8192+794] !== 8'h61) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 494"); end
  if (bm[1*8192+795] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 495"); end
  if (bm[1*8192+796] !== 8'hba) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 496"); end
  if (bm[1*8192+797] !== 8'hfe) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 497"); end
  if (bm[1*8192+798] !== 8'h4f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 498"); end
  if (bm[1*8192+799] !== 8'hc8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 499"); end
  if (bm[1*8192+800] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 500"); end
  if (bm[1*8192+801] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 501"); end
  if (bm[1*8192+802] !== 8'hb5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 502"); end
  if (bm[1*8192+803] !== 8'hb0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 503"); end
  if (bm[1*8192+804] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 504"); end
  if (bm[1*8192+805] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 505"); end
  if (bm[1*8192+806] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 506"); end
  if (bm[1*8192+807] !== 8'heb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 507"); end
  if (bm[1*8192+808] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 508"); end
  if (bm[1*8192+809] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 509"); end
  if (bm[1*8192+810] !== 8'h89) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 510"); end
  if (bm[1*8192+811] !== 8'h9c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 511"); end
  if (bm[1*8192+812] !== 8'hcc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 512"); end
  if (bm[1*8192+813] !== 8'h7a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 513"); end
  if (bm[1*8192+814] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 514"); end
  if (bm[1*8192+815] !== 8'h9b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 515"); end
  if (bm[1*8192+816] !== 8'hfb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 516"); end
  if (bm[1*8192+817] !== 8'h24) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 517"); end
  if (bm[1*8192+818] !== 8'hb6) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 518"); end
  if (bm[1*8192+819] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 519"); end
  if (bm[1*8192+820] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 520"); end
  if (bm[1*8192+821] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 521"); end
  if (bm[1*8192+822] !== 8'h99) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 522"); end
  if (bm[1*8192+823] !== 8'h7d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 523"); end
  if (bm[1*8192+824] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 524"); end
  if (bm[1*8192+825] !== 8'he0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 525"); end
  if (bm[1*8192+826] !== 8'h5c) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 526"); end
  if (bm[1*8192+827] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 527"); end
  if (bm[1*8192+828] !== 8'h9b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 528"); end
  if (bm[1*8192+829] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 529"); end
  if (bm[1*8192+830] !== 8'h97) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 530"); end
  if (bm[1*8192+831] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 531"); end
  if (bm[1*8192+832] !== 8'ha1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 532"); end
  if (bm[1*8192+833] !== 8'hf2) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 533"); end
  if (bm[1*8192+834] !== 8'hc2) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 534"); end
  if (bm[1*8192+835] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 535"); end
  if (bm[1*8192+836] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 536"); end
  if (bm[1*8192+837] !== 8'h97) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 537"); end
  if (bm[1*8192+838] !== 8'hda) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 538"); end
  if (bm[1*8192+839] !== 8'hd0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 539"); end
  if (bm[1*8192+840] !== 8'h64) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 540"); end
  if (bm[1*8192+841] !== 8'hc2) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 541"); end
  if (bm[1*8192+842] !== 8'hf3) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 542"); end
  if (bm[1*8192+843] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 543"); end
  if (bm[1*8192+844] !== 8'hbb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 544"); end
  if (bm[1*8192+845] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 545"); end
  if (bm[1*8192+846] !== 8'hee) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 546"); end
  if (bm[1*8192+847] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 547"); end
  if (bm[1*8192+848] !== 8'hdb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 548"); end
  if (bm[1*8192+849] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 549"); end
  if (bm[1*8192+850] !== 8'h95) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 550"); end
  if (bm[1*8192+851] !== 8'h66) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 551"); end
  if (bm[1*8192+852] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 552"); end
  if (bm[1*8192+853] !== 8'h17) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 553"); end
  if (bm[1*8192+854] !== 8'h2b) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 554"); end
  if (bm[1*8192+855] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 555"); end
  if (bm[1*8192+856] !== 8'h79) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 556"); end
  if (bm[1*8192+857] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 557"); end
  if (bm[1*8192+858] !== 8'h1d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 558"); end
  if (bm[1*8192+859] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 559"); end
  if (bm[1*8192+860] !== 8'h89) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 560"); end
  if (bm[1*8192+861] !== 8'he4) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 561"); end
  if (bm[1*8192+862] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 562"); end
  if (bm[1*8192+863] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 563"); end
  if (bm[1*8192+864] !== 8'h1d) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 564"); end
  if (bm[1*8192+865] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 565"); end
  if (bm[1*8192+866] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 566"); end
  if (bm[1*8192+867] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 567"); end
  if (bm[1*8192+868] !== 8'h36) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 568"); end
  if (bm[1*8192+869] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 569"); end
  if (bm[1*8192+870] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 570"); end
  if (bm[1*8192+871] !== 8'heb) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 571"); end
  if (bm[1*8192+872] !== 8'hc2) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 572"); end
  if (bm[1*8192+873] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 573"); end
  if (bm[1*8192+874] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 574"); end
  if (bm[1*8192+875] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkz17 byte 575"); end
  expv = 8192'h00014bb50000e3850003200cfffcfd5d00056d1cfffd69eefffd91620005b2440007d5ff00073d310002c25dfff9d6a2fff8158b0006072b0003d165fff9d581fffb2f1a0000cd180000312800042dccffff289d00049b33fffb11cffffef6a3fffde0a9fffc423200063ffc0007ac95fffc26220002564cfffb3c3900017ded0005089f000631130007311dfffc89020005a961fffd1d04ffff9e680002f3c5fffa19f3fff9cbe7fffba410fffd84d70007a0310000ae7200001652ffff24d6fff86b8a00070290000470ebfffdb6320007aff0ffff0ab900051dbc00013fd30007f522fff8e7ab0006bf62fffd01290003dd55fffc2374fffb30f50005e44b00018c2bfffeaf40fffc2676fffaa5f200058c68fffb0260fffbbe6ffffb5a30fff854d4fffb4154fffdfee100074cb500057a7d00009f17fffc5019fffb028c00008b55ffffd140fffe666800032833fffc9342fffa70270004503fffff6c18fffeb0f00007613b0003922e000143b7ffff080400057cbefffc23d600027ac1000344e50007c793fff897ccfffc1a0bfff8d2590004c0f50005f60dfffa2c0b0002c9fc00078ab20005e0ac00014efb00048554ffff2627000380af00068f3d00069ee5000100cbfff8fb91000036b7fffa23f600021deafffdf0dffffe3bcd0000b69f00048ab40004a3a2000056e4fffb11f6ffff952afffb740afffbd8d90001acfafffd075e0005a120fffc528400019a950004b28cfffefb2f0004218800029c41fff8a8840000be3100043888000300adfffeb480fffca8defff90385fffc02b30001519400071f72fffbb133fffd609ffffd3f8dfffe56eb0005a35dfffe0083fffa0047fffcde00ffff583b0001e814fff8db040004b2320006fd3c000321aefff9c894ffff9a2bfffcd9eafff8c1920007398effff80d3000053e9ffff002e0007c4520003c91cfffc91410005db6e00024fbd00079eb5fffe2909ffff161600078e64fffe0e520000ba42fffe2974000361570001814d0000cd0c0007734500069291000636fd00045fd1fffa409ffffecece00049de800012b880006895f0004921f00059850fffac437fffa931900018d5ffffed3d9000070d2fffc0371000088e6fffa2171fffd555efffd6bbcfffd40b2ffff5c73ffff58e3fffb2ca90004ebbffffca16100075eccfffa762bfffbb976fffdc360fffbc47900064a28ffffcb1700006576000573fffffed2dafffb5cb80003ccd20005707afffeeb3200056396fffcbcec0000b020fff902630007af0a00035756000123b10004a7b4fffd59d4fffecc66fff960030002555f0007b0ce00072fe70006f16b00054a46000778d2fffa255b0006237efff9ed2300005542fffa1f3500038cbffff8095b00004355000635e4fff825adfff9d8610001e682000018a900014ace;
  for (i=0;i<256;i=i+1) pm.mem[3*256+i] = expv[32*i +: 32];
  go(3,3,1,300,0,1,0,80,0); $display("pkz19: %0d clk", cyc-c0); n=n+1;
  if (bm[1*8192+300] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 0"); end
  if (bm[1*8192+301] !== 8'hb5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 1"); end
  if (bm[1*8192+302] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 2"); end
  if (bm[1*8192+303] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 3"); end
  if (bm[1*8192+304] !== 8'h7e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 4"); end
  if (bm[1*8192+305] !== 8'h7e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 5"); end
  if (bm[1*8192+306] !== 8'h19) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 6"); end
  if (bm[1*8192+307] !== 8'hf6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 7"); end
  if (bm[1*8192+308] !== 8'h79) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 8"); end
  if (bm[1*8192+309] !== 8'he2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 9"); end
  if (bm[1*8192+310] !== 8'h53) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 10"); end
  if (bm[1*8192+311] !== 8'hda) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 11"); end
  if (bm[1*8192+312] !== 8'hcf) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 12"); end
  if (bm[1*8192+313] !== 8'ha1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 13"); end
  if (bm[1*8192+314] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 14"); end
  if (bm[1*8192+315] !== 8'hab) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 15"); end
  if (bm[1*8192+316] !== 8'hbc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 16"); end
  if (bm[1*8192+317] !== 8'h57) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 17"); end
  if (bm[1*8192+318] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 18"); end
  if (bm[1*8192+319] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 19"); end
  if (bm[1*8192+320] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 20"); end
  if (bm[1*8192+321] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 21"); end
  if (bm[1*8192+322] !== 8'hb4) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 22"); end
  if (bm[1*8192+323] !== 8'h0c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 23"); end
  if (bm[1*8192+324] !== 8'hde) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 24"); end
  if (bm[1*8192+325] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 25"); end
  if (bm[1*8192+326] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 26"); end
  if (bm[1*8192+327] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 27"); end
  if (bm[1*8192+328] !== 8'h2d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 28"); end
  if (bm[1*8192+329] !== 8'he1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 29"); end
  if (bm[1*8192+330] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 30"); end
  if (bm[1*8192+331] !== 8'hdc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 31"); end
  if (bm[1*8192+332] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 32"); end
  if (bm[1*8192+333] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 33"); end
  if (bm[1*8192+334] !== 8'hdd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 34"); end
  if (bm[1*8192+335] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 35"); end
  if (bm[1*8192+336] !== 8'h87) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 36"); end
  if (bm[1*8192+337] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 37"); end
  if (bm[1*8192+338] !== 8'h5b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 38"); end
  if (bm[1*8192+339] !== 8'h2b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 39"); end
  if (bm[1*8192+340] !== 8'h95) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 40"); end
  if (bm[1*8192+341] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 41"); end
  if (bm[1*8192+342] !== 8'h91) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 42"); end
  if (bm[1*8192+343] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 43"); end
  if (bm[1*8192+344] !== 8'h0d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 44"); end
  if (bm[1*8192+345] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 45"); end
  if (bm[1*8192+346] !== 8'h4f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 46"); end
  if (bm[1*8192+347] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 47"); end
  if (bm[1*8192+348] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 48"); end
  if (bm[1*8192+349] !== 8'h5a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 49"); end
  if (bm[1*8192+350] !== 8'hfd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 50"); end
  if (bm[1*8192+351] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 51"); end
  if (bm[1*8192+352] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 52"); end
  if (bm[1*8192+353] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 53"); end
  if (bm[1*8192+354] !== 8'h93) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 54"); end
  if (bm[1*8192+355] !== 8'h2c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 55"); end
  if (bm[1*8192+356] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 56"); end
  if (bm[1*8192+357] !== 8'hca) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 57"); end
  if (bm[1*8192+358] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 58"); end
  if (bm[1*8192+359] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 59"); end
  if (bm[1*8192+360] !== 8'h4f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 60"); end
  if (bm[1*8192+361] !== 8'hdc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 61"); end
  if (bm[1*8192+362] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 62"); end
  if (bm[1*8192+363] !== 8'h8a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 63"); end
  if (bm[1*8192+364] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 64"); end
  if (bm[1*8192+365] !== 8'hf6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 65"); end
  if (bm[1*8192+366] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 66"); end
  if (bm[1*8192+367] !== 8'hd0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 67"); end
  if (bm[1*8192+368] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 68"); end
  if (bm[1*8192+369] !== 8'hef) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 69"); end
  if (bm[1*8192+370] !== 8'he0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 70"); end
  if (bm[1*8192+371] !== 8'h4f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 71"); end
  if (bm[1*8192+372] !== 8'h47) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 72"); end
  if (bm[1*8192+373] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 73"); end
  if (bm[1*8192+374] !== 8'hb4) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 74"); end
  if (bm[1*8192+375] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 75"); end
  if (bm[1*8192+376] !== 8'h9c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 76"); end
  if (bm[1*8192+377] !== 8'he2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 77"); end
  if (bm[1*8192+378] !== 8'h4c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 78"); end
  if (bm[1*8192+379] !== 8'h91) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 79"); end
  if (bm[1*8192+380] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 80"); end
  if (bm[1*8192+381] !== 8'h8f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 81"); end
  if (bm[1*8192+382] !== 8'he2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 82"); end
  if (bm[1*8192+383] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 83"); end
  if (bm[1*8192+384] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 84"); end
  if (bm[1*8192+385] !== 8'h48) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 85"); end
  if (bm[1*8192+386] !== 8'ha3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 86"); end
  if (bm[1*8192+387] !== 8'h6c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 87"); end
  if (bm[1*8192+388] !== 8'hd2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 88"); end
  if (bm[1*8192+389] !== 8'h92) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 89"); end
  if (bm[1*8192+390] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 90"); end
  if (bm[1*8192+391] !== 8'h8c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 91"); end
  if (bm[1*8192+392] !== 8'ha2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 92"); end
  if (bm[1*8192+393] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 93"); end
  if (bm[1*8192+394] !== 8'h79) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 94"); end
  if (bm[1*8192+395] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 95"); end
  if (bm[1*8192+396] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 96"); end
  if (bm[1*8192+397] !== 8'h88) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 97"); end
  if (bm[1*8192+398] !== 8'h5d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 98"); end
  if (bm[1*8192+399] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 99"); end
  if (bm[1*8192+400] !== 8'h87) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 100"); end
  if (bm[1*8192+401] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 101"); end
  if (bm[1*8192+402] !== 8'h0c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 102"); end
  if (bm[1*8192+403] !== 8'hca) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 103"); end
  if (bm[1*8192+404] !== 8'ha3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 104"); end
  if (bm[1*8192+405] !== 8'h8a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 105"); end
  if (bm[1*8192+406] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 106"); end
  if (bm[1*8192+407] !== 8'h5c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 107"); end
  if (bm[1*8192+408] !== 8'h9d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 108"); end
  if (bm[1*8192+409] !== 8'hd8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 109"); end
  if (bm[1*8192+410] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 110"); end
  if (bm[1*8192+411] !== 8'ha1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 111"); end
  if (bm[1*8192+412] !== 8'hf0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 112"); end
  if (bm[1*8192+413] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 113"); end
  if (bm[1*8192+414] !== 8'hb5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 114"); end
  if (bm[1*8192+415] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 115"); end
  if (bm[1*8192+416] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 116"); end
  if (bm[1*8192+417] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 117"); end
  if (bm[1*8192+418] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 118"); end
  if (bm[1*8192+419] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 119"); end
  if (bm[1*8192+420] !== 8'h1d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 120"); end
  if (bm[1*8192+421] !== 8'ha7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 121"); end
  if (bm[1*8192+422] !== 8'hd8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 122"); end
  if (bm[1*8192+423] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 123"); end
  if (bm[1*8192+424] !== 8'h8a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 124"); end
  if (bm[1*8192+425] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 125"); end
  if (bm[1*8192+426] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 126"); end
  if (bm[1*8192+427] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 127"); end
  if (bm[1*8192+428] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 128"); end
  if (bm[1*8192+429] !== 8'ha9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 129"); end
  if (bm[1*8192+430] !== 8'ha2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 130"); end
  if (bm[1*8192+431] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 131"); end
  if (bm[1*8192+432] !== 8'hfa) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 132"); end
  if (bm[1*8192+433] !== 8'he8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 133"); end
  if (bm[1*8192+434] !== 8'hdd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 134"); end
  if (bm[1*8192+435] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 135"); end
  if (bm[1*8192+436] !== 8'h77) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 136"); end
  if (bm[1*8192+437] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 137"); end
  if (bm[1*8192+438] !== 8'hc8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 138"); end
  if (bm[1*8192+439] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 139"); end
  if (bm[1*8192+440] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 140"); end
  if (bm[1*8192+441] !== 8'h8f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 141"); end
  if (bm[1*8192+442] !== 8'h77) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 142"); end
  if (bm[1*8192+443] !== 8'hc2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 143"); end
  if (bm[1*8192+444] !== 8'h92) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 144"); end
  if (bm[1*8192+445] !== 8'ha1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 145"); end
  if (bm[1*8192+446] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 146"); end
  if (bm[1*8192+447] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 147"); end
  if (bm[1*8192+448] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 148"); end
  if (bm[1*8192+449] !== 8'hd6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 149"); end
  if (bm[1*8192+450] !== 8'hc9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 150"); end
  if (bm[1*8192+451] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 151"); end
  if (bm[1*8192+452] !== 8'h0d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 152"); end
  if (bm[1*8192+453] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 153"); end
  if (bm[1*8192+454] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 154"); end
  if (bm[1*8192+455] !== 8'he1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 155"); end
  if (bm[1*8192+456] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 156"); end
  if (bm[1*8192+457] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 157"); end
  if (bm[1*8192+458] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 158"); end
  if (bm[1*8192+459] !== 8'h17) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 159"); end
  if (bm[1*8192+460] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 160"); end
  if (bm[1*8192+461] !== 8'hd4) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 161"); end
  if (bm[1*8192+462] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 162"); end
  if (bm[1*8192+463] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 163"); end
  if (bm[1*8192+464] !== 8'h36) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 164"); end
  if (bm[1*8192+465] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 165"); end
  if (bm[1*8192+466] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 166"); end
  if (bm[1*8192+467] !== 8'h19) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 167"); end
  if (bm[1*8192+468] !== 8'hf6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 168"); end
  if (bm[1*8192+469] !== 8'hdb) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 169"); end
  if (bm[1*8192+470] !== 8'h2f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 170"); end
  if (bm[1*8192+471] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 171"); end
  if (bm[1*8192+472] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 172"); end
  if (bm[1*8192+473] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 173"); end
  if (bm[1*8192+474] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 174"); end
  if (bm[1*8192+475] !== 8'h6f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 175"); end
  if (bm[1*8192+476] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 176"); end
  if (bm[1*8192+477] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 177"); end
  if (bm[1*8192+478] !== 8'hcb) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 178"); end
  if (bm[1*8192+479] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 179"); end
  if (bm[1*8192+480] !== 8'hf4) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 180"); end
  if (bm[1*8192+481] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 181"); end
  if (bm[1*8192+482] !== 8'h37) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 182"); end
  if (bm[1*8192+483] !== 8'heb) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 183"); end
  if (bm[1*8192+484] !== 8'h67) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 184"); end
  if (bm[1*8192+485] !== 8'ha9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 185"); end
  if (bm[1*8192+486] !== 8'h9e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 186"); end
  if (bm[1*8192+487] !== 8'hc4) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 187"); end
  if (bm[1*8192+488] !== 8'h68) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 188"); end
  if (bm[1*8192+489] !== 8'h9d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 189"); end
  if (bm[1*8192+490] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 190"); end
  if (bm[1*8192+491] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 191"); end
  if (bm[1*8192+492] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 192"); end
  if (bm[1*8192+493] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 193"); end
  if (bm[1*8192+494] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 194"); end
  if (bm[1*8192+495] !== 8'h9c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 195"); end
  if (bm[1*8192+496] !== 8'h71) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 196"); end
  if (bm[1*8192+497] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 197"); end
  if (bm[1*8192+498] !== 8'h9e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 198"); end
  if (bm[1*8192+499] !== 8'h8e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 199"); end
  if (bm[1*8192+500] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 200"); end
  if (bm[1*8192+501] !== 8'hd6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 201"); end
  if (bm[1*8192+502] !== 8'hb9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 202"); end
  if (bm[1*8192+503] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 203"); end
  if (bm[1*8192+504] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 204"); end
  if (bm[1*8192+505] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 205"); end
  if (bm[1*8192+506] !== 8'hb0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 206"); end
  if (bm[1*8192+507] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 207"); end
  if (bm[1*8192+508] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 208"); end
  if (bm[1*8192+509] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 209"); end
  if (bm[1*8192+510] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 210"); end
  if (bm[1*8192+511] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 211"); end
  if (bm[1*8192+512] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 212"); end
  if (bm[1*8192+513] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 213"); end
  if (bm[1*8192+514] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 214"); end
  if (bm[1*8192+515] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 215"); end
  if (bm[1*8192+516] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 216"); end
  if (bm[1*8192+517] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 217"); end
  if (bm[1*8192+518] !== 8'hfd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 218"); end
  if (bm[1*8192+519] !== 8'h8f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 219"); end
  if (bm[1*8192+520] !== 8'h17) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 220"); end
  if (bm[1*8192+521] !== 8'hac) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 221"); end
  if (bm[1*8192+522] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 222"); end
  if (bm[1*8192+523] !== 8'hf2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 223"); end
  if (bm[1*8192+524] !== 8'h87) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 224"); end
  if (bm[1*8192+525] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 225"); end
  if (bm[1*8192+526] !== 8'hc6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 226"); end
  if (bm[1*8192+527] !== 8'he0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 227"); end
  if (bm[1*8192+528] !== 8'he6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 228"); end
  if (bm[1*8192+529] !== 8'hf3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 229"); end
  if (bm[1*8192+530] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 230"); end
  if (bm[1*8192+531] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 231"); end
  if (bm[1*8192+532] !== 8'h5b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 232"); end
  if (bm[1*8192+533] !== 8'h5d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 233"); end
  if (bm[1*8192+534] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 234"); end
  if (bm[1*8192+535] !== 8'h6c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 235"); end
  if (bm[1*8192+536] !== 8'h37) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 236"); end
  if (bm[1*8192+537] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 237"); end
  if (bm[1*8192+538] !== 8'he5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 238"); end
  if (bm[1*8192+539] !== 8'h4d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 239"); end
  if (bm[1*8192+540] !== 8'hc4) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 240"); end
  if (bm[1*8192+541] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 241"); end
  if (bm[1*8192+542] !== 8'he1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 242"); end
  if (bm[1*8192+543] !== 8'hdc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 243"); end
  if (bm[1*8192+544] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 244"); end
  if (bm[1*8192+545] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 245"); end
  if (bm[1*8192+546] !== 8'h24) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 246"); end
  if (bm[1*8192+547] !== 8'hcf) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 247"); end
  if (bm[1*8192+548] !== 8'h7e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 248"); end
  if (bm[1*8192+549] !== 8'h61) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 249"); end
  if (bm[1*8192+550] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 250"); end
  if (bm[1*8192+551] !== 8'ha7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 251"); end
  if (bm[1*8192+552] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 252"); end
  if (bm[1*8192+553] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 253"); end
  if (bm[1*8192+554] !== 8'hb2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 254"); end
  if (bm[1*8192+555] !== 8'hb9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 255"); end
  if (bm[1*8192+556] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 256"); end
  if (bm[1*8192+557] !== 8'hdd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 257"); end
  if (bm[1*8192+558] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 258"); end
  if (bm[1*8192+559] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 259"); end
  if (bm[1*8192+560] !== 8'ha3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 260"); end
  if (bm[1*8192+561] !== 8'h5c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 261"); end
  if (bm[1*8192+562] !== 8'h52) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 262"); end
  if (bm[1*8192+563] !== 8'h91) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 263"); end
  if (bm[1*8192+564] !== 8'h9a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 264"); end
  if (bm[1*8192+565] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 265"); end
  if (bm[1*8192+566] !== 8'hc0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 266"); end
  if (bm[1*8192+567] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 267"); end
  if (bm[1*8192+568] !== 8'hf6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 268"); end
  if (bm[1*8192+569] !== 8'ha9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 269"); end
  if (bm[1*8192+570] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 270"); end
  if (bm[1*8192+571] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 271"); end
  if (bm[1*8192+572] !== 8'hec) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 272"); end
  if (bm[1*8192+573] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 273"); end
  if (bm[1*8192+574] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 274"); end
  if (bm[1*8192+575] !== 8'h6c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 275"); end
  if (bm[1*8192+576] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 276"); end
  if (bm[1*8192+577] !== 8'hd6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 277"); end
  if (bm[1*8192+578] !== 8'hd4) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 278"); end
  if (bm[1*8192+579] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 279"); end
  if (bm[1*8192+580] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 280"); end
  if (bm[1*8192+581] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 281"); end
  if (bm[1*8192+582] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 282"); end
  if (bm[1*8192+583] !== 8'h72) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 283"); end
  if (bm[1*8192+584] !== 8'hb5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 284"); end
  if (bm[1*8192+585] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 285"); end
  if (bm[1*8192+586] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 286"); end
  if (bm[1*8192+587] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 287"); end
  if (bm[1*8192+588] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 288"); end
  if (bm[1*8192+589] !== 8'h4f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 289"); end
  if (bm[1*8192+590] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 290"); end
  if (bm[1*8192+591] !== 8'hc7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 291"); end
  if (bm[1*8192+592] !== 8'hf3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 292"); end
  if (bm[1*8192+593] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 293"); end
  if (bm[1*8192+594] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 294"); end
  if (bm[1*8192+595] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 295"); end
  if (bm[1*8192+596] !== 8'h57) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 296"); end
  if (bm[1*8192+597] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 297"); end
  if (bm[1*8192+598] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 298"); end
  if (bm[1*8192+599] !== 8'h56) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 299"); end
  if (bm[1*8192+600] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 300"); end
  if (bm[1*8192+601] !== 8'hde) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 301"); end
  if (bm[1*8192+602] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 302"); end
  if (bm[1*8192+603] !== 8'h4d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 303"); end
  if (bm[1*8192+604] !== 8'h90) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 304"); end
  if (bm[1*8192+605] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 305"); end
  if (bm[1*8192+606] !== 8'h4d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 306"); end
  if (bm[1*8192+607] !== 8'hb3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 307"); end
  if (bm[1*8192+608] !== 8'h56) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 308"); end
  if (bm[1*8192+609] !== 8'h66) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 309"); end
  if (bm[1*8192+610] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 310"); end
  if (bm[1*8192+611] !== 8'had) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 311"); end
  if (bm[1*8192+612] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 312"); end
  if (bm[1*8192+613] !== 8'hee) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 313"); end
  if (bm[1*8192+614] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 314"); end
  if (bm[1*8192+615] !== 8'ha2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 315"); end
  if (bm[1*8192+616] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 316"); end
  if (bm[1*8192+617] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 317"); end
  if (bm[1*8192+618] !== 8'h30) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 318"); end
  if (bm[1*8192+619] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 319"); end
  if (bm[1*8192+620] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 320"); end
  if (bm[1*8192+621] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 321"); end
  if (bm[1*8192+622] !== 8'h6c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 322"); end
  if (bm[1*8192+623] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 323"); end
  if (bm[1*8192+624] !== 8'hc8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 324"); end
  if (bm[1*8192+625] !== 8'hd6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 325"); end
  if (bm[1*8192+626] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 326"); end
  if (bm[1*8192+627] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 327"); end
  if (bm[1*8192+628] !== 8'he0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 328"); end
  if (bm[1*8192+629] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 329"); end
  if (bm[1*8192+630] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 330"); end
  if (bm[1*8192+631] !== 8'ha9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 331"); end
  if (bm[1*8192+632] !== 8'he7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 332"); end
  if (bm[1*8192+633] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 333"); end
  if (bm[1*8192+634] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 334"); end
  if (bm[1*8192+635] !== 8'h4c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 335"); end
  if (bm[1*8192+636] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 336"); end
  if (bm[1*8192+637] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 337"); end
  if (bm[1*8192+638] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 338"); end
  if (bm[1*8192+639] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 339"); end
  if (bm[1*8192+640] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 340"); end
  if (bm[1*8192+641] !== 8'hc4) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 341"); end
  if (bm[1*8192+642] !== 8'h19) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 342"); end
  if (bm[1*8192+643] !== 8'hf2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 343"); end
  if (bm[1*8192+644] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 344"); end
  if (bm[1*8192+645] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 345"); end
  if (bm[1*8192+646] !== 8'he2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 346"); end
  if (bm[1*8192+647] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 347"); end
  if (bm[1*8192+648] !== 8'hc0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 348"); end
  if (bm[1*8192+649] !== 8'hdd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 349"); end
  if (bm[1*8192+650] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 350"); end
  if (bm[1*8192+651] !== 8'hc9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 351"); end
  if (bm[1*8192+652] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 352"); end
  if (bm[1*8192+653] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 353"); end
  if (bm[1*8192+654] !== 8'hf0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 354"); end
  if (bm[1*8192+655] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 355"); end
  if (bm[1*8192+656] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 356"); end
  if (bm[1*8192+657] !== 8'hb6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 357"); end
  if (bm[1*8192+658] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 358"); end
  if (bm[1*8192+659] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 359"); end
  if (bm[1*8192+660] !== 8'hc3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 360"); end
  if (bm[1*8192+661] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 361"); end
  if (bm[1*8192+662] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 362"); end
  if (bm[1*8192+663] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 363"); end
  if (bm[1*8192+664] !== 8'h47) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 364"); end
  if (bm[1*8192+665] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 365"); end
  if (bm[1*8192+666] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 366"); end
  if (bm[1*8192+667] !== 8'hc8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 367"); end
  if (bm[1*8192+668] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 368"); end
  if (bm[1*8192+669] !== 8'h37) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 369"); end
  if (bm[1*8192+670] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 370"); end
  if (bm[1*8192+671] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 371"); end
  if (bm[1*8192+672] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 372"); end
  if (bm[1*8192+673] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 373"); end
  if (bm[1*8192+674] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 374"); end
  if (bm[1*8192+675] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 375"); end
  if (bm[1*8192+676] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 376"); end
  if (bm[1*8192+677] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 377"); end
  if (bm[1*8192+678] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 378"); end
  if (bm[1*8192+679] !== 8'h53) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 379"); end
  if (bm[1*8192+680] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 380"); end
  if (bm[1*8192+681] !== 8'hd3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 381"); end
  if (bm[1*8192+682] !== 8'h3d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 382"); end
  if (bm[1*8192+683] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 383"); end
  if (bm[1*8192+684] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 384"); end
  if (bm[1*8192+685] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 385"); end
  if (bm[1*8192+686] !== 8'h3f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 386"); end
  if (bm[1*8192+687] !== 8'h73) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 387"); end
  if (bm[1*8192+688] !== 8'hda) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 388"); end
  if (bm[1*8192+689] !== 8'hf2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 389"); end
  if (bm[1*8192+690] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 390"); end
  if (bm[1*8192+691] !== 8'he5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 391"); end
  if (bm[1*8192+692] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 392"); end
  if (bm[1*8192+693] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 393"); end
  if (bm[1*8192+694] !== 8'hf6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 394"); end
  if (bm[1*8192+695] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 395"); end
  if (bm[1*8192+696] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 396"); end
  if (bm[1*8192+697] !== 8'hb0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 397"); end
  if (bm[1*8192+698] !== 8'hb1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 398"); end
  if (bm[1*8192+699] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 399"); end
  if (bm[1*8192+700] !== 8'h3f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 400"); end
  if (bm[1*8192+701] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 401"); end
  if (bm[1*8192+702] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 402"); end
  if (bm[1*8192+703] !== 8'hc2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 403"); end
  if (bm[1*8192+704] !== 8'hbd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 404"); end
  if (bm[1*8192+705] !== 8'h42) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 405"); end
  if (bm[1*8192+706] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 406"); end
  if (bm[1*8192+707] !== 8'hc2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 407"); end
  if (bm[1*8192+708] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 408"); end
  if (bm[1*8192+709] !== 8'h8f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 409"); end
  if (bm[1*8192+710] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 410"); end
  if (bm[1*8192+711] !== 8'hbc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 411"); end
  if (bm[1*8192+712] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 412"); end
  if (bm[1*8192+713] !== 8'hdd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 413"); end
  if (bm[1*8192+714] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 414"); end
  if (bm[1*8192+715] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 415"); end
  if (bm[1*8192+716] !== 8'h9e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 416"); end
  if (bm[1*8192+717] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 417"); end
  if (bm[1*8192+718] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 418"); end
  if (bm[1*8192+719] !== 8'h94) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 419"); end
  if (bm[1*8192+720] !== 8'he8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 420"); end
  if (bm[1*8192+721] !== 8'h93) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 421"); end
  if (bm[1*8192+722] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 422"); end
  if (bm[1*8192+723] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 423"); end
  if (bm[1*8192+724] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 424"); end
  if (bm[1*8192+725] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 425"); end
  if (bm[1*8192+726] !== 8'h8f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 426"); end
  if (bm[1*8192+727] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 427"); end
  if (bm[1*8192+728] !== 8'hcb) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 428"); end
  if (bm[1*8192+729] !== 8'hb6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 429"); end
  if (bm[1*8192+730] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 430"); end
  if (bm[1*8192+731] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 431"); end
  if (bm[1*8192+732] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 432"); end
  if (bm[1*8192+733] !== 8'h99) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 433"); end
  if (bm[1*8192+734] !== 8'h99) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 434"); end
  if (bm[1*8192+735] !== 8'hc0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 435"); end
  if (bm[1*8192+736] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 436"); end
  if (bm[1*8192+737] !== 8'hb8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 437"); end
  if (bm[1*8192+738] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 438"); end
  if (bm[1*8192+739] !== 8'h77) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 439"); end
  if (bm[1*8192+740] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 440"); end
  if (bm[1*8192+741] !== 8'hfd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 441"); end
  if (bm[1*8192+742] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 442"); end
  if (bm[1*8192+743] !== 8'hfe) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 443"); end
  if (bm[1*8192+744] !== 8'hba) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 444"); end
  if (bm[1*8192+745] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 445"); end
  if (bm[1*8192+746] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 446"); end
  if (bm[1*8192+747] !== 8'h37) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 447"); end
  if (bm[1*8192+748] !== 8'h58) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 448"); end
  if (bm[1*8192+749] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 449"); end
  if (bm[1*8192+750] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 450"); end
  if (bm[1*8192+751] !== 8'hb3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 451"); end
  if (bm[1*8192+752] !== 8'hf0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 452"); end
  if (bm[1*8192+753] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 453"); end
  if (bm[1*8192+754] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 454"); end
  if (bm[1*8192+755] !== 8'hac) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 455"); end
  if (bm[1*8192+756] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 456"); end
  if (bm[1*8192+757] !== 8'hcc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 457"); end
  if (bm[1*8192+758] !== 8'hb2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 458"); end
  if (bm[1*8192+759] !== 8'hfa) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 459"); end
  if (bm[1*8192+760] !== 8'hd0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 460"); end
  if (bm[1*8192+761] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 461"); end
  if (bm[1*8192+762] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 462"); end
  if (bm[1*8192+763] !== 8'h19) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 463"); end
  if (bm[1*8192+764] !== 8'hc4) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 464"); end
  if (bm[1*8192+765] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 465"); end
  if (bm[1*8192+766] !== 8'hfd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 466"); end
  if (bm[1*8192+767] !== 8'h8c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 467"); end
  if (bm[1*8192+768] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 468"); end
  if (bm[1*8192+769] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 469"); end
  if (bm[1*8192+770] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 470"); end
  if (bm[1*8192+771] !== 8'h5a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 471"); end
  if (bm[1*8192+772] !== 8'had) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 472"); end
  if (bm[1*8192+773] !== 8'h98) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 473"); end
  if (bm[1*8192+774] !== 8'hbd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 474"); end
  if (bm[1*8192+775] !== 8'hc0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 475"); end
  if (bm[1*8192+776] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 476"); end
  if (bm[1*8192+777] !== 8'h59) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 477"); end
  if (bm[1*8192+778] !== 8'h3d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 478"); end
  if (bm[1*8192+779] !== 8'h67) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 479"); end
  if (bm[1*8192+780] !== 8'hb5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 480"); end
  if (bm[1*8192+781] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 481"); end
  if (bm[1*8192+782] !== 8'hb2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 482"); end
  if (bm[1*8192+783] !== 8'hf0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 483"); end
  if (bm[1*8192+784] !== 8'hcc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 484"); end
  if (bm[1*8192+785] !== 8'h8c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 485"); end
  if (bm[1*8192+786] !== 8'hdc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 486"); end
  if (bm[1*8192+787] !== 8'hbb) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 487"); end
  if (bm[1*8192+788] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 488"); end
  if (bm[1*8192+789] !== 8'h42) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 489"); end
  if (bm[1*8192+790] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 490"); end
  if (bm[1*8192+791] !== 8'hfe) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 491"); end
  if (bm[1*8192+792] !== 8'hea) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 492"); end
  if (bm[1*8192+793] !== 8'h09) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 493"); end
  if (bm[1*8192+794] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 494"); end
  if (bm[1*8192+795] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 495"); end
  if (bm[1*8192+796] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 496"); end
  if (bm[1*8192+797] !== 8'hef) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 497"); end
  if (bm[1*8192+798] !== 8'had) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 498"); end
  if (bm[1*8192+799] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 499"); end
  if (bm[1*8192+800] !== 8'h2d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 500"); end
  if (bm[1*8192+801] !== 8'hc0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 501"); end
  if (bm[1*8192+802] !== 8'h46) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 502"); end
  if (bm[1*8192+803] !== 8'h24) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 503"); end
  if (bm[1*8192+804] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 504"); end
  if (bm[1*8192+805] !== 8'h47) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 505"); end
  if (bm[1*8192+806] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 506"); end
  if (bm[1*8192+807] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 507"); end
  if (bm[1*8192+808] !== 8'h01) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 508"); end
  if (bm[1*8192+809] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 509"); end
  if (bm[1*8192+810] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 510"); end
  if (bm[1*8192+811] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 511"); end
  if (bm[1*8192+812] !== 8'h5a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 512"); end
  if (bm[1*8192+813] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 513"); end
  if (bm[1*8192+814] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 514"); end
  if (bm[1*8192+815] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 515"); end
  if (bm[1*8192+816] !== 8'hfd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 516"); end
  if (bm[1*8192+817] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 517"); end
  if (bm[1*8192+818] !== 8'h47) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 518"); end
  if (bm[1*8192+819] !== 8'hf9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 519"); end
  if (bm[1*8192+820] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 520"); end
  if (bm[1*8192+821] !== 8'hdb) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 521"); end
  if (bm[1*8192+822] !== 8'he8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 522"); end
  if (bm[1*8192+823] !== 8'h9a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 523"); end
  if (bm[1*8192+824] !== 8'h7e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 524"); end
  if (bm[1*8192+825] !== 8'h8e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 525"); end
  if (bm[1*8192+826] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 526"); end
  if (bm[1*8192+827] !== 8'hf7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 527"); end
  if (bm[1*8192+828] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 528"); end
  if (bm[1*8192+829] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 529"); end
  if (bm[1*8192+830] !== 8'h29) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 530"); end
  if (bm[1*8192+831] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 531"); end
  if (bm[1*8192+832] !== 8'h0a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 532"); end
  if (bm[1*8192+833] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 533"); end
  if (bm[1*8192+834] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 534"); end
  if (bm[1*8192+835] !== 8'h19) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 535"); end
  if (bm[1*8192+836] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 536"); end
  if (bm[1*8192+837] !== 8'hde) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 537"); end
  if (bm[1*8192+838] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 538"); end
  if (bm[1*8192+839] !== 8'hde) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 539"); end
  if (bm[1*8192+840] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 540"); end
  if (bm[1*8192+841] !== 8'h0c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 541"); end
  if (bm[1*8192+842] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 542"); end
  if (bm[1*8192+843] !== 8'h19) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 543"); end
  if (bm[1*8192+844] !== 8'h86) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 544"); end
  if (bm[1*8192+845] !== 8'hfc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 545"); end
  if (bm[1*8192+846] !== 8'he2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 546"); end
  if (bm[1*8192+847] !== 8'hfa) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 547"); end
  if (bm[1*8192+848] !== 8'h69) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 548"); end
  if (bm[1*8192+849] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 549"); end
  if (bm[1*8192+850] !== 8'hfe) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 550"); end
  if (bm[1*8192+851] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 551"); end
  if (bm[1*8192+852] !== 8'h3b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 552"); end
  if (bm[1*8192+853] !== 8'hee) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 553"); end
  if (bm[1*8192+854] !== 8'h0c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 554"); end
  if (bm[1*8192+855] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 555"); end
  if (bm[1*8192+856] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 556"); end
  if (bm[1*8192+857] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 557"); end
  if (bm[1*8192+858] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 558"); end
  if (bm[1*8192+859] !== 8'h2f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 559"); end
  if (bm[1*8192+860] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 560"); end
  if (bm[1*8192+861] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 561"); end
  if (bm[1*8192+862] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 562"); end
  if (bm[1*8192+863] !== 8'h3c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 563"); end
  if (bm[1*8192+864] !== 8'hcc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 564"); end
  if (bm[1*8192+865] !== 8'hb4) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 565"); end
  if (bm[1*8192+866] !== 8'ha9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 566"); end
  if (bm[1*8192+867] !== 8'he5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 567"); end
  if (bm[1*8192+868] !== 8'h9d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 568"); end
  if (bm[1*8192+869] !== 8'hbd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 569"); end
  if (bm[1*8192+870] !== 8'h6b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 570"); end
  if (bm[1*8192+871] !== 8'h53) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 571"); end
  if (bm[1*8192+872] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 572"); end
  if (bm[1*8192+873] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 573"); end
  if (bm[1*8192+874] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 574"); end
  if (bm[1*8192+875] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 575"); end
  if (bm[1*8192+876] !== 8'hbd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 576"); end
  if (bm[1*8192+877] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 577"); end
  if (bm[1*8192+878] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 578"); end
  if (bm[1*8192+879] !== 8'ha1) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 579"); end
  if (bm[1*8192+880] !== 8'h5d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 580"); end
  if (bm[1*8192+881] !== 8'h09) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 581"); end
  if (bm[1*8192+882] !== 8'h19) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 582"); end
  if (bm[1*8192+883] !== 8'he3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 583"); end
  if (bm[1*8192+884] !== 8'hce) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 584"); end
  if (bm[1*8192+885] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 585"); end
  if (bm[1*8192+886] !== 8'h64) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 586"); end
  if (bm[1*8192+887] !== 8'h33) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 587"); end
  if (bm[1*8192+888] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 588"); end
  if (bm[1*8192+889] !== 8'h8d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 589"); end
  if (bm[1*8192+890] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 590"); end
  if (bm[1*8192+891] !== 8'hd2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 591"); end
  if (bm[1*8192+892] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 592"); end
  if (bm[1*8192+893] !== 8'hed) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 593"); end
  if (bm[1*8192+894] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 594"); end
  if (bm[1*8192+895] !== 8'he8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 595"); end
  if (bm[1*8192+896] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 596"); end
  if (bm[1*8192+897] !== 8'h67) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 597"); end
  if (bm[1*8192+898] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 598"); end
  if (bm[1*8192+899] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 599"); end
  if (bm[1*8192+900] !== 8'h7f) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 600"); end
  if (bm[1*8192+901] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 601"); end
  if (bm[1*8192+902] !== 8'hbe) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 602"); end
  if (bm[1*8192+903] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 603"); end
  if (bm[1*8192+904] !== 8'h42) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 604"); end
  if (bm[1*8192+905] !== 8'hd5) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 605"); end
  if (bm[1*8192+906] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 606"); end
  if (bm[1*8192+907] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 607"); end
  if (bm[1*8192+908] !== 8'ha7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 608"); end
  if (bm[1*8192+909] !== 8'hfe) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 609"); end
  if (bm[1*8192+910] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 610"); end
  if (bm[1*8192+911] !== 8'h29) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 611"); end
  if (bm[1*8192+912] !== 8'h3e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 612"); end
  if (bm[1*8192+913] !== 8'hda) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 613"); end
  if (bm[1*8192+914] !== 8'h53) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 614"); end
  if (bm[1*8192+915] !== 8'hcf) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 615"); end
  if (bm[1*8192+916] !== 8'hc2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 616"); end
  if (bm[1*8192+917] !== 8'h10) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 617"); end
  if (bm[1*8192+918] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 618"); end
  if (bm[1*8192+919] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 619"); end
  if (bm[1*8192+920] !== 8'hbc) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 620"); end
  if (bm[1*8192+921] !== 8'h4d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 621"); end
  if (bm[1*8192+922] !== 8'he2) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 622"); end
  if (bm[1*8192+923] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 623"); end
  if (bm[1*8192+924] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 624"); end
  if (bm[1*8192+925] !== 8'h12) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 625"); end
  if (bm[1*8192+926] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 626"); end
  if (bm[1*8192+927] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 627"); end
  if (bm[1*8192+928] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 628"); end
  if (bm[1*8192+929] !== 8'h29) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 629"); end
  if (bm[1*8192+930] !== 8'ha3) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 630"); end
  if (bm[1*8192+931] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 631"); end
  if (bm[1*8192+932] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 632"); end
  if (bm[1*8192+933] !== 8'hff) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 633"); end
  if (bm[1*8192+934] !== 8'h4d) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 634"); end
  if (bm[1*8192+935] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 635"); end
  if (bm[1*8192+936] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 636"); end
  if (bm[1*8192+937] !== 8'hb7) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 637"); end
  if (bm[1*8192+938] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 638"); end
  if (bm[1*8192+939] !== 8'h6b) begin fails=fails+1; if (fails<6) $display("FAIL pkz19 byte 639"); end
  expv = 8192'h0000000700000024000000170000002100000010000000090000001400000018000000000000000d0000002b000000050000000d0000002500000003000000190000000700000009000000250000000b0000000800000012000000040000000b0000001a000000090000001000000025000000090000002a0000000f0000001b0000000e000000240000000d000000200000002b000000050000002b000000240000000100000012000000250000001000000010000000100000002a00000028000000120000002a0000000b00000021000000140000001700000017000000060000000800000021000000210000000b0000001d000000040000002b0000001700000005000000110000000c0000000f000000210000001b000000090000001c0000001d000000260000001b00000021000000040000001f000000180000002900000008000000080000000c000000120000000300000020000000180000001b00000001000000280000001f0000001a00000011000000190000001400000000000000270000001e00000002000000240000000c000000040000000c0000000d000000140000000a00000022000000000000000700000019000000080000002b0000000300000014000000100000001400000028000000290000002a0000000c0000001b000000020000001f000000080000002500000022000000280000000b00000016000000120000001d00000009000000290000000200000005000000010000000e0000002700000004000000150000000b000000200000000f0000000d000000010000002800000017000000110000001f0000000b000000100000001d0000001f00000003000000120000002b00000015000000180000000a000000250000000800000015000000260000000b0000002b00000002000000240000000e000000140000000f0000000200000002000000200000000e00000023000000240000000d00000023000000250000002800000003000000260000000d00000012000000100000001300000004000000210000001e000000080000000d00000025000000140000000f0000000b00000001000000070000000c0000001c000000230000001b00000013000000210000001e000000120000002000000003000000290000001f000000030000001200000015000000250000000600000008000000080000002100000018000000000000000900000027000000130000002100000018000000270000002b0000000c0000001b000000210000001700000021000000000000001d0000002000000003000000170000002b0000002500000016000000090000001c0000000d000000060000000a0000002a0000000a0000001a0000002a00000028000000190000001a000000200000001f000000270000002b00000026;
  for (i=0;i<256;i=i+1) pm.mem[3*256+i] = expv[32*i +: 32];
  go(4,3,2,40,0,0,0,80,0); $display("pkw1_88: %0d clk", cyc-c0); n=n+1;
  if (bm[2*8192+40] !== 8'he6) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 0"); end
  if (bm[2*8192+41] !== 8'h7a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 1"); end
  if (bm[2*8192+42] !== 8'h7e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 2"); end
  if (bm[2*8192+43] !== 8'ha0) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 3"); end
  if (bm[2*8192+44] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 4"); end
  if (bm[2*8192+45] !== 8'ha1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 5"); end
  if (bm[2*8192+46] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 6"); end
  if (bm[2*8192+47] !== 8'ha6) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 7"); end
  if (bm[2*8192+48] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 8"); end
  if (bm[2*8192+49] !== 8'h8a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 9"); end
  if (bm[2*8192+50] !== 8'hd1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 10"); end
  if (bm[2*8192+51] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 11"); end
  if (bm[2*8192+52] !== 8'h89) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 12"); end
  if (bm[2*8192+53] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 13"); end
  if (bm[2*8192+54] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 14"); end
  if (bm[2*8192+55] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 15"); end
  if (bm[2*8192+56] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 16"); end
  if (bm[2*8192+57] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 17"); end
  if (bm[2*8192+58] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 18"); end
  if (bm[2*8192+59] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 19"); end
  if (bm[2*8192+60] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 20"); end
  if (bm[2*8192+61] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 21"); end
  if (bm[2*8192+62] !== 8'hb3) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 22"); end
  if (bm[2*8192+63] !== 8'h9e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 23"); end
  if (bm[2*8192+64] !== 8'h58) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 24"); end
  if (bm[2*8192+65] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 25"); end
  if (bm[2*8192+66] !== 8'h9d) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 26"); end
  if (bm[2*8192+67] !== 8'h09) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 27"); end
  if (bm[2*8192+68] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 28"); end
  if (bm[2*8192+69] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 29"); end
  if (bm[2*8192+70] !== 8'h08) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 30"); end
  if (bm[2*8192+71] !== 8'h62) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 31"); end
  if (bm[2*8192+72] !== 8'h94) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 32"); end
  if (bm[2*8192+73] !== 8'h95) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 33"); end
  if (bm[2*8192+74] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 34"); end
  if (bm[2*8192+75] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 35"); end
  if (bm[2*8192+76] !== 8'he9) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 36"); end
  if (bm[2*8192+77] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 37"); end
  if (bm[2*8192+78] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 38"); end
  if (bm[2*8192+79] !== 8'h5e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 39"); end
  if (bm[2*8192+80] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 40"); end
  if (bm[2*8192+81] !== 8'h6d) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 41"); end
  if (bm[2*8192+82] !== 8'h23) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 42"); end
  if (bm[2*8192+83] !== 8'hc7) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 43"); end
  if (bm[2*8192+84] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 44"); end
  if (bm[2*8192+85] !== 8'hc1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 45"); end
  if (bm[2*8192+86] !== 8'hf2) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 46"); end
  if (bm[2*8192+87] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 47"); end
  if (bm[2*8192+88] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 48"); end
  if (bm[2*8192+89] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 49"); end
  if (bm[2*8192+90] !== 8'h78) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 50"); end
  if (bm[2*8192+91] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 51"); end
  if (bm[2*8192+92] !== 8'h31) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 52"); end
  if (bm[2*8192+93] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 53"); end
  if (bm[2*8192+94] !== 8'h52) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 54"); end
  if (bm[2*8192+95] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 55"); end
  if (bm[2*8192+96] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 56"); end
  if (bm[2*8192+97] !== 8'h68) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 57"); end
  if (bm[2*8192+98] !== 8'h39) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 58"); end
  if (bm[2*8192+99] !== 8'h36) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 59"); end
  if (bm[2*8192+100] !== 8'he4) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 60"); end
  if (bm[2*8192+101] !== 8'he8) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 61"); end
  if (bm[2*8192+102] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 62"); end
  if (bm[2*8192+103] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 63"); end
  if (bm[2*8192+104] !== 8'hf0) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 64"); end
  if (bm[2*8192+105] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 65"); end
  if (bm[2*8192+106] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 66"); end
  if (bm[2*8192+107] !== 8'h29) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 67"); end
  if (bm[2*8192+108] !== 8'hac) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 68"); end
  if (bm[2*8192+109] !== 8'h8b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 69"); end
  if (bm[2*8192+110] !== 8'h59) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 70"); end
  if (bm[2*8192+111] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 71"); end
  if (bm[2*8192+112] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 72"); end
  if (bm[2*8192+113] !== 8'h82) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 73"); end
  if (bm[2*8192+114] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 74"); end
  if (bm[2*8192+115] !== 8'hab) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 75"); end
  if (bm[2*8192+116] !== 8'h34) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 76"); end
  if (bm[2*8192+117] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 77"); end
  if (bm[2*8192+118] !== 8'h1d) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 78"); end
  if (bm[2*8192+119] !== 8'hb4) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 79"); end
  if (bm[2*8192+120] !== 8'h7c) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 80"); end
  if (bm[2*8192+121] !== 8'hd1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 81"); end
  if (bm[2*8192+122] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 82"); end
  if (bm[2*8192+123] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 83"); end
  if (bm[2*8192+124] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 84"); end
  if (bm[2*8192+125] !== 8'h03) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 85"); end
  if (bm[2*8192+126] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 86"); end
  if (bm[2*8192+127] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 87"); end
  if (bm[2*8192+128] !== 8'h71) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 88"); end
  if (bm[2*8192+129] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 89"); end
  if (bm[2*8192+130] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 90"); end
  if (bm[2*8192+131] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 91"); end
  if (bm[2*8192+132] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 92"); end
  if (bm[2*8192+133] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 93"); end
  if (bm[2*8192+134] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 94"); end
  if (bm[2*8192+135] !== 8'h59) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 95"); end
  if (bm[2*8192+136] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 96"); end
  if (bm[2*8192+137] !== 8'h2a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 97"); end
  if (bm[2*8192+138] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 98"); end
  if (bm[2*8192+139] !== 8'hc8) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 99"); end
  if (bm[2*8192+140] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 100"); end
  if (bm[2*8192+141] !== 8'h6c) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 101"); end
  if (bm[2*8192+142] !== 8'h8c) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 102"); end
  if (bm[2*8192+143] !== 8'h9a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 103"); end
  if (bm[2*8192+144] !== 8'ha2) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 104"); end
  if (bm[2*8192+145] !== 8'h14) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 105"); end
  if (bm[2*8192+146] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 106"); end
  if (bm[2*8192+147] !== 8'h0d) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 107"); end
  if (bm[2*8192+148] !== 8'h2b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 108"); end
  if (bm[2*8192+149] !== 8'h92) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 109"); end
  if (bm[2*8192+150] !== 8'h1d) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 110"); end
  if (bm[2*8192+151] !== 8'h80) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 111"); end
  if (bm[2*8192+152] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 112"); end
  if (bm[2*8192+153] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 113"); end
  if (bm[2*8192+154] !== 8'h0d) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 114"); end
  if (bm[2*8192+155] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 115"); end
  if (bm[2*8192+156] !== 8'h30) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 116"); end
  if (bm[2*8192+157] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 117"); end
  if (bm[2*8192+158] !== 8'he0) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 118"); end
  if (bm[2*8192+159] !== 8'h9d) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 119"); end
  if (bm[2*8192+160] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 120"); end
  if (bm[2*8192+161] !== 8'h95) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 121"); end
  if (bm[2*8192+162] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 122"); end
  if (bm[2*8192+163] !== 8'hda) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 123"); end
  if (bm[2*8192+164] !== 8'h87) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 124"); end
  if (bm[2*8192+165] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 125"); end
  if (bm[2*8192+166] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 126"); end
  if (bm[2*8192+167] !== 8'h06) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 127"); end
  if (bm[2*8192+168] !== 8'h0e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 128"); end
  if (bm[2*8192+169] !== 8'h12) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 129"); end
  if (bm[2*8192+170] !== 8'h83) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 130"); end
  if (bm[2*8192+171] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 131"); end
  if (bm[2*8192+172] !== 8'h29) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 132"); end
  if (bm[2*8192+173] !== 8'hf6) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 133"); end
  if (bm[2*8192+174] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 134"); end
  if (bm[2*8192+175] !== 8'he1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 135"); end
  if (bm[2*8192+176] !== 8'h66) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 136"); end
  if (bm[2*8192+177] !== 8'h76) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 137"); end
  if (bm[2*8192+178] !== 8'h5c) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 138"); end
  if (bm[2*8192+179] !== 8'hb2) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 139"); end
  if (bm[2*8192+180] !== 8'h85) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 140"); end
  if (bm[2*8192+181] !== 8'h0f) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 141"); end
  if (bm[2*8192+182] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 142"); end
  if (bm[2*8192+183] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 143"); end
  if (bm[2*8192+184] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 144"); end
  if (bm[2*8192+185] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 145"); end
  if (bm[2*8192+186] !== 8'h74) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 146"); end
  if (bm[2*8192+187] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 147"); end
  if (bm[2*8192+188] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 148"); end
  if (bm[2*8192+189] !== 8'h22) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 149"); end
  if (bm[2*8192+190] !== 8'hc6) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 150"); end
  if (bm[2*8192+191] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 151"); end
  if (bm[2*8192+192] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 152"); end
  if (bm[2*8192+193] !== 8'he1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 153"); end
  if (bm[2*8192+194] !== 8'ha2) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 154"); end
  if (bm[2*8192+195] !== 8'h4a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 155"); end
  if (bm[2*8192+196] !== 8'ha8) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 156"); end
  if (bm[2*8192+197] !== 8'h0a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 157"); end
  if (bm[2*8192+198] !== 8'h41) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 158"); end
  if (bm[2*8192+199] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 159"); end
  if (bm[2*8192+200] !== 8'h29) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 160"); end
  if (bm[2*8192+201] !== 8'h05) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 161"); end
  if (bm[2*8192+202] !== 8'he4) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 162"); end
  if (bm[2*8192+203] !== 8'h5a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 163"); end
  if (bm[2*8192+204] !== 8'hac) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 164"); end
  if (bm[2*8192+205] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 165"); end
  if (bm[2*8192+206] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 166"); end
  if (bm[2*8192+207] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 167"); end
  if (bm[2*8192+208] !== 8'hdb) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 168"); end
  if (bm[2*8192+209] !== 8'ha3) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 169"); end
  if (bm[2*8192+210] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 170"); end
  if (bm[2*8192+211] !== 8'h25) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 171"); end
  if (bm[2*8192+212] !== 8'h94) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 172"); end
  if (bm[2*8192+213] !== 8'h68) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 173"); end
  if (bm[2*8192+214] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 174"); end
  if (bm[2*8192+215] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 175"); end
  if (bm[2*8192+216] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 176"); end
  if (bm[2*8192+217] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 177"); end
  if (bm[2*8192+218] !== 8'h99) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 178"); end
  if (bm[2*8192+219] !== 8'h1c) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 179"); end
  if (bm[2*8192+220] !== 8'hd9) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 180"); end
  if (bm[2*8192+221] !== 8'h50) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 181"); end
  if (bm[2*8192+222] !== 8'h36) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 182"); end
  if (bm[2*8192+223] !== 8'hc5) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 183"); end
  if (bm[2*8192+224] !== 8'hda) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 184"); end
  if (bm[2*8192+225] !== 8'h00) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 185"); end
  if (bm[2*8192+226] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 186"); end
  if (bm[2*8192+227] !== 8'h95) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 187"); end
  if (bm[2*8192+228] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 188"); end
  if (bm[2*8192+229] !== 8'he1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 189"); end
  if (bm[2*8192+230] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 190"); end
  if (bm[2*8192+231] !== 8'h1e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_88 byte 191"); end
  expv = 8192'h00000005000000020000000d000000010000000a0000000e00000006000000020000000300000000000000010000000d0000000c0000000f000000020000000d000000010000000300000001000000050000000a00000002000000040000000b00000008000000010000000400000000000000010000000b000000090000000800000000000000040000000a00000009000000060000000e00000001000000020000000c0000000f0000000f0000000d0000000d0000000f00000005000000010000000a0000000c0000000200000009000000040000000e000000020000000c0000000c000000080000000e0000000a00000007000000050000000200000008000000080000000b00000004000000040000000f000000010000000500000007000000090000000600000007000000070000000c0000000800000006000000030000000b0000000000000003000000020000000200000001000000080000000b00000009000000060000000100000006000000090000000e0000000e0000000c000000070000000a0000000c00000003000000010000000a000000020000000e000000000000000b000000090000000f0000000a0000000d0000000e0000000f0000000f0000000b0000000900000006000000030000000e0000000c000000070000000300000005000000080000000a0000000a0000000d000000070000000b0000000b000000060000000f0000000800000006000000000000000e00000001000000070000000a0000000e0000000e000000030000000a000000090000000900000001000000080000000900000005000000010000000a0000000d0000000d000000060000000a0000000f0000000400000001000000010000000200000006000000010000000900000007000000050000000300000008000000000000000a0000000000000002000000020000000700000004000000030000000d0000000400000009000000040000000b00000008000000000000000d0000000a00000005000000010000000500000005000000020000000c0000000d0000000a0000000a00000007000000000000000a0000000b00000002000000000000000a0000000700000004000000050000000a0000000a00000006000000050000000e000000010000000b000000050000000a0000000e00000004000000090000000f000000090000000400000004000000020000000000000008000000040000000f0000000500000004000000050000000b0000000f0000000f0000000d00000005000000010000000c0000000c0000000d00000007000000030000000f0000000c0000000f0000000b0000000700000005000000050000000d000000080000000f0000000200000008000000010000000f000000020000000a000000040000000100000008;
  for (i=0;i<256;i=i+1) pm.mem[3*256+i] = expv[32*i +: 32];
  go(4,3,2,40,0,0,1,80,0); $display("pkw1_32: %0d clk", cyc-c0); n=n+1;
  if (bm[2*8192+40] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 0"); end
  if (bm[2*8192+41] !== 8'ha4) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 1"); end
  if (bm[2*8192+42] !== 8'hf2) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 2"); end
  if (bm[2*8192+43] !== 8'h81) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 3"); end
  if (bm[2*8192+44] !== 8'hf2) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 4"); end
  if (bm[2*8192+45] !== 8'hd8) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 5"); end
  if (bm[2*8192+46] !== 8'h55) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 6"); end
  if (bm[2*8192+47] !== 8'hb7) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 7"); end
  if (bm[2*8192+48] !== 8'hcf) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 8"); end
  if (bm[2*8192+49] !== 8'h3f) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 9"); end
  if (bm[2*8192+50] !== 8'hd7) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 10"); end
  if (bm[2*8192+51] !== 8'hcc) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 11"); end
  if (bm[2*8192+52] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 12"); end
  if (bm[2*8192+53] !== 8'hfd) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 13"); end
  if (bm[2*8192+54] !== 8'hbf) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 14"); end
  if (bm[2*8192+55] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 15"); end
  if (bm[2*8192+56] !== 8'hf5) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 16"); end
  if (bm[2*8192+57] !== 8'h84) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 17"); end
  if (bm[2*8192+58] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 18"); end
  if (bm[2*8192+59] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 19"); end
  if (bm[2*8192+60] !== 8'hf9) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 20"); end
  if (bm[2*8192+61] !== 8'h49) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 21"); end
  if (bm[2*8192+62] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 22"); end
  if (bm[2*8192+63] !== 8'hb5) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 23"); end
  if (bm[2*8192+64] !== 8'he1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 24"); end
  if (bm[2*8192+65] !== 8'h65) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 25"); end
  if (bm[2*8192+66] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 26"); end
  if (bm[2*8192+67] !== 8'h45) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 27"); end
  if (bm[2*8192+68] !== 8'ha7) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 28"); end
  if (bm[2*8192+69] !== 8'h20) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 29"); end
  if (bm[2*8192+70] !== 8'hab) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 30"); end
  if (bm[2*8192+71] !== 8'h70) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 31"); end
  if (bm[2*8192+72] !== 8'haa) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 32"); end
  if (bm[2*8192+73] !== 8'hcd) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 33"); end
  if (bm[2*8192+74] !== 8'h52) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 34"); end
  if (bm[2*8192+75] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 35"); end
  if (bm[2*8192+76] !== 8'ha5) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 36"); end
  if (bm[2*8192+77] !== 8'h0d) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 37"); end
  if (bm[2*8192+78] !== 8'hb8) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 38"); end
  if (bm[2*8192+79] !== 8'h94) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 39"); end
  if (bm[2*8192+80] !== 8'hd4) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 40"); end
  if (bm[2*8192+81] !== 8'h43) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 41"); end
  if (bm[2*8192+82] !== 8'h27) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 42"); end
  if (bm[2*8192+83] !== 8'h02) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 43"); end
  if (bm[2*8192+84] !== 8'h0a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 44"); end
  if (bm[2*8192+85] !== 8'h38) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 45"); end
  if (bm[2*8192+86] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 46"); end
  if (bm[2*8192+87] !== 8'h19) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 47"); end
  if (bm[2*8192+88] !== 8'h26) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 48"); end
  if (bm[2*8192+89] !== 8'h11) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 49"); end
  if (bm[2*8192+90] !== 8'hf4) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 50"); end
  if (bm[2*8192+91] !== 8'h6a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 51"); end
  if (bm[2*8192+92] !== 8'hdd) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 52"); end
  if (bm[2*8192+93] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 53"); end
  if (bm[2*8192+94] !== 8'h95) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 54"); end
  if (bm[2*8192+95] !== 8'h18) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 55"); end
  if (bm[2*8192+96] !== 8'h99) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 56"); end
  if (bm[2*8192+97] !== 8'h3a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 57"); end
  if (bm[2*8192+98] !== 8'hee) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 58"); end
  if (bm[2*8192+99] !== 8'h7a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 59"); end
  if (bm[2*8192+100] !== 8'he1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 60"); end
  if (bm[2*8192+101] !== 8'h60) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 61"); end
  if (bm[2*8192+102] !== 8'hf8) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 62"); end
  if (bm[2*8192+103] !== 8'hb6) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 63"); end
  if (bm[2*8192+104] !== 8'h7b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 64"); end
  if (bm[2*8192+105] !== 8'had) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 65"); end
  if (bm[2*8192+106] !== 8'h8a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 66"); end
  if (bm[2*8192+107] !== 8'h35) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 67"); end
  if (bm[2*8192+108] !== 8'hc7) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 68"); end
  if (bm[2*8192+109] !== 8'h3e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 69"); end
  if (bm[2*8192+110] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 70"); end
  if (bm[2*8192+111] !== 8'hfb) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 71"); end
  if (bm[2*8192+112] !== 8'hef) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 72"); end
  if (bm[2*8192+113] !== 8'had) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 73"); end
  if (bm[2*8192+114] !== 8'h9f) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 74"); end
  if (bm[2*8192+115] !== 8'h0b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 75"); end
  if (bm[2*8192+116] !== 8'h2e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 76"); end
  if (bm[2*8192+117] !== 8'h1a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 77"); end
  if (bm[2*8192+118] !== 8'hc3) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 78"); end
  if (bm[2*8192+119] !== 8'h7a) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 79"); end
  if (bm[2*8192+120] !== 8'hec) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 80"); end
  if (bm[2*8192+121] !== 8'h9e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 81"); end
  if (bm[2*8192+122] !== 8'h16) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 82"); end
  if (bm[2*8192+123] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 83"); end
  if (bm[2*8192+124] !== 8'h8b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 84"); end
  if (bm[2*8192+125] !== 8'h21) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 85"); end
  if (bm[2*8192+126] !== 8'h32) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 86"); end
  if (bm[2*8192+127] !== 8'hb0) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 87"); end
  if (bm[2*8192+128] !== 8'h63) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 88"); end
  if (bm[2*8192+129] !== 8'hc8) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 89"); end
  if (bm[2*8192+130] !== 8'h77) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 90"); end
  if (bm[2*8192+131] !== 8'h96) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 91"); end
  if (bm[2*8192+132] !== 8'h57) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 92"); end
  if (bm[2*8192+133] !== 8'hf1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 93"); end
  if (bm[2*8192+134] !== 8'h44) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 94"); end
  if (bm[2*8192+135] !== 8'h8b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 95"); end
  if (bm[2*8192+136] !== 8'h28) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 96"); end
  if (bm[2*8192+137] !== 8'h75) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 97"); end
  if (bm[2*8192+138] !== 8'hea) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 98"); end
  if (bm[2*8192+139] !== 8'hc8) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 99"); end
  if (bm[2*8192+140] !== 8'h2c) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 100"); end
  if (bm[2*8192+141] !== 8'h4e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 101"); end
  if (bm[2*8192+142] !== 8'h29) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 102"); end
  if (bm[2*8192+143] !== 8'hac) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 103"); end
  if (bm[2*8192+144] !== 8'h51) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 104"); end
  if (bm[2*8192+145] !== 8'hdf) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 105"); end
  if (bm[2*8192+146] !== 8'hfd) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 106"); end
  if (bm[2*8192+147] !== 8'hcf) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 107"); end
  if (bm[2*8192+148] !== 8'h12) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 108"); end
  if (bm[2*8192+149] !== 8'h6e) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 109"); end
  if (bm[2*8192+150] !== 8'ha9) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 110"); end
  if (bm[2*8192+151] !== 8'h04) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 111"); end
  if (bm[2*8192+152] !== 8'h98) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 112"); end
  if (bm[2*8192+153] !== 8'h1b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 113"); end
  if (bm[2*8192+154] !== 8'h40) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 114"); end
  if (bm[2*8192+155] !== 8'h81) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 115"); end
  if (bm[2*8192+156] !== 8'h4b) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 116"); end
  if (bm[2*8192+157] !== 8'ha2) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 117"); end
  if (bm[2*8192+158] !== 8'h15) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 118"); end
  if (bm[2*8192+159] !== 8'h13) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 119"); end
  if (bm[2*8192+160] !== 8'h2d) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 120"); end
  if (bm[2*8192+161] !== 8'hcf) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 121"); end
  if (bm[2*8192+162] !== 8'h1d) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 122"); end
  if (bm[2*8192+163] !== 8'h30) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 123"); end
  if (bm[2*8192+164] !== 8'h62) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 124"); end
  if (bm[2*8192+165] !== 8'hae) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 125"); end
  if (bm[2*8192+166] !== 8'hd1) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 126"); end
  if (bm[2*8192+167] !== 8'h52) begin fails=fails+1; if (fails<6) $display("FAIL pkw1_32 byte 127"); end
  expv = 8192'h0000000e00000003000000020000000f0000000b000000000000000d000000090000000e000000060000000d0000000c000000040000000c0000000600000002000000060000000700000003000000060000000f0000000300000007000000080000000a00000007000000030000000d00000007000000070000000f000000030000000b000000070000000a000000010000000c000000040000000300000001000000010000000d0000000900000007000000010000000a0000000a0000000400000005000000020000000a000000090000000f0000000b000000080000000e000000040000000d0000000d000000040000000a0000000e0000000b0000000a0000000e0000000b0000000900000000000000040000000100000000000000000000000a000000050000000b0000000c0000000200000008000000050000000e000000000000000a0000000500000008000000010000000a0000000200000001000000030000000f000000080000000100000004000000060000000b00000004000000050000000c00000007000000030000000c00000004000000020000000e00000003000000060000000400000002000000080000000a0000000000000000000000080000000d00000002000000030000000d000000000000000b00000003000000060000000d0000000d0000000100000007000000030000000a0000000500000001000000050000000b0000000b0000000f0000000700000000000000030000000100000003000000010000000d000000060000000f00000008000000020000000400000009000000080000000c0000000a0000000b0000000e0000000e00000001000000030000000d000000080000000100000000000000030000000b0000000f0000000b0000000e0000000b0000000d000000080000000700000007000000090000000e0000000600000009000000010000000300000002000000010000000000000006000000050000000400000007000000070000000d00000005000000070000000c0000000d0000000b00000003000000090000000e0000000c0000000b000000030000000c000000070000000800000000000000020000000c000000020000000c00000003000000020000000a000000020000000300000003000000090000000400000002000000090000000a000000050000000e00000005000000020000000900000008000000010000000d00000003000000050000000a00000004000000090000000600000000000000040000000000000006000000000000000200000005000000000000000c0000000100000008000000000000000f0000000c0000000f000000070000000500000001000000090000000a0000000a0000000200000001000000000000000300000004000000010000000b0000000f;
  for (i=0;i<256;i=i+1) pm.mem[3*256+i] = expv[32*i +: 32];
  sh_init=1; @(negedge clk); sh_init=0; repeat(6) @(negedge clk);
  go(4,3,3,0,0,0,1,80,0); $display("pkw1_shake: %0d clk", cyc-c0); n=n+1;
  while(!sh_ready) @(negedge clk); sh_fin=1; @(negedge clk); sh_fin=0;
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h8b) begin fails=fails+1; $display("FAIL shake digest byte 0"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h96) begin fails=fails+1; $display("FAIL shake digest byte 1"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'hc8) begin fails=fails+1; $display("FAIL shake digest byte 2"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'hc3) begin fails=fails+1; $display("FAIL shake digest byte 3"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h7c) begin fails=fails+1; $display("FAIL shake digest byte 4"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'hd9) begin fails=fails+1; $display("FAIL shake digest byte 5"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h5a) begin fails=fails+1; $display("FAIL shake digest byte 6"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h54) begin fails=fails+1; $display("FAIL shake digest byte 7"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h32) begin fails=fails+1; $display("FAIL shake digest byte 8"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h10) begin fails=fails+1; $display("FAIL shake digest byte 9"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'hee) begin fails=fails+1; $display("FAIL shake digest byte 10"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h5e) begin fails=fails+1; $display("FAIL shake digest byte 11"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h85) begin fails=fails+1; $display("FAIL shake digest byte 12"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h94) begin fails=fails+1; $display("FAIL shake digest byte 13"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h13) begin fails=fails+1; $display("FAIL shake digest byte 14"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'hf7) begin fails=fails+1; $display("FAIL shake digest byte 15"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h33) begin fails=fails+1; $display("FAIL shake digest byte 16"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h14) begin fails=fails+1; $display("FAIL shake digest byte 17"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'had) begin fails=fails+1; $display("FAIL shake digest byte 18"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h90) begin fails=fails+1; $display("FAIL shake digest byte 19"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'hd2) begin fails=fails+1; $display("FAIL shake digest byte 20"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'had) begin fails=fails+1; $display("FAIL shake digest byte 21"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h5f) begin fails=fails+1; $display("FAIL shake digest byte 22"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h18) begin fails=fails+1; $display("FAIL shake digest byte 23"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h2e) begin fails=fails+1; $display("FAIL shake digest byte 24"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'hfb) begin fails=fails+1; $display("FAIL shake digest byte 25"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h3b) begin fails=fails+1; $display("FAIL shake digest byte 26"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h7b) begin fails=fails+1; $display("FAIL shake digest byte 27"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h4a) begin fails=fails+1; $display("FAIL shake digest byte 28"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'he5) begin fails=fails+1; $display("FAIL shake digest byte 29"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h9e) begin fails=fails+1; $display("FAIL shake digest byte 30"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  while(!sh_oready) @(negedge clk); if (sh_obyte !== 8'h9e) begin fails=fails+1; $display("FAIL shake digest byte 31"); end sh_take=1; @(negedge clk); sh_take=0; @(negedge clk);
  bm[2*8192+64] = 8'hc9;
  bm[2*8192+65] = 8'h00;
  bm[2*8192+66] = 8'h05;
  bm[2*8192+67] = 8'hd4;
  bm[2*8192+68] = 8'h16;
  bm[2*8192+69] = 8'h89;
  bm[2*8192+70] = 8'h11;
  bm[2*8192+71] = 8'hc9;
  bm[2*8192+72] = 8'h50;
  bm[2*8192+73] = 8'hc2;
  bm[2*8192+74] = 8'hb4;
  bm[2*8192+75] = 8'h05;
  bm[2*8192+76] = 8'h01;
  bm[2*8192+77] = 8'h16;
  bm[2*8192+78] = 8'h82;
  bm[2*8192+79] = 8'hc0;
  bm[2*8192+80] = 8'h40;
  bm[2*8192+81] = 8'h72;
  bm[2*8192+82] = 8'h60;
  bm[2*8192+83] = 8'h96;
  bm[2*8192+84] = 8'h44;
  bm[2*8192+85] = 8'h12;
  bm[2*8192+86] = 8'h91;
  bm[2*8192+87] = 8'h84;
  bm[2*8192+88] = 8'h41;
  bm[2*8192+89] = 8'hc2;
  bm[2*8192+90] = 8'h28;
  bm[2*8192+91] = 8'h11;
  bm[2*8192+92] = 8'hc6;
  bm[2*8192+93] = 8'h6d;
  bm[2*8192+94] = 8'h8a;
  bm[2*8192+95] = 8'h80;
  bm[2*8192+96] = 8'h51;
  bm[2*8192+97] = 8'h4c;
  bm[2*8192+98] = 8'h48;
  bm[2*8192+99] = 8'h61;
  bm[2*8192+100] = 8'h08;
  bm[2*8192+101] = 8'h37;
  bm[2*8192+102] = 8'h4d;
  bm[2*8192+103] = 8'h82;
  bm[2*8192+104] = 8'hc0;
  bm[2*8192+105] = 8'h25;
  bm[2*8192+106] = 8'hd3;
  bm[2*8192+107] = 8'hb8;
  bm[2*8192+108] = 8'h2c;
  bm[2*8192+109] = 8'h8a;
  bm[2*8192+110] = 8'hc0;
  bm[2*8192+111] = 8'h44;
  bm[2*8192+112] = 8'h98;
  bm[2*8192+113] = 8'h12;
  bm[2*8192+114] = 8'h42;
  bm[2*8192+115] = 8'h84;
  bm[2*8192+116] = 8'h46;
  bm[2*8192+117] = 8'h49;
  bm[2*8192+118] = 8'h12;
  bm[2*8192+119] = 8'ha2;
  bm[2*8192+120] = 8'h2c;
  bm[2*8192+121] = 8'hc1;
  bm[2*8192+122] = 8'h12;
  bm[2*8192+123] = 8'h61;
  bm[2*8192+124] = 8'h18;
  bm[2*8192+125] = 8'h45;
  bm[2*8192+126] = 8'h40;
  bm[2*8192+127] = 8'h58;
  bm[2*8192+128] = 8'h88;
  bm[2*8192+129] = 8'h8d;
  bm[2*8192+130] = 8'h08;
  bm[2*8192+131] = 8'h40;
  bm[2*8192+132] = 8'h72;
  bm[2*8192+133] = 8'h41;
  bm[2*8192+134] = 8'h48;
  bm[2*8192+135] = 8'h4d;
  bm[2*8192+136] = 8'h12;
  bm[2*8192+137] = 8'h34;
  bm[2*8192+138] = 8'h04;
  bm[2*8192+139] = 8'h8c;
  bm[2*8192+140] = 8'h22;
  bm[2*8192+141] = 8'h21;
  bm[2*8192+142] = 8'hc4;
  bm[2*8192+143] = 8'ha0;
  bm[2*8192+144] = 8'h2c;
  bm[2*8192+145] = 8'h13;
  bm[2*8192+146] = 8'hc6;
  bm[2*8192+147] = 8'h4d;
  bm[2*8192+148] = 8'h01;
  bm[2*8192+149] = 8'h93;
  bm[2*8192+150] = 8'h41;
  bm[2*8192+151] = 8'h01;
  bm[2*8192+152] = 8'h28;
  bm[2*8192+153] = 8'h60;
  bm[2*8192+154] = 8'hdb;
  bm[2*8192+155] = 8'hc2;
  bm[2*8192+156] = 8'h4d;
  bm[2*8192+157] = 8'h81;
  bm[2*8192+158] = 8'h28;
  bm[2*8192+159] = 8'h28;
  go(5,5,2,64,0,0,0,80,0); $display("upketa2: %0d clk", cyc-c0); n=n+1;
  expv = 8192'h00000001000000000000000200000000fffffffe00000000000000020000000100000000fffffffffffffffffffffffe00000001ffffffffffffffffffffffffffffffff000000020000000200000000fffffffe0000000200000002000000010000000000000002ffffffff0000000100000001fffffffe000000020000000100000000fffffffffffffffffffffffeffffffff0000000200000000ffffffff00000001ffffffff000000010000000000000002ffffffff00000002fffffffe00000001000000020000000000000000000000010000000000000001fffffffe000000020000000100000002ffffffff0000000000000002000000000000000000000000ffffffff00000000fffffffefffffffe000000010000000200000001fffffffffffffffefffffffefffffffe00000002000000020000000100000002fffffffeffffffffffffffff00000002fffffffe00000001ffffffff00000002000000000000000200000002fffffffe00000000fffffffeffffffff00000002ffffffff00000002000000000000000100000001ffffffff000000020000000100000001ffffffff000000010000000000000001000000020000000000000000000000000000000000000000fffffffeffffffff0000000000000002fffffffe0000000000000002fffffffe000000010000000100000000ffffffff00000002000000000000000100000001fffffffe0000000200000000000000010000000000000001ffffffff00000001fffffffffffffffeffffffff00000000ffffffff0000000100000001fffffffffffffffe0000000200000000000000020000000000000000ffffffff00000000fffffffffffffffffffffffe0000000100000002ffffffff0000000200000000fffffffefffffffe0000000100000001fffffffe00000000fffffffeffffffff0000000200000002000000000000000100000000fffffffffffffffffffffffffffffffeffffffff000000020000000000000001000000010000000000000001fffffffe00000001000000010000000200000001fffffffe00000001000000010000000100000002fffffffe000000000000000000000000000000010000000100000001ffffffff00000001fffffffe00000002fffffffffffffffefffffffefffffffe00000002ffffffff0000000200000002fffffffe00000002fffffffe00000001ffffffff0000000200000002000000010000000200000001ffffffffffffffff00000000ffffffff000000020000000000000000fffffffe00000001fffffffefffffffefffffffe0000000000000001fffffffe000000000000000000000001ffffffffffffffff00000000fffffffe0000000200000001000000000000000200000002ffffffff0000000100000001;
  for (i=0;i<256;i=i+1) if (pm.mem[5*256+i] !== expv[32*i +: 32]) begin fails=fails+1; if (fails<6) $display("FAIL upketa2 coeff %0d got %h exp %h", i, pm.mem[5*256+i], expv[32*i +: 32]); end
  bm[2*8192+64] = 8'h28;
  bm[2*8192+65] = 8'h74;
  bm[2*8192+66] = 8'h48;
  bm[2*8192+67] = 8'h13;
  bm[2*8192+68] = 8'h00;
  bm[2*8192+69] = 8'h52;
  bm[2*8192+70] = 8'h08;
  bm[2*8192+71] = 8'h64;
  bm[2*8192+72] = 8'h72;
  bm[2*8192+73] = 8'h45;
  bm[2*8192+74] = 8'h12;
  bm[2*8192+75] = 8'h31;
  bm[2*8192+76] = 8'h74;
  bm[2*8192+77] = 8'h25;
  bm[2*8192+78] = 8'h12;
  bm[2*8192+79] = 8'h75;
  bm[2*8192+80] = 8'h14;
  bm[2*8192+81] = 8'h51;
  bm[2*8192+82] = 8'h01;
  bm[2*8192+83] = 8'h11;
  bm[2*8192+84] = 8'h78;
  bm[2*8192+85] = 8'h26;
  bm[2*8192+86] = 8'h42;
  bm[2*8192+87] = 8'h70;
  bm[2*8192+88] = 8'h08;
  bm[2*8192+89] = 8'h32;
  bm[2*8192+90] = 8'h06;
  bm[2*8192+91] = 8'h50;
  bm[2*8192+92] = 8'h87;
  bm[2*8192+93] = 8'h46;
  bm[2*8192+94] = 8'h60;
  bm[2*8192+95] = 8'h61;
  bm[2*8192+96] = 8'h16;
  bm[2*8192+97] = 8'h88;
  bm[2*8192+98] = 8'h77;
  bm[2*8192+99] = 8'h12;
  bm[2*8192+100] = 8'h12;
  bm[2*8192+101] = 8'h34;
  bm[2*8192+102] = 8'h48;
  bm[2*8192+103] = 8'h64;
  bm[2*8192+104] = 8'h03;
  bm[2*8192+105] = 8'h51;
  bm[2*8192+106] = 8'h13;
  bm[2*8192+107] = 8'h25;
  bm[2*8192+108] = 8'h80;
  bm[2*8192+109] = 8'h80;
  bm[2*8192+110] = 8'h41;
  bm[2*8192+111] = 8'h41;
  bm[2*8192+112] = 8'h04;
  bm[2*8192+113] = 8'h16;
  bm[2*8192+114] = 8'h53;
  bm[2*8192+115] = 8'h87;
  bm[2*8192+116] = 8'h24;
  bm[2*8192+117] = 8'h50;
  bm[2*8192+118] = 8'h58;
  bm[2*8192+119] = 8'h54;
  bm[2*8192+120] = 8'h56;
  bm[2*8192+121] = 8'h14;
  bm[2*8192+122] = 8'h72;
  bm[2*8192+123] = 8'h60;
  bm[2*8192+124] = 8'h85;
  bm[2*8192+125] = 8'h41;
  bm[2*8192+126] = 8'h45;
  bm[2*8192+127] = 8'h70;
  bm[2*8192+128] = 8'h15;
  bm[2*8192+129] = 8'h03;
  bm[2*8192+130] = 8'h88;
  bm[2*8192+131] = 8'h40;
  bm[2*8192+132] = 8'h42;
  bm[2*8192+133] = 8'h42;
  bm[2*8192+134] = 8'h73;
  bm[2*8192+135] = 8'h70;
  bm[2*8192+136] = 8'h72;
  bm[2*8192+137] = 8'h67;
  bm[2*8192+138] = 8'h05;
  bm[2*8192+139] = 8'h50;
  bm[2*8192+140] = 8'h12;
  bm[2*8192+141] = 8'h77;
  bm[2*8192+142] = 8'h16;
  bm[2*8192+143] = 8'h48;
  bm[2*8192+144] = 8'h63;
  bm[2*8192+145] = 8'h08;
  bm[2*8192+146] = 8'h76;
  bm[2*8192+147] = 8'h63;
  bm[2*8192+148] = 8'h43;
  bm[2*8192+149] = 8'h78;
  bm[2*8192+150] = 8'h14;
  bm[2*8192+151] = 8'h24;
  bm[2*8192+152] = 8'h10;
  bm[2*8192+153] = 8'h58;
  bm[2*8192+154] = 8'h38;
  bm[2*8192+155] = 8'h60;
  bm[2*8192+156] = 8'h82;
  bm[2*8192+157] = 8'h06;
  bm[2*8192+158] = 8'h14;
  bm[2*8192+159] = 8'h37;
  bm[2*8192+160] = 8'h01;
  bm[2*8192+161] = 8'h31;
  bm[2*8192+162] = 8'h43;
  bm[2*8192+163] = 8'h07;
  bm[2*8192+164] = 8'h00;
  bm[2*8192+165] = 8'h55;
  bm[2*8192+166] = 8'h54;
  bm[2*8192+167] = 8'h34;
  bm[2*8192+168] = 8'h67;
  bm[2*8192+169] = 8'h25;
  bm[2*8192+170] = 8'h76;
  bm[2*8192+171] = 8'h30;
  bm[2*8192+172] = 8'h80;
  bm[2*8192+173] = 8'h60;
  bm[2*8192+174] = 8'h84;
  bm[2*8192+175] = 8'h86;
  bm[2*8192+176] = 8'h60;
  bm[2*8192+177] = 8'h54;
  bm[2*8192+178] = 8'h04;
  bm[2*8192+179] = 8'h75;
  bm[2*8192+180] = 8'h34;
  bm[2*8192+181] = 8'h60;
  bm[2*8192+182] = 8'h46;
  bm[2*8192+183] = 8'h55;
  bm[2*8192+184] = 8'h16;
  bm[2*8192+185] = 8'h28;
  bm[2*8192+186] = 8'h66;
  bm[2*8192+187] = 8'h14;
  bm[2*8192+188] = 8'h74;
  bm[2*8192+189] = 8'h41;
  bm[2*8192+190] = 8'h32;
  bm[2*8192+191] = 8'h46;
  go(5,5,2,64,1,0,0,80,0); $display("upketa4: %0d clk", cyc-c0); n=n+1;
  expv = 8192'h00000000fffffffe00000001000000020000000000000003fffffffd000000000000000300000000fffffffefffffffe00000002fffffffc00000003fffffffeffffffffffffffff00000000fffffffefffffffe000000040000000100000000fffffffdffffffff0000000400000000ffffffff00000000fffffffe00000004fffffffcfffffffefffffffc00000000fffffffe00000004fffffffc000000040000000100000004fffffffdfffffffe00000002fffffffffffffffefffffffd0000000100000000ffffffff00000000ffffffffffffffff000000040000000400000004fffffffd00000000000000010000000100000003000000040000000300000001fffffffd000000030000000000000004fffffffefffffffc00000002fffffffe0000000400000001fffffffcfffffffffffffffc000000030000000400000002000000000000000300000000fffffffdfffffffc0000000000000001fffffffe00000001fffffffdfffffffe00000004fffffffcfffffffe0000000100000000fffffffc00000003fffffffefffffffdfffffffd0000000300000002ffffffff0000000400000004fffffffffffffffefffffffdfffffffd00000002fffffffd00000004fffffffd00000001000000000000000200000000000000020000000000000004fffffffcfffffffc000000040000000100000003fffffffffffffffd0000000400000000ffffffff0000000000000003fffffffcfffffffffffffffe00000004fffffffd000000020000000300000000fffffffffffffffeffffffff00000000fffffffffffffffcffffffff000000040000000200000000fffffffcfffffffdffffffff0000000100000003fffffffe000000040000000000000000000000030000000000000003fffffffc00000004fffffffc0000000400000002ffffffff0000000300000001ffffffff000000030000000400000001fffffffe0000000000000000fffffffc000000010000000000000003000000020000000300000002fffffffdfffffffdfffffffcfffffffc00000003fffffffefffffffe00000003fffffffe0000000400000000fffffffefffffffcfffffffdffffffff0000000400000004fffffffe000000010000000200000004fffffffcfffffffd00000004000000000000000200000002fffffffefffffffdfffffffc00000003000000030000000400000003ffffffff000000030000000300000000fffffffdffffffff000000030000000200000002fffffffffffffffd000000000000000100000003000000030000000200000000fffffffffffffffd00000002fffffffe0000000000000004fffffffcffffffff000000020000000400000004000000030000000100000000fffffffcfffffffd0000000000000002fffffffc;
  for (i=0;i<256;i=i+1) if (pm.mem[5*256+i] !== expv[32*i +: 32]) begin fails=fails+1; if (fails<6) $display("FAIL upketa4 coeff %0d got %h exp %h", i, pm.mem[5*256+i], expv[32*i +: 32]); end
  bm[0*8192+9] = 8'hd3;
  bm[0*8192+10] = 8'h00;
  bm[0*8192+11] = 8'hf5;
  bm[0*8192+12] = 8'h4b;
  bm[0*8192+13] = 8'h69;
  bm[0*8192+14] = 8'haf;
  bm[0*8192+15] = 8'ha8;
  bm[0*8192+16] = 8'h04;
  bm[0*8192+17] = 8'h87;
  bm[0*8192+18] = 8'h22;
  bm[0*8192+19] = 8'h39;
  bm[0*8192+20] = 8'h74;
  bm[0*8192+21] = 8'h54;
  bm[0*8192+22] = 8'h91;
  bm[0*8192+23] = 8'h13;
  bm[0*8192+24] = 8'hea;
  bm[0*8192+25] = 8'ha1;
  bm[0*8192+26] = 8'h8b;
  bm[0*8192+27] = 8'h17;
  bm[0*8192+28] = 8'h46;
  bm[0*8192+29] = 8'hb1;
  bm[0*8192+30] = 8'h48;
  bm[0*8192+31] = 8'hf2;
  bm[0*8192+32] = 8'hc6;
  bm[0*8192+33] = 8'hc4;
  bm[0*8192+34] = 8'h49;
  bm[0*8192+35] = 8'h15;
  bm[0*8192+36] = 8'h3a;
  bm[0*8192+37] = 8'h63;
  bm[0*8192+38] = 8'h37;
  bm[0*8192+39] = 8'hbd;
  bm[0*8192+40] = 8'h0c;
  bm[0*8192+41] = 8'h14;
  bm[0*8192+42] = 8'h5c;
  bm[0*8192+43] = 8'h7d;
  bm[0*8192+44] = 8'h87;
  bm[0*8192+45] = 8'h9c;
  bm[0*8192+46] = 8'h49;
  bm[0*8192+47] = 8'h39;
  bm[0*8192+48] = 8'h2d;
  bm[0*8192+49] = 8'h82;
  bm[0*8192+50] = 8'h3c;
  bm[0*8192+51] = 8'heb;
  bm[0*8192+52] = 8'h95;
  bm[0*8192+53] = 8'h31;
  bm[0*8192+54] = 8'hcf;
  bm[0*8192+55] = 8'h3f;
  bm[0*8192+56] = 8'h37;
  bm[0*8192+57] = 8'h4d;
  bm[0*8192+58] = 8'h22;
  bm[0*8192+59] = 8'h7c;
  bm[0*8192+60] = 8'h70;
  bm[0*8192+61] = 8'h91;
  bm[0*8192+62] = 8'h0b;
  bm[0*8192+63] = 8'hff;
  bm[0*8192+64] = 8'he4;
  bm[0*8192+65] = 8'h1a;
  bm[0*8192+66] = 8'h0f;
  bm[0*8192+67] = 8'h6e;
  bm[0*8192+68] = 8'hb7;
  bm[0*8192+69] = 8'h39;
  bm[0*8192+70] = 8'h76;
  bm[0*8192+71] = 8'h8f;
  bm[0*8192+72] = 8'h62;
  bm[0*8192+73] = 8'heb;
  bm[0*8192+74] = 8'h0f;
  bm[0*8192+75] = 8'hb8;
  bm[0*8192+76] = 8'h12;
  bm[0*8192+77] = 8'he5;
  bm[0*8192+78] = 8'h06;
  bm[0*8192+79] = 8'ha5;
  bm[0*8192+80] = 8'h9e;
  bm[0*8192+81] = 8'hca;
  bm[0*8192+82] = 8'h58;
  bm[0*8192+83] = 8'hed;
  bm[0*8192+84] = 8'h07;
  bm[0*8192+85] = 8'h6b;
  bm[0*8192+86] = 8'h5c;
  bm[0*8192+87] = 8'h9a;
  bm[0*8192+88] = 8'h68;
  bm[0*8192+89] = 8'hc9;
  bm[0*8192+90] = 8'h73;
  bm[0*8192+91] = 8'hb7;
  bm[0*8192+92] = 8'had;
  bm[0*8192+93] = 8'hc6;
  bm[0*8192+94] = 8'h25;
  bm[0*8192+95] = 8'hb4;
  bm[0*8192+96] = 8'ha8;
  bm[0*8192+97] = 8'hdb;
  bm[0*8192+98] = 8'h92;
  bm[0*8192+99] = 8'ha7;
  bm[0*8192+100] = 8'ha6;
  bm[0*8192+101] = 8'h1c;
  bm[0*8192+102] = 8'h03;
  bm[0*8192+103] = 8'ha6;
  bm[0*8192+104] = 8'h8f;
  bm[0*8192+105] = 8'h64;
  bm[0*8192+106] = 8'h2a;
  bm[0*8192+107] = 8'h85;
  bm[0*8192+108] = 8'h7f;
  bm[0*8192+109] = 8'he2;
  bm[0*8192+110] = 8'h00;
  bm[0*8192+111] = 8'h7b;
  bm[0*8192+112] = 8'h8e;
  bm[0*8192+113] = 8'hb8;
  bm[0*8192+114] = 8'h94;
  bm[0*8192+115] = 8'hfa;
  bm[0*8192+116] = 8'h7f;
  bm[0*8192+117] = 8'h7a;
  bm[0*8192+118] = 8'h57;
  bm[0*8192+119] = 8'h25;
  bm[0*8192+120] = 8'he1;
  bm[0*8192+121] = 8'hb4;
  bm[0*8192+122] = 8'h6e;
  bm[0*8192+123] = 8'h2f;
  bm[0*8192+124] = 8'hb7;
  bm[0*8192+125] = 8'h65;
  bm[0*8192+126] = 8'h49;
  bm[0*8192+127] = 8'hdd;
  bm[0*8192+128] = 8'h58;
  bm[0*8192+129] = 8'h5c;
  bm[0*8192+130] = 8'h17;
  bm[0*8192+131] = 8'h48;
  bm[0*8192+132] = 8'hdc;
  bm[0*8192+133] = 8'h78;
  bm[0*8192+134] = 8'h9c;
  bm[0*8192+135] = 8'h5d;
  bm[0*8192+136] = 8'h36;
  bm[0*8192+137] = 8'he8;
  bm[0*8192+138] = 8'h63;
  bm[0*8192+139] = 8'hd8;
  bm[0*8192+140] = 8'hf1;
  bm[0*8192+141] = 8'h94;
  bm[0*8192+142] = 8'hae;
  bm[0*8192+143] = 8'h3e;
  bm[0*8192+144] = 8'h2b;
  bm[0*8192+145] = 8'h61;
  bm[0*8192+146] = 8'h57;
  bm[0*8192+147] = 8'ha7;
  bm[0*8192+148] = 8'h7c;
  bm[0*8192+149] = 8'he2;
  bm[0*8192+150] = 8'h6f;
  bm[0*8192+151] = 8'hd7;
  bm[0*8192+152] = 8'h84;
  bm[0*8192+153] = 8'h23;
  bm[0*8192+154] = 8'h23;
  bm[0*8192+155] = 8'hdf;
  bm[0*8192+156] = 8'hc1;
  bm[0*8192+157] = 8'h35;
  bm[0*8192+158] = 8'h9e;
  bm[0*8192+159] = 8'h24;
  bm[0*8192+160] = 8'hd1;
  bm[0*8192+161] = 8'hcf;
  bm[0*8192+162] = 8'h94;
  bm[0*8192+163] = 8'h25;
  bm[0*8192+164] = 8'h96;
  bm[0*8192+165] = 8'h70;
  bm[0*8192+166] = 8'hd1;
  bm[0*8192+167] = 8'hdf;
  bm[0*8192+168] = 8'h40;
  bm[0*8192+169] = 8'h5e;
  bm[0*8192+170] = 8'hf1;
  bm[0*8192+171] = 8'h4c;
  bm[0*8192+172] = 8'ha7;
  bm[0*8192+173] = 8'h51;
  bm[0*8192+174] = 8'h34;
  bm[0*8192+175] = 8'hbe;
  bm[0*8192+176] = 8'h18;
  bm[0*8192+177] = 8'hd7;
  bm[0*8192+178] = 8'h4f;
  bm[0*8192+179] = 8'h03;
  bm[0*8192+180] = 8'h9c;
  bm[0*8192+181] = 8'hef;
  bm[0*8192+182] = 8'h1d;
  bm[0*8192+183] = 8'h64;
  bm[0*8192+184] = 8'h2f;
  bm[0*8192+185] = 8'h90;
  bm[0*8192+186] = 8'h37;
  bm[0*8192+187] = 8'hf9;
  bm[0*8192+188] = 8'h36;
  bm[0*8192+189] = 8'h0e;
  bm[0*8192+190] = 8'ha6;
  bm[0*8192+191] = 8'h2c;
  bm[0*8192+192] = 8'hab;
  bm[0*8192+193] = 8'h3c;
  bm[0*8192+194] = 8'h0e;
  bm[0*8192+195] = 8'h8a;
  bm[0*8192+196] = 8'h35;
  bm[0*8192+197] = 8'hb3;
  bm[0*8192+198] = 8'hac;
  bm[0*8192+199] = 8'hb1;
  bm[0*8192+200] = 8'h6c;
  bm[0*8192+201] = 8'h33;
  bm[0*8192+202] = 8'h29;
  bm[0*8192+203] = 8'h19;
  bm[0*8192+204] = 8'hff;
  bm[0*8192+205] = 8'hcc;
  bm[0*8192+206] = 8'h4a;
  bm[0*8192+207] = 8'hcb;
  bm[0*8192+208] = 8'hc0;
  bm[0*8192+209] = 8'h21;
  bm[0*8192+210] = 8'h99;
  bm[0*8192+211] = 8'h5b;
  bm[0*8192+212] = 8'hb1;
  bm[0*8192+213] = 8'h31;
  bm[0*8192+214] = 8'h41;
  bm[0*8192+215] = 8'h8b;
  bm[0*8192+216] = 8'hb4;
  bm[0*8192+217] = 8'hf5;
  bm[0*8192+218] = 8'h44;
  bm[0*8192+219] = 8'h76;
  bm[0*8192+220] = 8'h4a;
  bm[0*8192+221] = 8'h8d;
  bm[0*8192+222] = 8'hef;
  bm[0*8192+223] = 8'h35;
  bm[0*8192+224] = 8'heb;
  bm[0*8192+225] = 8'h15;
  bm[0*8192+226] = 8'ha1;
  bm[0*8192+227] = 8'hdf;
  bm[0*8192+228] = 8'h6f;
  bm[0*8192+229] = 8'hc6;
  bm[0*8192+230] = 8'he5;
  bm[0*8192+231] = 8'h55;
  bm[0*8192+232] = 8'h92;
  bm[0*8192+233] = 8'hc2;
  bm[0*8192+234] = 8'h24;
  bm[0*8192+235] = 8'hf8;
  bm[0*8192+236] = 8'ha0;
  bm[0*8192+237] = 8'h5b;
  bm[0*8192+238] = 8'h8f;
  bm[0*8192+239] = 8'hb1;
  bm[0*8192+240] = 8'hac;
  bm[0*8192+241] = 8'hdd;
  bm[0*8192+242] = 8'h97;
  bm[0*8192+243] = 8'h14;
  bm[0*8192+244] = 8'h9d;
  bm[0*8192+245] = 8'h57;
  bm[0*8192+246] = 8'hf7;
  bm[0*8192+247] = 8'h2b;
  bm[0*8192+248] = 8'hc5;
  bm[0*8192+249] = 8'hf4;
  bm[0*8192+250] = 8'ha1;
  bm[0*8192+251] = 8'ha7;
  bm[0*8192+252] = 8'he5;
  bm[0*8192+253] = 8'h06;
  bm[0*8192+254] = 8'hdf;
  bm[0*8192+255] = 8'h38;
  bm[0*8192+256] = 8'h4c;
  bm[0*8192+257] = 8'h35;
  bm[0*8192+258] = 8'h24;
  bm[0*8192+259] = 8'h89;
  bm[0*8192+260] = 8'h21;
  bm[0*8192+261] = 8'h70;
  bm[0*8192+262] = 8'h43;
  bm[0*8192+263] = 8'hc2;
  bm[0*8192+264] = 8'h66;
  bm[0*8192+265] = 8'hbc;
  bm[0*8192+266] = 8'h26;
  bm[0*8192+267] = 8'hcf;
  bm[0*8192+268] = 8'h15;
  bm[0*8192+269] = 8'h21;
  bm[0*8192+270] = 8'hee;
  bm[0*8192+271] = 8'h6a;
  bm[0*8192+272] = 8'ha5;
  bm[0*8192+273] = 8'h18;
  bm[0*8192+274] = 8'h96;
  bm[0*8192+275] = 8'h2c;
  bm[0*8192+276] = 8'h4f;
  bm[0*8192+277] = 8'h20;
  bm[0*8192+278] = 8'hbf;
  bm[0*8192+279] = 8'hb5;
  bm[0*8192+280] = 8'ha5;
  bm[0*8192+281] = 8'hb7;
  bm[0*8192+282] = 8'hff;
  bm[0*8192+283] = 8'hec;
  bm[0*8192+284] = 8'h77;
  bm[0*8192+285] = 8'ha9;
  bm[0*8192+286] = 8'hbf;
  bm[0*8192+287] = 8'hb9;
  bm[0*8192+288] = 8'h87;
  bm[0*8192+289] = 8'hac;
  bm[0*8192+290] = 8'hcf;
  bm[0*8192+291] = 8'h36;
  bm[0*8192+292] = 8'h6d;
  bm[0*8192+293] = 8'hd9;
  bm[0*8192+294] = 8'h11;
  bm[0*8192+295] = 8'he8;
  bm[0*8192+296] = 8'h2c;
  bm[0*8192+297] = 8'h0a;
  bm[0*8192+298] = 8'h2b;
  bm[0*8192+299] = 8'h8c;
  bm[0*8192+300] = 8'h99;
  bm[0*8192+301] = 8'h20;
  bm[0*8192+302] = 8'hfc;
  bm[0*8192+303] = 8'hd4;
  bm[0*8192+304] = 8'h48;
  bm[0*8192+305] = 8'h11;
  bm[0*8192+306] = 8'h38;
  bm[0*8192+307] = 8'hb1;
  bm[0*8192+308] = 8'hd5;
  bm[0*8192+309] = 8'hb0;
  bm[0*8192+310] = 8'h9e;
  bm[0*8192+311] = 8'h2d;
  bm[0*8192+312] = 8'hef;
  bm[0*8192+313] = 8'h2d;
  bm[0*8192+314] = 8'h3e;
  bm[0*8192+315] = 8'h7a;
  bm[0*8192+316] = 8'h72;
  bm[0*8192+317] = 8'h67;
  bm[0*8192+318] = 8'he1;
  bm[0*8192+319] = 8'h15;
  bm[0*8192+320] = 8'hf8;
  bm[0*8192+321] = 8'h0d;
  bm[0*8192+322] = 8'h6f;
  bm[0*8192+323] = 8'hac;
  bm[0*8192+324] = 8'h1e;
  bm[0*8192+325] = 8'he4;
  bm[0*8192+326] = 8'h81;
  bm[0*8192+327] = 8'h99;
  bm[0*8192+328] = 8'h14;
  bm[0*8192+329] = 8'hba;
  bm[0*8192+330] = 8'h49;
  bm[0*8192+331] = 8'hfd;
  bm[0*8192+332] = 8'hd7;
  bm[0*8192+333] = 8'hdd;
  bm[0*8192+334] = 8'hbf;
  bm[0*8192+335] = 8'h7c;
  bm[0*8192+336] = 8'h25;
  bm[0*8192+337] = 8'h18;
  bm[0*8192+338] = 8'h72;
  bm[0*8192+339] = 8'h98;
  bm[0*8192+340] = 8'hfb;
  bm[0*8192+341] = 8'h48;
  bm[0*8192+342] = 8'hf8;
  bm[0*8192+343] = 8'hb4;
  bm[0*8192+344] = 8'h88;
  bm[0*8192+345] = 8'h47;
  bm[0*8192+346] = 8'h02;
  bm[0*8192+347] = 8'hf8;
  bm[0*8192+348] = 8'hfb;
  bm[0*8192+349] = 8'h0a;
  bm[0*8192+350] = 8'h58;
  bm[0*8192+351] = 8'h43;
  bm[0*8192+352] = 8'hea;
  bm[0*8192+353] = 8'h5c;
  bm[0*8192+354] = 8'h4e;
  bm[0*8192+355] = 8'heb;
  bm[0*8192+356] = 8'h9e;
  bm[0*8192+357] = 8'hc6;
  bm[0*8192+358] = 8'hc7;
  bm[0*8192+359] = 8'h5d;
  bm[0*8192+360] = 8'haa;
  bm[0*8192+361] = 8'h8b;
  bm[0*8192+362] = 8'h7a;
  bm[0*8192+363] = 8'h9a;
  bm[0*8192+364] = 8'hdd;
  bm[0*8192+365] = 8'ha9;
  bm[0*8192+366] = 8'hf3;
  bm[0*8192+367] = 8'hb4;
  bm[0*8192+368] = 8'h39;
  bm[0*8192+369] = 8'h61;
  bm[0*8192+370] = 8'h33;
  bm[0*8192+371] = 8'h84;
  bm[0*8192+372] = 8'hc0;
  bm[0*8192+373] = 8'hde;
  bm[0*8192+374] = 8'hc0;
  bm[0*8192+375] = 8'h15;
  bm[0*8192+376] = 8'ha6;
  bm[0*8192+377] = 8'h86;
  bm[0*8192+378] = 8'h60;
  bm[0*8192+379] = 8'h8c;
  bm[0*8192+380] = 8'h8f;
  bm[0*8192+381] = 8'he3;
  bm[0*8192+382] = 8'h12;
  bm[0*8192+383] = 8'h1e;
  bm[0*8192+384] = 8'h3a;
  bm[0*8192+385] = 8'h19;
  bm[0*8192+386] = 8'h05;
  bm[0*8192+387] = 8'ha5;
  bm[0*8192+388] = 8'hb0;
  bm[0*8192+389] = 8'h8a;
  bm[0*8192+390] = 8'hc3;
  bm[0*8192+391] = 8'hb3;
  bm[0*8192+392] = 8'hc9;
  bm[0*8192+393] = 8'h30;
  bm[0*8192+394] = 8'h6f;
  bm[0*8192+395] = 8'hf6;
  bm[0*8192+396] = 8'h4b;
  bm[0*8192+397] = 8'hac;
  bm[0*8192+398] = 8'h69;
  bm[0*8192+399] = 8'h22;
  bm[0*8192+400] = 8'he6;
  bm[0*8192+401] = 8'h49;
  bm[0*8192+402] = 8'hdb;
  bm[0*8192+403] = 8'h07;
  bm[0*8192+404] = 8'he3;
  bm[0*8192+405] = 8'hdd;
  bm[0*8192+406] = 8'h7e;
  bm[0*8192+407] = 8'hff;
  bm[0*8192+408] = 8'h6f;
  bm[0*8192+409] = 8'h39;
  bm[0*8192+410] = 8'h89;
  bm[0*8192+411] = 8'hbb;
  bm[0*8192+412] = 8'ha1;
  bm[0*8192+413] = 8'ha2;
  bm[0*8192+414] = 8'hba;
  bm[0*8192+415] = 8'h13;
  bm[0*8192+416] = 8'h4d;
  bm[0*8192+417] = 8'h5c;
  bm[0*8192+418] = 8'h39;
  bm[0*8192+419] = 8'h5a;
  bm[0*8192+420] = 8'ha0;
  bm[0*8192+421] = 8'hef;
  bm[0*8192+422] = 8'h5f;
  bm[0*8192+423] = 8'h96;
  bm[0*8192+424] = 8'h4b;
  go(6,5,0,9,0,0,0,80,0); $display("upkt0: %0d clk", cyc-c0); n=n+1;
  expv = 8192'h0000068efffff681fffff83000000a5dfffffd48fffffcbcfffff22b00000d5ffffff88f00000b1bfffff801fffff813fffff43a00000e0afffff5b1000009de000002cbfffffed1fffff4c9fffffcf4fffffc99ffffff1efffffa7b00000afb00000cd9000007880000068ffffff708fffff73f00000e57ffffff5200000f22fffff7f0ffffff33ffffff64fffff4b1000008adfffff89afffffc2c0000045600000448fffff0e60000008bfffffb1bfffff62cffffff2a00000fa9fffff40800000fb8fffff1defffff58400000b71fffff8d0fffff37a00000ed5fffff341fffff446fffff00b00000b2300000eb7fffffcfdfffff6f9fffffa9d000000f3fffff0fefffff87bfffffc470000085dfffff3a5fffff4350000030bffffff2bfffff9d900000fbb00000b960000003e00000ecd00000cf6fffff7af0000031800000dc500000a4cfffff499fffff5380000008d000000160000044100000301fffff90cfffff92afffff07000000b0efffff6d4000009d7000004a9000001df00000d47fffff366fffff1cd000003dc000009200000079e000006dffffffab4000008e5fffff3e5fffffd2dfffff5e10000067600000503fffff544fffff2ecfffffd05fffff94efffff739fffffa4600000e10000006d0fffffb6efffffa1bfffff733fffff082ffffff76fffff14d0000042100000caefffffc4e00000b0bfffff96f000002fcfffff728fffffa47fffffdbdffffffcefffff5aa0000030100000cdb00000b33fffff9a8fffff5350000099500000d7dfffffe1b000004d4fffffb3ffffff725fffff365fffff6fefffff13800000885fffff32000000cb1fffff51d00000d08fffff5d8fffff58cfffff61efffff87000000902fffffe90fffffd3cfffff9ad00000818fffffdb7fffff395ffffff89fffff6e700000c7cfffff513fffff077fffff1adfffffa8a00000daa00000055fffffb59fffffe280000038300000f270000013200000873fffff77000000a2900000d3afffff2b70000034afffff343fffff8a6000001ee00000552fffff161fffff02cfffffb48fffffe31000003fdfffffec1fffff7aefffffb3700000c17ffffffe8fffff35afffffb0e00000492fffffba600000da4000002a500000224fffff1b50000076600000473000003e1fffff95400000357fffff2b600000e470000076bfffff7f1fffff294000005c3fffff4e4fffff48afffff3e200000947000008080000046f000001f1ffffff7700000965fffffc04fffff19d00000a86fffff61c00000dd3000008d70000098e00000c42fffffa3f000007e7000000b3fffff4e7fffff5eb000006c8fffffce5fffff6dc000004ec000003d100000d18000000b0fffffc6f00000572ffffff1cfffffebdffffffb6fffffea2fffff5aefffff05800000f2d;
  for (i=0;i<256;i=i+1) if (pm.mem[5*256+i] !== expv[32*i +: 32]) begin fails=fails+1; if (fails<6) $display("FAIL upkt0 coeff %0d got %h exp %h", i, pm.mem[5*256+i], expv[32*i +: 32]); end
  expv = 8192'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000;
  for (i=0;i<256;i=i+1) pm.mem[3*256+i] = expv[32*i +: 32];
  go(7,3,1,500,0,0,0,20,2); $display("pkh: %0d clk", cyc-c0); n=n+1;
  if (bm[1*8192+500] !== 8'h02) begin fails=fails+1; $display("FAIL pkh pos 0"); end
  if (bm[1*8192+501] !== 8'h0c) begin fails=fails+1; $display("FAIL pkh pos 1"); end
  if (bm[1*8192+502] !== 8'h4c) begin fails=fails+1; $display("FAIL pkh pos 2"); end
  if (bm[1*8192+503] !== 8'h7c) begin fails=fails+1; $display("FAIL pkh pos 3"); end
  if (bm[1*8192+504] !== 8'h93) begin fails=fails+1; $display("FAIL pkh pos 4"); end
  if (bm[1*8192+505] !== 8'h9f) begin fails=fails+1; $display("FAIL pkh pos 5"); end
  if (bm[1*8192+506] !== 8'ha3) begin fails=fails+1; $display("FAIL pkh pos 6"); end
  if (bm[1*8192+522] !== 8'd7) begin fails=fails+1; $display("FAIL pkh count"); end
  if (fails==0) $display("ALL PASS (%0d ops)", n); else $display("FAILED (%0d)", fails);
  $finish;
end
initial begin #400000000 $display("TIMEOUT"); $finish; end
endmodule
