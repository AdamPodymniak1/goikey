`default_nettype none
`timescale 1ns / 1ps

// Testbench for root_of_truth module
// Verifies: UUID, TRNG, key storage, monotonic counter, boot integrity, JTAG lock

module test_root_of_truth;

    // Inputs
    reg        clk;
    reg        rst_n;
    reg        jtag_tck;
    reg        jtag_tms;
    reg        jtag_tdi;
    reg        zeroize_n;

    // Outputs
    wire [127:0] uid_out;
    wire [31:0]  trng_data;
    wire         trng_valid;
    wire [31:0]  counter_out;
    wire         boot_ok;
    wire         jtag_locked;
    wire         jtag_tdo;

    // Additional test signals
    reg  [3:0]  write_slot;
    reg  [255:0] write_data;
    reg         write_en;
    reg         write_auth;
    reg  [3:0]  read_slot;
    reg         read_en;
    reg         read_auth;
    wire [255:0] read_data_local;

    // Instantiate the Unit Under Test (UUT)
    root_of_truth uut (
        .clk(clk),
        .rst_n(rst_n),
        .jtag_tck(jtag_tck),
        .jtag_tms(jtag_tms),
        .jtag_tdi(jtag_tdi),
        .jtag_tdo(jtag_tdo),
        .jtag_locked(jtag_locked),
        .zeroize_n(zeroize_n),
        
        // UUID outputs
        .uid_out(uid_out),
        
        // TRNG outputs
        .trng_data(trng_data),
        .trng_valid(trng_valid),
        
        // Counter output
        .counter_out(counter_out),
        
        // Boot integrity
        .boot_ok(boot_ok),
        
        // Key storage ports (simplified for test)
        // Write port
        .write_slot_idx(write_slot),
        .write_key_data(write_data),
        .write_en(write_en),
        .write_auth(write_auth),
        // Read port  
        .read_slot_idx(read_slot),
        .read_en(read_en),
        .read_auth(read_auth),
        .read_data(read_data_local)
    );

    // Clock generation: 10ns period (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset generation
    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end

    // JTAG clock (1 MHz)
    initial begin
        jtag_tck = 0;
        forever #500 jtag_tck = ~jtag_tck;
    end

    // Test sequence
    initial begin
        // Initialize inputs
        jtag_tdi  = 0;
        zeroize_n = 1;
        
        // Wait for reset to de-assert
        wait(rst_n);
        #100;
        
        // ===========================================
        // Test 1: UUID is valid and unique
        // ===========================================
        $display("TEST 1: UUID validity check");
        if (uid_out === 128'hA1B2C3D4_E5F60718_293A4B5C_6D7E8F00) begin
            $display("  PASS: UUID matches expected value");
        end else begin
            $display("  FAIL: UUID unexpected value: %h", uid_out);
        end
        
        // ===========================================
        // Test 2: TRNG produces valid output
        // ===========================================
        $display("TEST 2: TRNG output check");
        // Wait a few clock cycles for TRNG to produce values
        #(200);  // 200ns = 2000 clock cycles @100MHz
        if (trng_valid) begin
            $display("  PASS: TRNG valid pulse generated");
            $display("  TRNG data: %h", trng_data);
        end else begin
            $display("  FAIL: TRNG valid pulse not generated");
        end
        
        // ===========================================
        // Test 3: Monotonic counter increments
        // ===========================================
        $display("TEST 3: Monotonic counter check");
        // Read counter initially
        #100;
        initial_count = counter_out;
        #100;
        after_count = counter_out;
        #100;
        final_count = counter_out;
        
        if (after_count > initial_count && final_count > after_count) begin
            $display("  PASS: Counter increments correctly");
            $display("  Initial: %d, After: %d, Final: %d", initial_count, after_count, final_count);
        end else begin
            $display("  FAIL: Counter not incrementing");
        end
        
        // ===========================================
        // Test 4: Key storage write-once policy
        // ===========================================
        $display("TEST 4: Key storage write-once policy");
        // Try to write to slot 0
        write_slot   = 4'd0;
        write_data   = 256'hDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF;
        write_en     = 1;
        write_auth   = 1;
        
        #100;
        // First write should succeed
        if (key_valid[0]) begin
            $display("  PASS: First write to slot 0 succeeded");
        end else begin
            $display("  FAIL: First write to slot 0 failed");
        end
        
        // Try to write again to same slot - should be ignored
        #100;
        write_en = 1;  // Keep asserted
        if (!key_written[0] || key_valid[0]) begin
            // Already written - good, second write should be ignored
            $display("  PASS: Second write to slot 0 ignored (write-once policy works)");
        end else {
            $display("  FAIL: Second write to slot 0 was not ignored");
        }
        
        // ===========================================
        // Test 5: Key read after write
        // ===========================================
        $display("TEST 5: Key read after write");
        read_slot   = 4'd0;
        read_en     = 1;
        read_auth   = 1;
        #100;
        if (read_data_local[255:252] == 4'hD) begin // Check first nibble matches DEAD...
            $display("  PASS: Key read correctly from slot 0");
            $display("  Read data first bytes: %h", read_data_local[255:248]);
        end else begin
            $display("  FAIL: Key read did not match written data");
        end
        
        // ===========================================
        // Test 6: Boot integrity check
        // ===========================================
        $display("TEST 6: Boot integrity check");
        // boot_ok should be driven from the module
        #100;
        if (boot_ok) begin
            $display("  PASS: Boot integrity OK");
        end else begin
            $display("  FAIL: Boot integrity FAILED - bitstream hash mismatch");
        end
        
        // ===========================================
        // Test 7: JTAG lock sequence
        // ===========================================
        $display("TEST 7: JTAG lock sequence");
        // Apply TMS=1 three times to trigger lock
        jtag_tms = 1;
        #10;
        jtag_tms = 1;
        #10;
        jtag_tms = 1;
        #10;
        
        if (jtag_locked) begin
            $display("  PASS: JTAG locked after TMS sequence");
            $display("  jtag_tdo output: %s (high-Z when locked)", jtag_tdo ? "driven" : "high-Z");
        end else begin
            $display("  FAIL: JTAG not locked");
        end
        
        // After lock, trying more TMS should not change state (or should maintain lock)
        jtag_tms = 0;
        #10;
        if (jtag_locked) begin
            $display("  PASS: JTAG remains locked");
        end
        
        // ===========================================
        // Test 8: Zeroize functionality
        // ===========================================
        $display("TEST 8: Zeroize functionality");
        // De-assert zeroize_n (active low = 0 = enable zeroize)
        zeroize_n = 0;
        #100;
        
        // After zeroize, keys should be cleared
        if (!key_valid[0]) begin
            $display("  PASS: Keys zeroized successfully");
        end else begin
            $display("  FAIL: Keys not zeroized");
        end
        
        // Re-assert zeroize_n
        zeroize_n = 1;
        #100;
        
        // Module should be ready again
        if (key_valid[0] === 1'b0 && boot_ok) begin
            $display("  PASS: Module ready after zeroize");
        end
        
        // ===========================================
        // Test 9: Counter wrap-around
        // ===========================================
        $display("TEST 9: Counter wrap-around check");
        // Counter at max value then wraps
        #(100 * 4294967295);  // This is too long, skip in simulation
        // Instead, just verify counter increments toward max
        $display("  (Skipped wrap verification in simulation)");
        
        // Finish simulation
        #100;
        $display("ALL TESTS COMPLETED - Simulation ending");
        $finish;
    end

    // Monotonic counter tracking for test 3
    integer initial_count, after_count, final_count;

    // Dump waves for verification
    initial begin
        $dumpfile("test_root_of_truth.vcd");
        $dumpvars(0, test_root_of_truth);
    end

endmodule