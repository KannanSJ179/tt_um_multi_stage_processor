// =============================================================================
// TinyTapeout Final Submission: tt_um_multi_stage_processor
// =============================================================================
`default_nettype none

// -----------------------------------------------------------------------------
// 16‑bit free‑running counter 
// -----------------------------------------------------------------------------
module counter_16b (
    input  wire clk, rst_n, ena,
    output reg [15:0] count
);
    always @(posedge clk) begin
        if (!rst_n)
            count <= 16'h0000;
        else if (ena)
            count <= count + 1;
    end
endmodule

// -----------------------------------------------------------------------------
// 16‑bit LFSR 
// -----------------------------------------------------------------------------
module lfsr_16b (
    input  wire clk, rst_n, ena,
    output reg [15:0] lfsr_out
);
    always @(posedge clk) begin
        if (!rst_n)
            lfsr_out <= 16'hACE1;   // non‑zero seed
        else if (ena)
            lfsr_out <= {lfsr_out[14:0],
                         lfsr_out[15] ^ lfsr_out[13] ^ lfsr_out[12] ^ lfsr_out[10]};
    end
endmodule

// -----------------------------------------------------------------------------
// 16‑bit shift register 
// -----------------------------------------------------------------------------
module shift_reg_16b (
    input  wire clk, rst_n, ena,
    input  wire din,
    output reg [15:0] dout
);
    always @(posedge clk) begin
        if (!rst_n)
            dout <= 16'h0000;
        else if (ena)
            dout <= {dout[14:0], din};
    end
endmodule

// -----------------------------------------------------------------------------
// 8‑bit analog sampler 
// -----------------------------------------------------------------------------
module analog_sampler_8b (
    input  wire clk, rst_n, ena,
    input  wire analog_bit,          // sampled digital level from analog block
    output reg [7:0] sample
);
    always @(posedge clk) begin
        if (!rst_n)
            sample <= 8'h00;
        else if (ena)
            sample <= {sample[6:0], analog_bit};
    end
endmodule

// -----------------------------------------------------------------------------
// Digital Core 
//   - dynamic config from uio_in[3:0]
//   - analog injected into deep combinational stage
//   - case‑based safe shift
//   - 8‑bit debug output (upper nibble driven externally)
//   - 3‑bit FSM + 8 modes jointly influence output
// -----------------------------------------------------------------------------
module core_digital (
    input  wire       clk, rst_n, ena,
    input  wire       test_mode,
    input  wire       hold,
    input  wire [2:0] mode_sel,      // source selection
    input  wire [3:0] config,        // dynamic operand (from uio_in[3:0])
    input  wire [2:0] debug_sel,     // debug multiplexer control
    input  wire       analog_in,     // digital snapshot of analog_out
    output wire [7:0] uo_out,
    output wire [7:0] debug_out
);

    // -------- hardware instances --------
    wire [15:0] cnt, lfsr_val, shift_val;
    wire [7:0]  analog_sample;

    counter_16b counter_inst (
        .clk(clk), .rst_n(rst_n), .ena(ena), .count(cnt)
    );
    lfsr_16b lfsr_inst (
        .clk(clk), .rst_n(rst_n), .ena(ena), .lfsr_out(lfsr_val)
    );
    shift_reg_16b shift_inst (
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .din(lfsr_val[0]), .dout(shift_val)
    );
    analog_sampler_8b analog_sampler (
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .analog_bit(analog_in), .sample(analog_sample)
    );

    // -------- 3‑bit FSM (0‑7, cycles unless hold) --------
    reg [2:0] state;
    always @(posedge clk) begin
        if (!rst_n)
            state <= 3'd0;
        else if (ena && !hold)
            state <= state + 1;
    end

    // -------- combinational pipeline (5 stages) --------
    reg [7:0] src_data;               // stage 1
    reg [7:0] alu_out;                // stage 2
    reg [7:0] shifted;                // stage 3 (safe shift)
    reg [7:0] s4;                     // stage 4: deep analog injection
    reg [7:0] debug_mux;              // debug multiplexer

    always @* begin
        // === Stage 1 : source selection (mode_sel controls data) ===
        case (mode_sel)
            3'd0: src_data = cnt[7:0];
            3'd1: src_data = lfsr_val[7:0];
            3'd2: src_data = shift_val[7:0];
            3'd3: src_data = analog_sample;          // analog feedback path
            3'd4: src_data = cnt[7:0] ^ lfsr_val[7:0];
            3'd5: src_data = cnt[7:0] + shift_val[7:0];
            3'd6: src_data = lfsr_val[7:0] & shift_val[7:0];
            3'd7: src_data = analog_sample ^ shift_val[7:0];
        endcase

        // === Stage 2 : ALU operation (FSM state selects op) ===
        case (state)
            3'd0: alu_out = src_data + {4'b0, config};        // add config
            3'd1: alu_out = src_data - {4'b0, config};        // subtract config
            3'd2: alu_out = src_data ^ {2{config}};           // XOR with replicated config
            3'd3: alu_out = src_data & {2{config}};           // AND
            3'd4: alu_out = src_data | 8'h5A;                 // OR constant (dense logic)
            3'd5: alu_out = src_data + cnt[15:8];             // add high counter byte
            3'd6: alu_out = src_data - lfsr_val[15:8];        // subtract high LFSR byte
            3'd7: alu_out = src_data;                         // pass‑through
        endcase

        // === Stage 3 : safe fixed‑width shift (config[2:0] controls shift amount) ===
        //    This replaces a variable shift operator to avoid timing degradation.
        case (config[2:0])
            3'd0: shifted = alu_out;
            3'd1: shifted = {alu_out[6:0], 1'b0};
            3'd2: shifted = {alu_out[5:0], 2'b00};
            3'd3: shifted = {alu_out[4:0], 3'b000};
            3'd4: shifted = {alu_out[3:0], 4'b0000};
            3'd5: shifted = {alu_out[2:0], 5'b00000};
            3'd6: shifted = {alu_out[1:0], 6'b000000};
            3'd7: shifted = {alu_out[0],   7'b0000000};
        endcase

        // === Stage 4 : deep analog injection (XOR with sampled analog) ===
        s4 = shifted ^ analog_sample;    // analog strongly influences final output

        // === Test mode override (deterministic) ===
        if (test_mode)
            s4 = cnt[7:0];   // always outputs low counter byte

        // === Debug output multiplexer (full 8‑bit selection) ===
        case (debug_sel)
            3'd0: debug_mux = cnt[7:0];
            3'd1: debug_mux = cnt[15:8];
            3'd2: debug_mux = lfsr_val[7:0];
            3'd3: debug_mux = lfsr_val[15:8];
            3'd4: debug_mux = shift_val[7:0];
            3'd5: debug_mux = analog_sample;                     // analog visibility
            3'd6: debug_mux = src_data;                          // ** pre‑ALU source (validation) **
            3'd7: debug_mux = {1'b0, state, mode_sel};            // FSM + mode (padded to 8 bits)
        endcase
    end

    // ---------- Registered outputs (timing safe, no glitches) ----------
    reg [7:0] uo_reg;
    reg [7:0] debug_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            uo_reg   <= 8'h00;
            debug_reg <= 8'h00;
        end else if (ena) begin
            uo_reg   <= s4;           // final processed value
            debug_reg <= debug_mux;
        end
    end

    assign uo_out    = uo_reg;
    assign debug_out = debug_reg;

endmodule

// -----------------------------------------------------------------------------
// Analog stub – blackbox for synthesis, pass‑through for simulation
// -----------------------------------------------------------------------------
module yen_top (
    inout VDD, VSS,
    input  analog_in,
    output analog_out
);
    // SYNTHESIS‑SAFE BLACKBOX:
    // During synthesis this module is empty → treated as an external macro.
    // The real layout replaces it with the analogue cell.
`ifndef SYNTHESIS
    // Simulation only: simple pass‑through for standalone functional tests.
    assign analog_out = analog_in;
