`timescale 1ns/1ps
// Runs the ML-DSA engine (pq_core) on vectors from tb/vec_pq and compares status and response bytes.
module tb_pq_core;
reg clk=0, rst_n=0; always #5 clk=~clk;
reg go=0; reg [7:0] cmd=0; reg [15:0] len=0; wire done, busy; wire [7:0] status; wire [15:0] tx_len;
wire [12:0] rx_ra, tx_wa, rx_wa, tx_ra; wire rx_we, tx_we; wire [7:0] rx_wd, tx_wd; reg [7:0] rx_rq, tx_rq;
reg use_xs = 0; reg [31:0] xs = 32'h2545F491; reg trng_valid=0; reg [31:0] trng_data=0; integer tcnt=0, tw=0;
wire r_start, r_done, r_flag, r_bus, rb_we; wire [7:0] r_op, rb_wd, br_data; wire [5:0] r_a, r_b, r_c, r_d; wire [31:0] r_imm; wire [1:0] rb_ws, rb_rs; wire [12:0] rb_wa, rb_ra;
pq_core #(.MASTER(256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f), .UID(128'ha0a1a2a3a4a5a6a7a8a9aaabacadaeaf))
    dut (.clk(clk), .rst_n(rst_n), .go(go), .cmd(cmd), .len(len), .done(done), .status(status), .tx_len(tx_len), .busy(busy),
         .rx_ra(rx_ra), .rx_rq(rx_rq), .rx_we(rx_we), .rx_wa(rx_wa), .rx_wd(rx_wd), .tx_we(tx_we), .tx_wa(tx_wa), .tx_wd(tx_wd), .tx_ra(tx_ra), .tx_rq(tx_rq),
         .trng_valid(trng_valid), .trng_data(trng_data),
         .r_start_o(r_start), .r_op_o(r_op), .r_a_o(r_a), .r_b_o(r_b), .r_c_o(r_c), .r_d_o(r_d), .r_imm_o(r_imm), .r_done_i(r_done), .r_flag_i(r_flag), .r_bus_i(r_bus),
         .rb_we_i(rb_we), .rb_ws_i(rb_ws), .rb_wa_i(rb_wa), .rb_wd_i(rb_wd), .rb_rs_i(rb_rs), .rb_ra_i(rb_ra), .br_data_o(br_data));
bn_engine eng (.clk(clk), .rst_n(rst_n), .start(r_start), .op(r_op), .ra(r_a), .rb(r_b), .rc(r_c), .rd(r_d), .imm0(r_imm), .done(r_done), .flag(r_flag), .bus_busy(r_bus),
    .bw_en(rb_we), .bw_space(rb_ws), .bw_addr(rb_wa), .bw_data(rb_wd), .br_space(rb_rs), .br_addr(rb_ra), .br_data(br_data), .trng_valid(trng_valid), .trng_data(trng_data),
    .e_start(1'b0), .e_op(4'd0), .e_d(7'd0), .e_a(7'd0), .e_b(7'd0), .e_msel(2'd0), .e_done(), .e_lt(),
    .x_ra(11'd0), .x_we(1'b0), .x_wa(11'd0), .x_wd(16'd0), .x_rq(), .busy_o());
reg [7:0] rxm [0:8191]; reg [7:0] txm [0:8191];
always @(posedge clk) begin
    if (rx_we) rxm[rx_wa] <= rx_wd;
    if (tx_we) txm[tx_wa] <= tx_wd;
    rx_rq <= rxm[rx_ra]; tx_rq <= txm[tx_ra];
end
// TRNG model: always valid; 32-bit words made of the counter bytes 100,101,102,... (little endian); advances when the engine consumes a word
always @(posedge clk) begin
    trng_valid <= 1;
    trng_data <= {8'd103 + 8'd4*tw[5:0], 8'd102 + 8'd4*tw[5:0], 8'd101 + 8'd4*tw[5:0], 8'd100 + 8'd4*tw[5:0]};
    if (trng_valid && dut.bytes.st == 4'd14) tw <= tw + 1;      // S_RNGW consumed the word
    if (use_xs) begin
        trng_data <= xs;
        if (trng_valid && (eng.st == 7'd39 || dut.bytes.st == 4'd14)) xs <= xs ^ (xs << 13) ^ ((xs ^ (xs << 13)) >> 17) ^ ((xs ^ (xs << 13) ^ ((xs ^ (xs << 13)) >> 17)) << 5);
    end
end
reg [7:0] rq [0:8191]; reg [7:0] ex [0:8191]; reg [8*64-1:0] vd; integer dumpf;
integer nt, t, fi, rl, el, est, c, j, bad, fails, rc, cmdv, c0, cyc=0; reg [8*40-1:0] name; reg [8*64-1:0] fn;
always @(posedge clk) cyc <= cyc + 1;
initial begin
    use_xs = $test$plusargs("xs");
    fails = 0; #200; rst_n = 1; repeat (100) @(posedge clk);
    if (!$value$plusargs("vec=%s", vd)) vd = "tb/vec_pq";
    $sformat(fn, "%0s/index.txt", vd); fi = $fopen(fn, "r"); rc = $fscanf(fi, "%d\n", nt);
    for (t = 0; t < nt; t = t + 1) begin
        rc = $fscanf(fi, "%d %d %d %d %s\n", cmdv, rl, est, el, name);
        $sformat(fn, "%0s/req_%0d.hex", vd, t); $readmemh(fn, rq);
        $sformat(fn, "%0s/exp_%0d.hex", vd, t); $readmemh(fn, ex);
        for (j = 0; j < rl; j = j + 1) rxm[j] = rq[j];
        tw = 0; c0 = cyc;
        @(negedge clk); cmd = cmdv; len = rl; go = 1; @(negedge clk); go = 0;
        wait (done); repeat (3) @(negedge clk);
        bad = (status != est);
        if (est == 0) begin
            if (tx_len != el) bad = bad + 1;
            for (j = 0; j < el; j = j + 1) if (txm[j] !== ex[j]) begin bad = bad + 1; if (bad < 6) $display("   byte %0d got %h exp %h", j, txm[j], ex[j]); end
        end
        if ($test$plusargs("dump")) begin $sformat(fn, "%0s/got_%0d.hex", vd, t); dumpf = $fopen(fn, "w"); for (j = 0; j < tx_len; j = j + 1) $fwrite(dumpf, "%02x\n", txm[j]); $fclose(dumpf); end
        if (bad) begin fails = fails + 1; $display("FAIL %0s (status %0d, len %0d, %0d bad)", name, status, tx_len, bad); end
        else $display("PASS %0s  (%0d clk, %0d bytes)", name, cyc - c0, tx_len);
    end
    if (fails == 0) $display("ALL PASS"); else $display("FAILED %0d", fails);
    $finish;
end
initial begin #400000000000 $display("TIMEOUT"); $finish; end
endmodule
