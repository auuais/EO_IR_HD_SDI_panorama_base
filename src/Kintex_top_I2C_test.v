module Kintex_top_I2C_test #(
    parameter [6:0] SLAVE_ADDR = 7'h36,

    // ===== Internal POR reset params =====
    parameter integer SCLK_HZ = 100_000_000, // 100 MHz default
    parameter integer POR_MS  = 100,         // 100 ms reset

    parameter integer REG_COUNT = 128
)(
    input  wire FPGA_RESET, // unused
    input  wire SCLK_IN,
    input  wire SCL,
    inout  wire SDA,
	output wire [3:0] cam_select,
    output wire [7:0] mode_out
);

    //===========================================================
    // SCLK BUFG
    //===========================================================
    wire SCLK;
    BUFG u_bufg_sclk (
        .I (SCLK_IN),
        .O (SCLK)
    );

    //===========================================================
    // Internal POR reset (POR_MS)
    //===========================================================
    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

    localparam integer POR_CYCLES = (SCLK_HZ * POR_MS) / 1000;
    localparam integer POR_W      = (POR_CYCLES <= 1) ? 1 : clog2(POR_CYCLES + 1);

    reg  [POR_W-1:0] por_cnt /* synthesis preserve */;
    wire             nRESET_INT;

    assign nRESET_INT = (POR_CYCLES <= 1) ? 1'b1
                                          : (por_cnt >= POR_CYCLES[POR_W-1:0]);

    always @(posedge SCLK) begin
        if (!nRESET_INT)
            por_cnt <= por_cnt + 1'b1;
    end

    //===========================================================
    // IBUF for SCL
    //===========================================================
    wire scl_ibuf;
    IBUF u_ibuf_scl (
        .I(SCL),
        .O(scl_ibuf)
    );

    //===========================================================
    // IOBUF for SDA (Open-Drain: low only)
    //===========================================================
    reg  sda_oe;     // 1 => drive LOW, 0 => release(Z)
    wire sda_in;

    wire sda_i;
    wire sda_o;
    wire sda_t;

    assign sda_o = 1'b0;
    assign sda_t = ~sda_oe;

    IOBUF u_iobuf_sda (
        .I (sda_o),
        .O (sda_i),
        .T (sda_t),
        .IO(SDA)
    );

    assign sda_in = sda_i;

    //===========================================================
    // Sync SCL and SDA to SCLK
    //===========================================================
    reg scl_meta, scl_sync, scl_sync_d;
    reg sda_meta, sda_sync, sda_sync_d;

    wire scl_rise =  scl_sync & ~scl_sync_d;
    wire scl_fall = ~scl_sync &  scl_sync_d;

    wire sda_rise =  sda_sync & ~sda_sync_d;
    wire sda_fall = ~sda_sync &  sda_sync_d;

    // ---- START/STOP qualification to avoid false detection ----
    wire scl_high_qual = scl_meta & scl_sync; // stable HIGH only

    wire start_cond = sda_fall & scl_high_qual; // START: SDA fall while SCL=1
    wire stop_cond  = sda_rise & scl_high_qual; // STOP : SDA rise while SCL=1

    //===========================================================
    // Register file (128 x 8-bit)
    // Force flip-flop/register implementation instead of inferred RAM.
    // The old known-good design used a small discrete register bank; once
    // expanded to 128 bytes we must prevent BRAM/LUTRAM inference so random
    // 8-bit address accesses continue to behave as a simple byte register file.
    //===========================================================
    (* ram_style = "registers" *) reg [7:0] regfile [0:REG_COUNT-1];
    reg [7:0] reg_index;

    wire [7:0] mode_reg = regfile[8'h00];
    assign mode_out = mode_reg;
    wire [31:0] eo_cyl_h_fov_q16 = {regfile[8'h23], regfile[8'h22], regfile[8'h21], regfile[8'h20]};
    wire [31:0] eo_cyl_v_fov_q16 = {regfile[8'h27], regfile[8'h26], regfile[8'h25], regfile[8'h24]};
    wire [31:0] eo_crop_h_q16    = {regfile[8'h2B], regfile[8'h2A], regfile[8'h29], regfile[8'h28]};
    wire [31:0] eo_crop_w_q16    = {regfile[8'h2F], regfile[8'h2E], regfile[8'h2D], regfile[8'h2C]};
    wire [31:0] eo_pitch_tr_q16  = {regfile[8'h33], regfile[8'h32], regfile[8'h31], regfile[8'h30]};
    wire [31:0] eo_yaw_tr_q16    = {regfile[8'h37], regfile[8'h36], regfile[8'h35], regfile[8'h34]};
    wire [31:0] eo_overlap_i32   = {regfile[8'h3B], regfile[8'h3A], regfile[8'h39], regfile[8'h38]};
    wire [31:0] eo_feather_q16   = {regfile[8'h3F], regfile[8'h3E], regfile[8'h3D], regfile[8'h3C]};

    wire [31:0] ir_cyl_h_fov_q16 = {regfile[8'h53], regfile[8'h52], regfile[8'h51], regfile[8'h50]};
    wire [31:0] ir_cyl_v_fov_q16 = {regfile[8'h57], regfile[8'h56], regfile[8'h55], regfile[8'h54]};
    wire [31:0] ir_crop_h_q16    = {regfile[8'h5B], regfile[8'h5A], regfile[8'h59], regfile[8'h58]};
    wire [31:0] ir_crop_w_q16    = {regfile[8'h5F], regfile[8'h5E], regfile[8'h5D], regfile[8'h5C]};
    wire [31:0] ir_pitch_tr_q16  = {regfile[8'h63], regfile[8'h62], regfile[8'h61], regfile[8'h60]};
    wire [31:0] ir_yaw_tr_q16    = {regfile[8'h67], regfile[8'h66], regfile[8'h65], regfile[8'h64]};
    wire [31:0] ir_overlap_i32   = {regfile[8'h6B], regfile[8'h6A], regfile[8'h69], regfile[8'h68]};
    wire [31:0] ir_feather_q16   = {regfile[8'h6F], regfile[8'h6E], regfile[8'h6D], regfile[8'h6C]};
    assign cam_select =
        (mode_reg <= 8'd5)                      ? mode_reg[3:0] :
        ((mode_reg >= 8'h0D) && (mode_reg <= 8'h12)) ? (mode_reg - 8'h0D) :
                                                  4'd0;

    //===========================================================
    // FSM / Shifters
    //===========================================================
    localparam [3:0]
        ST_IDLE      = 4'd0,
        ST_ADDR_RX   = 4'd1,
        ST_ADDR_ACK  = 4'd2,
        ST_REG_RX    = 4'd3,
        ST_REG_ACK   = 4'd4,
        ST_WRITE_RX  = 4'd5,
        ST_WRITE_ACK = 4'd6,
        ST_READ_TX   = 4'd7,
        ST_READ_ACK  = 4'd8;

    reg [3:0] state;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;
    reg       rw_flag; // 0=write, 1=read
    reg       addr_match;
    integer   idx;

    //===========================================================
    // Debug signals (ILA)
    //===========================================================
     /*
     wire dbg_sclk    = SCLK;
     wire dbg_rstn    = nRESET_INT;
     wire dbg_scl     = scl_ibuf;
     wire dbg_sda     = sda_in;
     wire dbg_sclsync = scl_sync;
     wire dbg_sdasyn  = sda_sync;
     wire dbg_start   = start_cond;
     wire dbg_stop    = stop_cond;
     wire dbg_sclr    = scl_rise;
     wire dbg_sclf    = scl_fall;
     wire dbg_sdaoe   = sda_oe;

     reg  [3:0] dbg_state;
     reg  [2:0] dbg_bit_cnt;
     reg  [7:0] dbg_shift_reg;
     reg  [3:0] dbg_reg_index;
     reg        dbg_addr_match;
     reg        dbg_rw;

    // Write debug mirrors (ILA friendly)
     reg [3:0] dbg_last_wr_idx;
     reg [7:0] dbg_last_wr_data;
     reg       dbg_last_wr_pulse;

    always @(posedge SCLK) begin
        dbg_state      <= state;
        dbg_bit_cnt    <= bit_cnt;
        dbg_shift_reg  <= shift_reg;
        dbg_reg_index  <= reg_index;
        dbg_addr_match <= addr_match;
        dbg_rw         <= rw_flag;
    end
    */

    //===========================================================
    // Input synchronizers
    //===========================================================
    always @(posedge SCLK or negedge nRESET_INT) begin
        if (!nRESET_INT) begin
            scl_meta   <= 1'b0;
            scl_sync   <= 1'b0;
            scl_sync_d <= 1'b0;

            sda_meta   <= 1'b1;
            sda_sync   <= 1'b1;
            sda_sync_d <= 1'b1;
        end else begin
            scl_meta   <= scl_ibuf;
            scl_sync   <= scl_meta;
            scl_sync_d <= scl_sync;

            sda_meta   <= sda_in;
            sda_sync   <= sda_meta;
            sda_sync_d <= sda_sync;
        end
    end

    //===========================================================
    // Main FSM (RX on SCL rising, drive SDA only while SCL low)
    //===========================================================
    always @(posedge SCLK or negedge nRESET_INT) begin
        if (!nRESET_INT) begin
            state      <= ST_IDLE;
            bit_cnt    <= 3'd0;
            shift_reg  <= 8'd0;
            rw_flag    <= 1'b0;
            addr_match <= 1'b0;
            reg_index  <= 8'd0;

            for (idx = 0; idx < REG_COUNT; idx = idx + 1)
                regfile[idx] <= 8'h00;

            sda_oe <= 1'b0;

            //dbg_last_wr_idx   <= 4'd0;
            //dbg_last_wr_data  <= 8'd0;
            //dbg_last_wr_pulse <= 1'b0;

        end else begin
            // default pulse low (one-shot)
            //dbg_last_wr_pulse <= 1'b0;

            // STOP: release bus, go idle
            if (stop_cond) begin
                state      <= ST_IDLE;
                sda_oe     <= 1'b0;
                addr_match <= 1'b0;
            end

            // START or Re-START: go receive address
            if (start_cond) begin
                state      <= ST_ADDR_RX;
                bit_cnt    <= 3'd7;
                shift_reg  <= 8'd0;
                sda_oe     <= 1'b0;
                addr_match <= 1'b0;
            end

            // DRIVE SDA only while SCL LOW (ACK / READ data)
            if (!scl_sync) begin
                case (state)
                    ST_ADDR_ACK:  sda_oe <= addr_match ? 1'b1 : 1'b0;
                    ST_REG_ACK:   sda_oe <= addr_match ? 1'b1 : 1'b0;
                    ST_WRITE_ACK: sda_oe <= addr_match ? 1'b1 : 1'b0;

                    ST_READ_TX: begin
                        if (!addr_match)
                            sda_oe <= 1'b0;
                        else
                            // open-drain: 0 drives low, 1 releases
                            sda_oe <= (regfile[reg_index][bit_cnt] == 1'b0) ? 1'b1 : 1'b0;
                    end

                    ST_READ_ACK:  sda_oe <= 1'b0; // master drives ACK/NACK

                    default:      sda_oe <= 1'b0; // RX states: release
                endcase
            end

            // SAMPLE on SCL rising edge
            if (scl_rise) begin
                case (state)

                    ST_ADDR_RX: begin
                        shift_reg[bit_cnt] <= sda_sync;
                        if (bit_cnt == 0) begin
                            // address bits already in shift_reg[7:1]
                            rw_flag    <= sda_sync;                 // R/W bit
                            addr_match <= (shift_reg[7:1] == SLAVE_ADDR); // Verilog-safe
                            state      <= ST_ADDR_ACK;
                            bit_cnt    <= 3'd7;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    ST_ADDR_ACK: begin
                        if (!addr_match) begin
                            state <= ST_IDLE;
                        end else if (rw_flag == 1'b0) begin
                            state     <= ST_REG_RX;
                            bit_cnt   <= 3'd7;
                            shift_reg <= 8'd0;
                        end else begin
                            state   <= ST_READ_TX;
                            bit_cnt <= 3'd7;
                        end
                    end

                    ST_REG_RX: begin
                        shift_reg[bit_cnt] <= sda_sync;
                        if (bit_cnt == 0) begin
                            reg_index <= {shift_reg[7:1], sda_sync};
                            state     <= ST_REG_ACK;
                            bit_cnt   <= 3'd7;
                            shift_reg <= 8'd0;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    ST_REG_ACK: begin
                        state     <= ST_WRITE_RX;
                        bit_cnt   <= 3'd7;
                        shift_reg <= 8'd0;
                    end

                    ST_WRITE_RX: begin
                        shift_reg[bit_cnt] <= sda_sync;
                        if (bit_cnt == 0) begin
                            // WRITE the received data byte
                            regfile[reg_index] <= {shift_reg[7:1], sda_sync};

                            // Debug mirrors (confirm actual write happened)
                            //dbg_last_wr_idx   <= reg_index;
                            //dbg_last_wr_data  <= {shift_reg[7:1], sda_sync};
                            //dbg_last_wr_pulse <= 1'b1;

                            reg_index <= reg_index + 1'b1;
                            state     <= ST_WRITE_ACK;
                            bit_cnt   <= 3'd7;
                            shift_reg <= 8'd0;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    ST_WRITE_ACK: begin
                        state     <= ST_WRITE_RX;
                        bit_cnt   <= 3'd7;
                        shift_reg <= 8'd0;
                    end

                    ST_READ_TX: begin
                        if (!addr_match) begin
                            state <= ST_IDLE;
                        end else if (bit_cnt == 0) begin
                            state <= ST_READ_ACK;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    ST_READ_ACK: begin
                        if (sda_sync == 1'b0) begin
                            reg_index <= reg_index + 1'b1;
                            state     <= ST_READ_TX;
                            bit_cnt   <= 3'd7;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end
 

endmodule