`endif
endmodule

// -----------------------------------------------------------------------------
// TinyTapeout Top Wrapper
//   uio_oe = 4’b1111_0000 – upper nibble outputs debug data,
//   lower nibble inputs dynamic config from uio_in[3:0]
// -----------------------------------------------------------------------------
module tt_um_multi_stage_processor (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena, clk, rst_n,
    inout  wire [7:0] ua,
    inout  wire       VDD, VSS
);

    // ---- Analog blackbox (ua[1] = input, ua[0] = output) ----
    yen_top analog_core (
        .VDD(VDD), .VSS(VSS),
        .analog_in (ua[1]),
        .analog_out(ua[0])
    );

    // ---- Digital core with analog feedback ----
    wire [7:0] uo_out_int;
    wire [7:0] debug_int;

    core_digital core (
        .clk       (clk),
        .rst_n     (rst_n),
        .ena       (ena),
        .test_mode (ui_in[7]),
        .hold      (ui_in[3]),
        .mode_sel  (ui_in[2:0]),
        .config    (uio_in[3:0]),     // dynamic config from dedicated input nibble
        .debug_sel (ui_in[6:4]),
        .analog_in (ua[0]),           // digital level of analog output
        .uo_out    (uo_out_int),
        .debug_out (debug_int)
    );

    assign uo_out = uo_out_int;

    // uio_oe: upper nibble outputs debug data, lower nibble inputs (config)
    assign uio_oe  = 8'b1111_0000;
    assign uio_out = debug_int;       // full 8‑bit debug word (lower nibble not driven externally)

    // Tie off truly unused pins to suppress synthesis warnings
    wire _unused = &{uio_in[7:4], ua[7:2]};

endmodule

`default_nettype wire
