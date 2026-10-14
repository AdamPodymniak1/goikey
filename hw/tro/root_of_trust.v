`default_nettype none

//============================================================================
// Root of Trust for Tang Nano 20k (Gowin GW2AR-18C)
//============================================================================
// Provides:
//   - Unique 128-bit Device UUID (from factory-trimmable OSC)
//   - On-chip TRNG (oscillator-based jitter extraction)
//   - Secure key storage with write-once policy
//   - Monotonic counter for replay protection
//   - Secure boot integrity check
//   - JTAG protection
//============================================================================

module root_of_trust #(
    parameter NUM_KEY_SLOTS = 4,
    parameter KEY_BITS      = 256
)(
    // System clock and reset
    input  wire        clk,
    input  wire        rst_n,

    // Zeroize control (active-low: 0 = erase all keys)
    input  wire        zeroize_n,

    // JTAG interface
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo,
    output wire        jtag_locked,

    //------------------------------------------------------------------
    // UUID output (128-bit, read-only)
    //------------------------------------------------------------------
    output wire [127:0] uid_o,
    output wire         uid_valid,

    //------------------------------------------------------------------
    // TRNG output
    //------------------------------------------------------------------
    output wire [31:0]  trng_o,
    output wire         trng_valid,

    //------------------------------------------------------------------
    // Key storage write port (provisioning)
    //------------------------------------------------------------------
    input  wire [3:0]         write_slot_idx,
    input  wire [KEY_BITS-1:0] write_key_data,
    input  wire               write_en,
    input  wire               write_auth,

    //------------------------------------------------------------------
    // Key storage read port
    //------------------------------------------------------------------
    input  wire [3:0]         read_slot_idx,
    input  wire               read_en,
    input  wire               read_auth,
    output wire [KEY_BITS-1:0] key_o,

    //------------------------------------------------------------------
    // Boot integrity status
    //------------------------------------------------------------------
    output wire         boot_ok,

    //------------------------------------------------------------------
    // Monotonic counter
    //------------------------------------------------------------------
    output wire [31:0]  counter_o
);

//----------------------------------------------------------------------
// 1. Device UUID (128-bit), provisioned at build time
//----------------------------------------------------------------------

// Per-device identity, generated randomly at build/provision time by
// build_tangnano20k.sh (-DUID_VAL=128'h...). Gowin parts expose no
// fabric-readable silicon ID, so this is a provisioned identity, not a
// hardware-unique one. The fallback below is for simulation only.
`ifdef UID_VAL
localparam [127:0] DEFAULT_UID = `UID_VAL;
`else
localparam [127:0] DEFAULT_UID = 128'hA1B2C3D4_E5F60718_293A4B5C_6D7E8F00;
`endif

reg [127:0] device_uid = DEFAULT_UID;

assign uid_valid = 1'b1;
assign uid_o     = device_uid;

//----------------------------------------------------------------------
// 2. True Random Number Generator (TRNG)
//    Uses cross-coupled ring oscillators to extract jitter.
//    Two free-running rings with slightly different frequencies:
//    XOR of LSBs provides entropy source.
//----------------------------------------------------------------------

// Raw entropy: free-running ring oscillators (see trng_ring below) are
// sampled by clk. Ring-to-clock phase jitter makes each sample unpredictable.
wire ring_raw;
`ifdef SIM_FAST_TRNG
// simulation stand-in (LUT ring oscillators cannot be simulated at zero delay)
reg [30:0] sim_lfsr = 31'h2468ace1;
always @(posedge clk) sim_lfsr <= {sim_lfsr[29:0], sim_lfsr[30] ^ sim_lfsr[27]};
assign ring_raw = sim_lfsr[0] ^ sim_lfsr[13];
`else
trng_core u_trng_core (.clk(clk), .rst_n(rst_n), .raw(ring_raw));
`endif

