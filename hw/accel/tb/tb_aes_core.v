`timescale 1ns/1ps
module tb_aes_core;
reg clk=0, rst_n=0; always #5 clk=~clk;
reg key_we=0; reg [2:0] key_wi=0; reg [31:0] key_wd=0; reg key_go=0; wire key_ready;
reg blk_start=0, dec=0, sh_en=0; reg [7:0] sh_in=0; wire blk_done, busy; wire [7:0] sh_out; wire [127:0] state;
aes_core dut(.clk(clk),.rst_n(rst_n),.key_we(key_we),.key_wi(key_wi),.key_wd(key_wd),.key_go(key_go),.key_ready(key_ready),
  .blk_start(blk_start),.dec(dec),.blk_done(blk_done),.sh_en(sh_en),.sh_in(sh_in),.sh_out(sh_out),.state(state),.busy(busy));
integer fails=0, n=0, j, c0, cyc=0; reg [127:0] got; always @(posedge clk) cyc<=cyc+1;
task setkey(input [255:0] k); begin
  for (j=0;j<8;j=j+1) begin @(negedge clk); key_we=1; key_wi=j; key_wd=k[255-32*j -: 32]; end
  @(negedge clk); key_we=0; @(negedge clk); key_go=1; c0=cyc; @(negedge clk); key_go=0; wait(key_ready); @(negedge clk);
  if (n==0) $display("key expansion: %0d clk", cyc-c0); end endtask
task blk(input d, input [127:0] i, input [127:0] exp); begin
  for (j=0;j<16;j=j+1) begin @(negedge clk); sh_en=1; sh_in=i[127-8*j -: 8]; end @(negedge clk); sh_en=0;
  @(negedge clk); dec=d; blk_start=1; c0=cyc; @(negedge clk); blk_start=0; wait(blk_done); @(negedge clk);
  if (n==0) $display("block: %0d clk", cyc-c0);
  for (j=0;j<16;j=j+1) begin got[127-8*j -: 8]=sh_out; @(negedge clk); sh_en=1; sh_in=8'h00; @(negedge clk); sh_en=0; end
  if (got!==exp) begin fails=fails+1; $display("FAIL dec=%0b in=%h got %h exp %h",d,i,got,exp); end n=n+1; end endtask
initial begin #30 rst_n=1; #30;
  setkey(256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4);
  blk(0,128'h6bc1bee22e409f96e93d7e117393172a,128'hf3eed1bdb5d2a03c064b5a7e3db181f8); blk(1,128'hf3eed1bdb5d2a03c064b5a7e3db181f8,128'h6bc1bee22e409f96e93d7e117393172a);
  setkey(256'ha54dca182530bb1d6d132cded6237b2ed91e3f721fcb1971174494d6493c9d5c);
  blk(0,128'h3460be31201e69fedaa0eee8b9997f5c,128'hb754afbe2b8462d27ea30e5fb30a9473); blk(1,128'hb754afbe2b8462d27ea30e5fb30a9473,128'h3460be31201e69fedaa0eee8b9997f5c);
  setkey(256'h7c2999fdafe593253cd654af4dfad71427a0aeb3fee9232f8af2211f9ee491c5);
  blk(0,128'hb10becb5563bfc1e6f93427ecbc8fe29,128'h14268f6cd9c7807f90170bd5a7cbe2b7); blk(1,128'h14268f6cd9c7807f90170bd5a7cbe2b7,128'hb10becb5563bfc1e6f93427ecbc8fe29);
  setkey(256'h55e5cd8e46dc8ed4b7c2764d2a5a4d767706f85d8690024ad6bda3401be9c8cb);
  blk(0,128'hccc935f6cd1f61226ae15338ae1a3400,128'h89109709390c03817089889e8a198bb7); blk(1,128'h89109709390c03817089889e8a198bb7,128'hccc935f6cd1f61226ae15338ae1a3400);
  setkey(256'h4d33ba0d246ac04c81b1baf23e3bf9eef5f79f2b4934af87f5520b69b94b0d98);
  blk(0,128'h2e85bb55b672a872637acd7466fcb60e,128'hf4d47617429204027be73717b862c37b); blk(1,128'hf4d47617429204027be73717b862c37b,128'h2e85bb55b672a872637acd7466fcb60e);
  setkey(256'h0e8ff18463b0e4b2ba29703474f064ac68f700f5b02b3dc666f45bdeaa2ccaed);
  blk(0,128'hcd2b5157410e4dee4af2b34f430a0734,128'h4eb1356eab75ae0b428c011ce7c899b9); blk(1,128'h4eb1356eab75ae0b428c011ce7c899b9,128'hcd2b5157410e4dee4af2b34f430a0734);
  setkey(256'h47de636c0e806c957ba684d6431fb5ead7424d09e15d024c5848f23d1fa6f736);
  blk(0,128'h1d7f618d1532e70e20e2a6668de7f47e,128'hbfc96d32e0ba9741453546e1c91bb576); blk(1,128'hbfc96d32e0ba9741453546e1c91bb576,128'h1d7f618d1532e70e20e2a6668de7f47e);
  setkey(256'h8467e546d53ec8e2a1257bdb256c9b3e4fbb498146ef7030cbf9537252dccead);
  blk(0,128'hd764b6a32fbb09adeae109c4a9972039,128'hd1460a647b4a21f9b5c542eb9463830e); blk(1,128'hd1460a647b4a21f9b5c542eb9463830e,128'hd764b6a32fbb09adeae109c4a9972039);
  setkey(256'h75352b878b145c8a42d884cf4cfda72d8e1d5dd92589082d852a7122873ee805);
  blk(0,128'hadd58942167a385286195c679f9c6994,128'h2f3f60cf31f7ab209dfe0129c6c6e9dc); blk(1,128'h2f3f60cf31f7ab209dfe0129c6c6e9dc,128'hadd58942167a385286195c679f9c6994);
  setkey(256'he45b8ab1098012070961f37de436ddfdc99d6e75af6547cfb11b42072482dc53);
  blk(0,128'h1c2bc3907c9617eb5e5089e40186baa8,128'hf836063c7c75c13f5666229a2c23fbfd); blk(1,128'hf836063c7c75c13f5666229a2c23fbfd,128'h1c2bc3907c9617eb5e5089e40186baa8);
  setkey(256'ha57d119e6fb65d00abc32af38e667f022e872d49cc15c90b999b772b4fc7a6fd);
  blk(0,128'h4c914a16db4708752b0f1544b835c0e7,128'h461c0d03ce72a9fe95d6ecdde7658459); blk(1,128'h461c0d03ce72a9fe95d6ecdde7658459,128'h4c914a16db4708752b0f1544b835c0e7);
  setkey(256'h19097dfa8701e9232f21f2812687786976ebfcc327f5931765274ba9829b4406);
  blk(0,128'hf61ff889326ffa9492edeeee3c669f2b,128'haeb080bb7b20b7dd0a3b108dbf6d6544); blk(1,128'haeb080bb7b20b7dd0a3b108dbf6d6544,128'hf61ff889326ffa9492edeeee3c669f2b);
  setkey(256'hf20894ea27e689c66b6b262e4886b8438f39ba76fef8c90c5101fbe6cf9a48d5);
  blk(0,128'hb0c0a13da900a6adcb3d64069481be21,128'h0ebdce37b3d35af42e757c2cb3eebbca); blk(1,128'h0ebdce37b3d35af42e757c2cb3eebbca,128'hb0c0a13da900a6adcb3d64069481be21);
  setkey(256'hc9c727b8db8c188f341a924c7f88dfa161bfdb0ecc682919d2e64692f8194157);
  blk(0,128'hf1d4af90988285cf7a9af7c93d555226,128'hf9401f7c60836e2974ae8803739d8802); blk(1,128'hf9401f7c60836e2974ae8803739d8802,128'hf1d4af90988285cf7a9af7c93d555226);
  setkey(256'h6afe70e7aae6da47627c2e59af2ea37abc84670ad3c4d36bc08aad1fff8eb840);
  blk(0,128'h6e2f8a7fc4cce4dd9f0b4110d9f2fa00,128'hcaed3a39eecc8158fb100802d6787285); blk(1,128'hcaed3a39eecc8158fb100802d6787285,128'h6e2f8a7fc4cce4dd9f0b4110d9f2fa00);
  setkey(256'h25c8efe57f37724f4d37ea2b14004077139b4180df3932249962c6857200059a);
  blk(0,128'heb8ea17cf3787e0ed29d1c0b63ffd729,128'h1601a3f68cde9dddcc2e3b80c4100ff0); blk(1,128'h1601a3f68cde9dddcc2e3b80c4100ff0,128'heb8ea17cf3787e0ed29d1c0b63ffd729);
  setkey(256'h8374d9bd74fc11add7b9ca6503952269fd669f6376ee71879737fd5f72f8d51c);
  blk(0,128'h4ac91b6d0c48d41a1e5ec9e6a0392854,128'hafc1639f27ceb96ecb09c2a1f0bda1c0); blk(1,128'hafc1639f27ceb96ecb09c2a1f0bda1c0,128'h4ac91b6d0c48d41a1e5ec9e6a0392854);
  setkey(256'ha8615eef109fc1bfa9e2563701288f29b3d73f6ac2b69edd2c19f264bee462a5);
  blk(0,128'hbaf20fd27ecf14c011ed201f836320ad,128'he74c8902bfc9679aa29e1e8709ecd035); blk(1,128'he74c8902bfc9679aa29e1e8709ecd035,128'hbaf20fd27ecf14c011ed201f836320ad);
  setkey(256'hb98bab1686a28d9801210c7736f3eec580dcfc43fe5d049b4d78a7a3ebb92865);
  blk(0,128'hc8517ed02111f6a652da3524872b6a31,128'h44b2c589b1c2732918ce3eed3a559386); blk(1,128'h44b2c589b1c2732918ce3eed3a559386,128'hc8517ed02111f6a652da3524872b6a31);
  setkey(256'hd7ffe4587744d5eb783e96968f89be828565e07e5f7d784e9060a721ca807d76);
  blk(0,128'h33ed123402f376e5bf1496773d196163,128'hb75388ca00fc3f113bad1413d18e2e64); blk(1,128'hb75388ca00fc3f113bad1413d18e2e64,128'h33ed123402f376e5bf1496773d196163);
  setkey(256'h26be5be5850336b36f13bcae48166882136805a7d1be5e9f276810fdf720d033);
  blk(0,128'hca4f2e53cb8ad1919dd51a9fb6d4d509,128'h32dc4dc8ea920b497b7c6dcdd79b0fb4); blk(1,128'h32dc4dc8ea920b497b7c6dcdd79b0fb4,128'hca4f2e53cb8ad1919dd51a9fb6d4d509);
  if (fails==0) $display("ALL PASS (%0d blocks)", n); else $display("FAILED %0d", fails);
  $finish;
end
initial begin #50000000 $display("TIMEOUT"); $finish; end
endmodule
