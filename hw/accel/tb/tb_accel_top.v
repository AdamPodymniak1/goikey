`timescale 1ns/1ps
// Link-level testbench: sends request frames bit-by-bit over the UART model and
// checks the response frames byte-by-byte (with an optional compare mask).
module tb_accel_top;
parameter CPB = 18; parameter USE_SPI = 0; parameter HAS_AES = 1; parameter HAS_SYM = 0; parameter HAS_ECC = 0; parameter HAS_PQ = 0;
reg clk = 0; always #18.518 clk = ~clk;         // 27 MHz
reg btn = 0; wire led0, led1, led2, utx; reg urx = 1;
reg sck = 0, mosi = 0, csn = 1; wire miso;
accel_top #(.CPB(CPB), .HAS_AES(HAS_AES), .HAS_SYM(HAS_SYM), .HAS_ECC(HAS_ECC), .HAS_PQ(HAS_PQ)) dut (.clk(clk), .btn_s1(btn), .led0(led0), .led1(led1), .led2(led2),
                            .uart_tx_pin(utx), .uart_rx_pin(urx), .spi_sck(sck), .spi_mosi(mosi), .spi_cs_n(csn), .spi_miso(miso));

// UART receiver model
reg [7:0] rxq [0:16383]; integer rxn = 0; reg [7:0] rsh; integer ri;
initial forever begin
    @(negedge utx);
    repeat (CPB + CPB/2) @(posedge clk);
    for (ri = 0; ri < 8; ri = ri + 1) begin rsh = {utx, rsh[7:1]}; repeat (CPB) @(posedge clk); end
    rxq[rxn] = rsh; rxn = rxn + 1;
end
// SPI master (mode 0), SCK = clk/12
task spi_xfer(input [7:0] o, output [7:0] i); integer k; reg [7:0] r; begin
    for (k = 7; k >= 0; k = k - 1) begin
        mosi = o[k]; repeat (6) @(posedge clk); sck = 1; r = {r[6:0], miso}; repeat (6) @(posedge clk); sck = 0;
    end
    i = r;
end endtask
reg [7:0] spi_i;
task send(input [7:0] b); integer k; begin
    urx = 0; repeat (CPB) @(posedge clk);
    for (k = 0; k < 8; k = k + 1) begin urx = b[k]; repeat (CPB) @(posedge clk); end
    urx = 1; repeat (CPB) @(posedge clk);
end endtask

reg [7:0] rq [0:16383]; reg [7:0] ex [0:16383]; reg [7:0] mk [0:16383];
integer nt, t, fi, rl, el, j, bad, fails, total_clk, c0, cyc = 0, rc; reg [8*40-1:0] name;
reg [8*64-1:0] fn; reg [8*32-1:0] vecdir;
always @(posedge clk) cyc <= cyc + 1;
initial begin
    fails = 0; #200; urx = 1; repeat (80000) @(posedge clk);
    if (!$value$plusargs("VEC=%s", vecdir)) vecdir = "tb/vec";
    $sformat(fn, "%0s/index.txt", vecdir); fi = $fopen(fn, "r");
    rc = $fscanf(fi, "%d\n", nt); if ($value$plusargs("NT=%d", t)) nt = t;
    for (t = 0; t < nt; t = t + 1) begin
        rc = $fscanf(fi, "%d %d %s\n", rl, el, name);
        $sformat(fn, "%0s/req_%0d.hex", vecdir, t); $readmemh(fn, rq);
        $sformat(fn, "%0s/exp_%0d.hex", vecdir, t); $readmemh(fn, ex);
        $sformat(fn, "%0s/msk_%0d.hex", vecdir, t); $readmemh(fn, mk);
        rxn = 0; c0 = cyc;
        $display("t=%0t sending %0s (%0d bytes)", $time, name, rl);
        if (USE_SPI) begin
            $display("SPI: sending %0d bytes", rl); csn = 0; repeat (8) @(posedge clk);
            for (j = 0; j < rl; j = j + 1) spi_xfer(rq[j], spi_i);
            repeat (8) @(posedge clk); csn = 1; repeat (8) @(posedge clk);
            // poll for the response: clock filler bytes until the start byte 0x5A, then read the rest
            begin : poll
                integer tries; tries = 0; spi_i = 0;
                while (spi_i !== 8'h5A && tries < 20000) begin
                    csn = 0; repeat (4) @(posedge clk); spi_xfer(8'h00, spi_i); repeat (4) @(posedge clk); csn = 1; repeat (4) @(posedge clk);
                    if (tries < 4) $display("poll %0d got %h", tries, spi_i);
                    tries = tries + 1;
                end
                csn = 0; // keep CS low while reading the frame (the 0x5A already read is the first frame byte)
            end
            $display("SPI: first resp byte %h", spi_i); rxq[0] = spi_i; rxn = 1;
            repeat (4) @(posedge clk);
            // the byte after 0x5A is already shifting: continue clocking within the same CS-low period is not possible
            // after a deassert, so re-read: the slave already consumed 0x5A, the next byte follows
            for (j = 1; j < el; j = j + 1) begin spi_xfer(8'h00, spi_i); rxq[j] = spi_i; rxn = rxn + 1; end
            repeat (8) @(posedge clk); csn = 1;
        end else
        for (j = 0; j < rl; j = j + 1) send(rq[j]);
        $display("t=%0t sent; rxn=%0d", $time, rxn);
        // wait for the full response (or timeout)
        j = 0; while (rxn < el && j < 60000000) begin @(posedge clk); j = j + 1; end
        repeat (4 * CPB) @(posedge clk);
        bad = (rxn != el);
        for (j = 0; j < el && j < rxn; j = j + 1) if (mk[j] && rxq[j] !== ex[j]) bad = bad + 1;
        if (bad) begin fails = fails + 1; $display("FAIL %0s (rx %0d of %0d bytes, %0d bad)", name, rxn, el, bad);
            if (rxn >= 4) $display("   status=%0d  rx: %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h", rxq[1], rxq[0],rxq[1],rxq[2],rxq[3],rxq[4],rxq[5],rxq[6],rxq[7],rxq[8],rxq[9],rxq[10],rxq[11],rxq[12],rxq[13],rxq[14],rxq[15],rxq[16],rxq[17]); end
        else $display("PASS %0s  (%0d clk)", name, cyc - c0);
    end
    if (fails == 0) $display("ALL PASS (%0d link tests)", nt); else $display("FAILED %0d of %0d", fails, nt);
    $finish;
end
endmodule