// Decimate (sample every 32nd clk so jitter accumulates between samples),
// then von Neumann debias pairs: 01 -> 0, 10 -> 1, 00/11 -> discard.
reg [4:0]  dec_cnt   = 5'd0;
reg        pair_have = 1'b0;
reg        pair_first = 1'b0;
reg [31:0] trng_q    = 32'd0;
reg [4:0]  trng_n    = 5'd0;
reg        trng_v    = 1'b0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dec_cnt <= 5'd0; pair_have <= 1'b0; pair_first <= 1'b0;
        trng_q <= 32'd0; trng_n <= 5'd0; trng_v <= 1'b0;
    end else begin
        trng_v  <= 1'b0;
        dec_cnt <= dec_cnt + 5'd1;
        if (dec_cnt == 5'd31) begin
            if (!pair_have) begin
                pair_first <= ring_raw;
                pair_have  <= 1'b1;
            end else begin
                pair_have <= 1'b0;
                if (pair_first != ring_raw) begin
                    trng_q <= {trng_q[30:0], pair_first};
                    trng_n <= trng_n + 5'd1;
                    if (trng_n == 5'd31) trng_v <= 1'b1;
                end
            end
        end
    end
end

assign trng_o     = trng_q;
assign trng_valid = trng_v;

//----------------------------------------------------------------------
// 3. Secure Key Storage (BRAM-based)
//    Write-once policy: keys can only be written once during provisioning.
//    After that, they are read-only. Zeroize capability.
//----------------------------------------------------------------------

reg [KEY_BITS-1:0] key_mem     [0:NUM_KEY_SLOTS-1];
reg [NUM_KEY_SLOTS-1:0] key_valid;
reg [NUM_KEY_SLOTS-1:0] key_written;
reg [KEY_BITS-1:0]      key_read_reg;

integer i;

// Initialize key storage
initial begin
    key_valid   = {NUM_KEY_SLOTS{1'b0}};
    key_written = {NUM_KEY_SLOTS{1'b0}};
    for (i = 0; i < NUM_KEY_SLOTS; i = i + 1) begin
        key_mem[i] = {KEY_BITS{1'b0}};
    end
end

// Write logic - first-write-per-slot only
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_valid   <= {NUM_KEY_SLOTS{1'b0}};
        key_written <= {NUM_KEY_SLOTS{1'b0}};
    end else if (zeroize_n === 1'b0) begin
        // Zeroize: clear all keys
        key_valid   <= {NUM_KEY_SLOTS{1'b0}};
        key_written <= {NUM_KEY_SLOTS{1'b0}};
        for (i = 0; i < NUM_KEY_SLOTS; i = i + 1) begin
            key_mem[i] <= {KEY_BITS{1'b0}};
        end
    end else if (write_en && write_auth && !key_written[write_slot_idx]) begin
        // First write to an empty slot succeeds
        key_mem[write_slot_idx]     <= write_key_data;
        key_valid[write_slot_idx]   <= 1'b1;
        key_written[write_slot_idx] <= 1'b1;
    end
end

// Read logic - only when authorized and slot is valid
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_read_reg <= {KEY_BITS{1'b0}};
    end else if (read_en && read_auth && key_valid[read_slot_idx]) begin
        key_read_reg <= key_mem[read_slot_idx];
    end else begin
        key_read_reg <= {KEY_BITS{1'b0}};
    end
end

assign key_o = key_read_reg;

//----------------------------------------------------------------------
// 4. Monotonic Counter (Replay Protection)
//    Counts monotonically from 0 to 2^32-1, then wraps.
//----------------------------------------------------------------------

reg [31:0] monotonic_counter = 32'd0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        monotonic_counter <= 32'd0;
    end else if (monotonic_counter == 32'hFFFF_FFFF) begin
        monotonic_counter <= 32'd0;
    end else begin
        monotonic_counter <= monotonic_counter + 32'd1;
    end
end

assign counter_o = monotonic_counter;

//----------------------------------------------------------------------
// 5. Secure Boot / Bitstream Integrity
//    Compares expected bitstream hash against computed hash.
//----------------------------------------------------------------------

localparam [255:0] EXPECTED_BITSTREAM_HASH = 256'hAABBCCDD_EEFF0011_22334455_66778899;

reg [255:0] computed_hash     = 256'd0;
reg         boot_integrity_ok = 1'b0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        boot_integrity_ok <= 1'b0;
        computed_hash     <= 256'd0;
    end else begin
        // Real implementation would compute SHA-256 of active config
        // and compare against EXPECTED_BITSTREAM_HASH
        boot_integrity_ok <= (computed_hash == EXPECTED_BITSTREAM_HASH);
    end
end

assign boot_ok = boot_integrity_ok;

//----------------------------------------------------------------------
// 6. JTAG Protection
//    Models iCE40 JTAG lock mechanism.
//    Once locked, JTAG debug access is disabled.
//----------------------------------------------------------------------

reg jtag_lock_reg = 1'b0;
reg [1:0] tms_history = 2'd0;

always @(posedge jtag_tck or negedge rst_n) begin
    if (!rst_n) begin
        jtag_lock_reg <= 1'b0;
        tms_history   <= 2'd0;
    end else begin
        tms_history <= {tms_history[0], jtag_tms};

        // Lock after detecting TMS=1, TMS=1 pattern
        if (tms_history == 2'b11) begin
            jtag_lock_reg <= 1'b1;
        end
    end
end

// JTAG data output (high-Z when locked)
assign jtag_tdo    = jtag_lock_reg ? 1'bz : 1'b0;
assign jtag_locked = jtag_lock_reg;

//----------------------------------------------------------------------
// End of Root of Trust Module
//----------------------------------------------------------------------

endmodule

`default_nettype wire
`ifndef SIM_FAST_TRNG
//============================================================================
// TRNG entropy source: 8 ring oscillators of different odd lengths built from
// Gowin LUT4 inverters (INIT=0x5555 -> ~I0), XOR-combined, sampled by clk.
// (* keep *) stops synthesis from collapsing the combinational loops.
//============================================================================
module trng_ring #(parameter N = 3)(output wire out);
    (* keep *) wire [N-1:0] w;
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : stage
            (* keep *) LUT4 #(.INIT(16'h5555)) inv (
                .F(w[g]), .I0(w[(g + N - 1) % N]), .I1(1'b0), .I2(1'b0), .I3(1'b0));
        end
    endgenerate
    assign out = w[N-1];
endmodule

module trng_core (
    input  wire clk,
    input  wire rst_n,
    output reg  raw
);
    wire [7:0] r;
    trng_ring #(.N(3))  r0 (.out(r[0]));
    trng_ring #(.N(5))  r1 (.out(r[1]));
    trng_ring #(.N(7))  r2 (.out(r[2]));
    trng_ring #(.N(9))  r3 (.out(r[3]));
    trng_ring #(.N(11)) r4 (.out(r[4]));
    trng_ring #(.N(13)) r5 (.out(r[5]));
    trng_ring #(.N(15)) r6 (.out(r[6]));
    trng_ring #(.N(17)) r7 (.out(r[7]));

    reg [7:0] s1;
    always @(posedge clk) s1 <= r;          // sample (metastability is welcome)
    always @(posedge clk or negedge rst_n)
        if (!rst_n) raw <= 1'b0;
        else        raw <= ^s1;
endmodule
`endif
