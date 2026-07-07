// Verbatim import of EO1920x1080_Decimate3_FrameBuffer from the proven
// BRAM/URAM reference project (E:\Xylinx\EO_IR_HDSDI_BRAM-URAM_FRAMESIZE\
// src\EOStackModules.v).  Only this module is imported here -- the donor
// file's EO6Stack_To_HD1080p_Buffered renderer is not needed because the
// DDR copy engine in PanoramaBase_DdrBlackFrame.v replaces its BRAM-read
// scan-out path.
module EO1920x1080_Decimate3_FrameBuffer #(
    parameter integer SRC_W        = 640,
    parameter integer SRC_H        = 480,
    parameter integer FRAME_ADDR_W = 19,
    parameter integer READ_LATENCY = 2,
    parameter        CLOCKING_MODE_STR = "common_clock",
    parameter        MEMORY_PRIMITIVE_STR = "block",
    parameter integer FIFO_RELATED_CLOCKS = 0,
    parameter integer USE_ASYNC_FIFO = 1
)(
    input  wire                     rst_n,
    input  wire                     wr_clk,
    input  wire                     wr_hsync,
    input  wire                     wr_vsync,
    input  wire [19:0]              wr_pixel,
    input  wire                     rd_clk,
    input  wire                     rd_frame_start,
    input  wire                     rd_en,
    input  wire [FRAME_ADDR_W-1:0]  rd_addr,
    output wire [19:0]              rd_pixel,
    output reg                      frame_valid
);
    localparam integer FRAME_PIXELS = SRC_W * SRC_H;
    localparam integer PACKED_PIXEL_W = 16;
    localparam integer FRAME_BITS   = FRAME_PIXELS * PACKED_PIXEL_W;
    localparam integer FIFO_WIDTH   = 1 + FRAME_ADDR_W + PACKED_PIXEL_W;
    localparam integer CROP_X_START = 240;
    localparam integer CROP_X_WIDTH = (SRC_W * 9) / 4;
    localparam integer CROP_X_END   = CROP_X_START + CROP_X_WIDTH;

    reg [FRAME_ADDR_W-1:0] wr_addr;
    reg                    wr_hsync_d;
    reg                    wr_vsync_d;
    reg [11:0]             wr_x;
    reg [3:0]              wr_x_phase;
    reg [3:0]              wr_y_phase;
    wire                   wr_frame_active;
    wire                   wr_frame_start;
    wire                   wr_line_end;
    wire                   wr_fifo_full;
    wire                   wr_sample_now;
    wire                   wr_x_in_crop;
    wire                   wr_x_sample;
    wire                   wr_y_sample;
    wire [FIFO_WIDTH-1:0]  wr_fifo_din;
    wire                   mem_wr_en;
    wire [FRAME_ADDR_W-1:0] mem_wr_addr;
    wire [PACKED_PIXEL_W-1:0] mem_wr_pixel;
    wire                   frame_complete_rd;
    wire [PACKED_PIXEL_W-1:0] wr_pixel_packed;

    assign wr_pixel_packed = {wr_pixel[19:12], wr_pixel[9:2]};
    assign wr_frame_active = ~wr_vsync;
    assign wr_frame_start  = wr_vsync_d && ~wr_vsync;
    assign wr_line_end     = wr_hsync_d && ~wr_hsync && wr_frame_active;
    assign wr_x_in_crop   = (wr_x >= CROP_X_START) && (wr_x < CROP_X_END);
    // Select whole Y/C chroma pairs so the stacked output keeps Cb/Cr cadence.
    assign wr_x_sample    = wr_x_in_crop &&
                            ((wr_x_phase == 4'd0) || (wr_x_phase == 4'd2) ||
                             (wr_x_phase == 4'd4) || (wr_x_phase == 4'd6));
    assign wr_y_sample    = (wr_y_phase == 4'd0) || (wr_y_phase == 4'd2) ||
                            (wr_y_phase == 4'd4) || (wr_y_phase == 4'd6);
    assign wr_sample_now   = wr_frame_active && wr_hsync &&
                             wr_y_sample && wr_x_sample &&
                             (wr_addr < FRAME_PIXELS) && !wr_fifo_full;
    assign wr_fifo_din     = {(wr_addr == (FRAME_PIXELS - 1)), wr_addr, wr_pixel_packed};

    always @(posedge wr_clk) begin
        if (!rst_n) begin
            wr_addr           <= {FRAME_ADDR_W{1'b0}};
            wr_hsync_d        <= 1'b0;
            wr_vsync_d        <= 1'b0;
            wr_x              <= 12'd0;
            wr_x_phase        <= 4'd0;
            wr_y_phase        <= 4'd0;
        end else begin
            wr_hsync_d <= wr_hsync;
            wr_vsync_d <= wr_vsync;

            if (wr_frame_start) begin
                wr_addr     <= {FRAME_ADDR_W{1'b0}};
                wr_x        <= 12'd0;
                wr_x_phase  <= 4'd0;
                wr_y_phase <= 4'd0;
            end

            if (wr_frame_active && wr_hsync) begin
                if (wr_sample_now) begin
                    wr_addr <= wr_addr + {{(FRAME_ADDR_W-1){1'b0}}, 1'b1};
                end

                if (wr_x_in_crop && wr_x[0]) begin
                    if (wr_x_phase == 4'd8)
                        wr_x_phase <= 4'd0;
                    else
                        wr_x_phase <= wr_x_phase + 4'd1;
                end

                wr_x <= wr_x + 12'd1;
            end

            if (wr_line_end) begin
                wr_x       <= 12'd0;
                wr_x_phase <= 4'd0;
                if (wr_y_phase == 4'd8)
                    wr_y_phase <= 4'd0;
                else
                    wr_y_phase <= wr_y_phase + 4'd1;
            end
        end
    end

    wire [PACKED_PIXEL_W-1:0] rd_pixel_buf;
    assign rd_pixel = {rd_pixel_buf[15:8], 2'b00, rd_pixel_buf[7:0], 2'b00};

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            frame_valid <= 1'b0;
        end else begin
            if (frame_complete_rd)
                frame_valid <= 1'b1;
        end
    end

    generate
        if (USE_ASYNC_FIFO) begin : gen_async_wr
            wire [FIFO_WIDTH-1:0] rd_fifo_dout;
            wire                  rd_fifo_empty;
            wire                  rd_fifo_pop;
            wire                  rd_fifo_last;
            wire [FRAME_ADDR_W-1:0] rd_fifo_addr;
            wire [PACKED_PIXEL_W-1:0] rd_fifo_pixel;
            wire                  wr_fifo_full_i;

            assign rd_fifo_pop     = !rd_fifo_empty;
            assign rd_fifo_last    = rd_fifo_dout[FIFO_WIDTH-1];
            assign rd_fifo_addr    = rd_fifo_dout[FRAME_ADDR_W+PACKED_PIXEL_W-1:PACKED_PIXEL_W];
            assign rd_fifo_pixel   = rd_fifo_dout[PACKED_PIXEL_W-1:0];
            assign wr_fifo_full    = wr_fifo_full_i;

            // One retiming register between the CDC FIFO's popped output and
            // the framebuffer's write port. At panorama-project scale this
            // write bus broadcasts to a ~142-deep BRAM cascade (640x480x16b
            // is far too large for one block); the direct combinational
            // connection measured 4.2-4.5ns of pure routing delay to the
            // farthest cascade segments against a 3.332ns (300MHz) period.
            // Splitting the same physical distance across two clock edges
            // instead of one comfortably closes it. Purely a timing retime
            // (write still happens, just one cycle later; the FIFO has no
            // other consumer coupled to that cycle) -- the only deviation
            // from the otherwise-verbatim donor module.
            reg                       mem_wr_en_r;
            reg [FRAME_ADDR_W-1:0]    mem_wr_addr_r;
            reg [PACKED_PIXEL_W-1:0]  mem_wr_pixel_r;
            reg                       frame_complete_rd_r;
            always @(posedge rd_clk) begin
                if (!rst_n) begin
                    mem_wr_en_r         <= 1'b0;
                    mem_wr_addr_r       <= {FRAME_ADDR_W{1'b0}};
                    mem_wr_pixel_r      <= {PACKED_PIXEL_W{1'b0}};
                    frame_complete_rd_r <= 1'b0;
                end else begin
                    mem_wr_en_r         <= rd_fifo_pop;
                    mem_wr_addr_r       <= rd_fifo_addr;
                    mem_wr_pixel_r      <= rd_fifo_pixel;
                    frame_complete_rd_r <= rd_fifo_pop && rd_fifo_last;
                end
            end
            assign mem_wr_en         = mem_wr_en_r;
            assign mem_wr_addr       = mem_wr_addr_r;
            assign mem_wr_pixel      = mem_wr_pixel_r;
            assign frame_complete_rd = frame_complete_rd_r;

            xpm_fifo_async #(
                .CDC_SYNC_STAGES     (2),
                .DOUT_RESET_VALUE    ("0"),
                .ECC_MODE            ("no_ecc"),
                .FIFO_MEMORY_TYPE    ("auto"),
                .FIFO_READ_LATENCY   (0),
                .FIFO_WRITE_DEPTH    (1024),
                .FULL_RESET_VALUE    (0),
                .PROG_EMPTY_THRESH   (10),
                .PROG_FULL_THRESH    (900),
                .RD_DATA_COUNT_WIDTH (11),
                .READ_DATA_WIDTH     (FIFO_WIDTH),
                .READ_MODE           ("fwft"),
                .RELATED_CLOCKS      (FIFO_RELATED_CLOCKS),
                .SIM_ASSERT_CHK      (0),
                .USE_ADV_FEATURES    ("0000"),
                .WAKEUP_TIME         (0),
                .WRITE_DATA_WIDTH    (FIFO_WIDTH),
                .WR_DATA_COUNT_WIDTH (11)
            ) u_wr_cdc_fifo (
                .sleep         (1'b0),
                .rst           (~rst_n),
                .wr_clk        (wr_clk),
                .wr_en         (wr_sample_now),
                .din           (wr_fifo_din),
                .full          (wr_fifo_full_i),
                .overflow      (),
                .wr_rst_busy   (),
                .wr_ack        (),
                .wr_data_count (),
                .almost_full   (),
                .prog_full     (),
                .rd_clk        (rd_clk),
                .rd_en         (rd_fifo_pop),
                .dout          (rd_fifo_dout),
                .empty         (rd_fifo_empty),
                .underflow     (),
                .rd_rst_busy   (),
                .data_valid    (),
                .rd_data_count (),
                .almost_empty  (),
                .prog_empty    (),
                .injectsbiterr (1'b0),
                .injectdbiterr (1'b0),
                .sbiterr       (),
                .dbiterr       ()
            );
        end else begin : gen_direct_wr
            assign wr_fifo_full      = 1'b0;
            assign mem_wr_en         = wr_sample_now;
            assign mem_wr_addr       = wr_addr;
            assign mem_wr_pixel      = wr_pixel_packed;
            assign frame_complete_rd = wr_sample_now && (wr_addr == (FRAME_PIXELS - 1));
        end
    endgenerate

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A             (FRAME_ADDR_W),
        .ADDR_WIDTH_B             (FRAME_ADDR_W),
        .AUTO_SLEEP_TIME          (0),
        .BYTE_WRITE_WIDTH_A       (PACKED_PIXEL_W),
        .CLOCKING_MODE            (CLOCKING_MODE_STR),
        .ECC_MODE                 ("no_ecc"),
        .MEMORY_INIT_FILE         ("none"),
        .MEMORY_INIT_PARAM        ("0"),
        .MEMORY_OPTIMIZATION      ("true"),
        .MEMORY_PRIMITIVE         (MEMORY_PRIMITIVE_STR),
        .MEMORY_SIZE              (FRAME_BITS),
        .MESSAGE_CONTROL          (0),
        .READ_DATA_WIDTH_B        (PACKED_PIXEL_W),
        .READ_LATENCY_B           (READ_LATENCY),
        .READ_RESET_VALUE_B       ("0"),
        .RST_MODE_B               ("SYNC"),
        .SIM_ASSERT_CHK           (0),
        .USE_EMBEDDED_CONSTRAINT  (0),
        .USE_MEM_INIT             (1),
        .WAKEUP_TIME              ("disable_sleep"),
        .WRITE_DATA_WIDTH_A       (PACKED_PIXEL_W),
        .WRITE_MODE_B             ("read_first")
    ) u_framebuf (
        .sleep          (1'b0),
        .clka           (rd_clk),
        .ena            (mem_wr_en),
        .wea            (mem_wr_en),
        .addra          (mem_wr_addr),
        .dina           (mem_wr_pixel),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (rd_clk),
        .rstb           (~rst_n),
        .enb            (rd_en),
        .regceb         (1'b1),
        .addrb          (rd_addr),
        .doutb          (rd_pixel_buf),
        .sbiterrb       (),
        .dbiterrb       ()
    );
endmodule

// EO1920x1080_RawFrameBuffer -- added 2026-07-07 (see
// docs/DDR_EO_PANORAMA_FIX_PLAN.md section 18.14) for a genuinely
// unmanipulated single-camera DDR diagnostic: the SRC_EO0 (640x480)
// diagnostic still ran every pixel through EO1920x1080_Decimate3_FrameBuffer's
// crop (1920->1440 window) and subsample (chroma-pair + line decimation)
// logic before anything reached the write/DDR/read path, which is not
// "cam0 with zero frame manipulation" -- it's the same per-tile decimation
// the real 6-camera build uses, just without the compositor mixing six of
// them together. This module is a straight copy of
// EO1920x1080_Decimate3_FrameBuffer's CDC/memory-primitive structure with
// ALL crop/subsample logic deleted: every active pixel of every active line
// is captured, in raster order, at full native resolution. Default
// SRC_W/SRC_H/FRAME_ADDR_W are sized for the full 1920x1080 EO frame
// (2,073,600 pixels needs 21 address bits, not the 19 sufficient for a
// 640x480 tile).
module EO1920x1080_RawFrameBuffer #(
    parameter integer SRC_W        = 1920,
    parameter integer SRC_H        = 1080,
    parameter integer FRAME_ADDR_W = 21,
    parameter integer READ_LATENCY = 2,
    parameter        CLOCKING_MODE_STR = "common_clock",
    parameter        MEMORY_PRIMITIVE_STR = "ultra",
    parameter integer FIFO_RELATED_CLOCKS = 0,
    parameter integer USE_ASYNC_FIFO = 1
)(
    input  wire                     rst_n,
    input  wire                     wr_clk,
    input  wire                     wr_hsync,
    input  wire                     wr_vsync,
    input  wire [19:0]              wr_pixel,
    input  wire                     rd_clk,
    input  wire                     rd_frame_start,
    input  wire                     rd_en,
    input  wire [FRAME_ADDR_W-1:0]  rd_addr,
    output wire [19:0]              rd_pixel,
    output reg                      frame_valid
);
    localparam integer FRAME_PIXELS = SRC_W * SRC_H;
    localparam integer PACKED_PIXEL_W = 16;
    localparam integer FRAME_BITS   = FRAME_PIXELS * PACKED_PIXEL_W;
    localparam integer FIFO_WIDTH   = 1 + FRAME_ADDR_W + PACKED_PIXEL_W;

    reg [FRAME_ADDR_W-1:0] wr_addr;
    reg                    wr_hsync_d;
    reg                    wr_vsync_d;
    wire                   wr_frame_active;
    wire                   wr_frame_start;
    wire                   wr_fifo_full;
    wire                   wr_sample_now;
    wire [FIFO_WIDTH-1:0]  wr_fifo_din;
    wire                   mem_wr_en;
    wire [FRAME_ADDR_W-1:0] mem_wr_addr;
    wire [PACKED_PIXEL_W-1:0] mem_wr_pixel;
    wire                   frame_complete_rd;
    wire [PACKED_PIXEL_W-1:0] wr_pixel_packed;

    assign wr_pixel_packed = {wr_pixel[19:12], wr_pixel[9:2]};
    assign wr_frame_active = ~wr_vsync;
    assign wr_frame_start  = wr_vsync_d && ~wr_vsync;
    // No crop, no chroma/line phase gating -- every active pixel of every
    // active line, in raster order, exactly once.
    assign wr_sample_now   = wr_frame_active && wr_hsync &&
                             (wr_addr < FRAME_PIXELS) && !wr_fifo_full;
    assign wr_fifo_din     = {(wr_addr == (FRAME_PIXELS - 1)), wr_addr, wr_pixel_packed};

    always @(posedge wr_clk) begin
        if (!rst_n) begin
            wr_addr    <= {FRAME_ADDR_W{1'b0}};
            wr_hsync_d <= 1'b0;
            wr_vsync_d <= 1'b0;
        end else begin
            wr_hsync_d <= wr_hsync;
            wr_vsync_d <= wr_vsync;

            if (wr_frame_start) begin
                wr_addr <= {FRAME_ADDR_W{1'b0}};
            end else if (wr_sample_now) begin
                wr_addr <= wr_addr + {{(FRAME_ADDR_W-1){1'b0}}, 1'b1};
            end
        end
    end

    wire [PACKED_PIXEL_W-1:0] rd_pixel_buf;
    assign rd_pixel = {rd_pixel_buf[15:8], 2'b00, rd_pixel_buf[7:0], 2'b00};

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            frame_valid <= 1'b0;
        end else begin
            if (frame_complete_rd)
                frame_valid <= 1'b1;
        end
    end

    generate
        if (USE_ASYNC_FIFO) begin : gen_async_wr
            wire [FIFO_WIDTH-1:0] rd_fifo_dout;
            wire                  rd_fifo_empty;
            wire                  rd_fifo_pop;
            wire                  rd_fifo_last;
            wire [FRAME_ADDR_W-1:0] rd_fifo_addr;
            wire [PACKED_PIXEL_W-1:0] rd_fifo_pixel;
            wire                  wr_fifo_full_i;

            assign rd_fifo_pop     = !rd_fifo_empty;
            assign rd_fifo_last    = rd_fifo_dout[FIFO_WIDTH-1];
            assign rd_fifo_addr    = rd_fifo_dout[FRAME_ADDR_W+PACKED_PIXEL_W-1:PACKED_PIXEL_W];
            assign rd_fifo_pixel   = rd_fifo_dout[PACKED_PIXEL_W-1:0];
            assign wr_fifo_full    = wr_fifo_full_i;

            // Same retiming register as EO1920x1080_Decimate3_FrameBuffer
            // (see its comment above) -- write bus timing margin, not a
            // correctness requirement, kept for consistency/safety.
            reg                       mem_wr_en_r;
            reg [FRAME_ADDR_W-1:0]    mem_wr_addr_r;
            reg [PACKED_PIXEL_W-1:0]  mem_wr_pixel_r;
            reg                       frame_complete_rd_r;
            always @(posedge rd_clk) begin
                if (!rst_n) begin
                    mem_wr_en_r         <= 1'b0;
                    mem_wr_addr_r       <= {FRAME_ADDR_W{1'b0}};
                    mem_wr_pixel_r      <= {PACKED_PIXEL_W{1'b0}};
                    frame_complete_rd_r <= 1'b0;
                end else begin
                    mem_wr_en_r         <= rd_fifo_pop;
                    mem_wr_addr_r       <= rd_fifo_addr;
                    mem_wr_pixel_r      <= rd_fifo_pixel;
                    frame_complete_rd_r <= rd_fifo_pop && rd_fifo_last;
                end
            end
            assign mem_wr_en         = mem_wr_en_r;
            assign mem_wr_addr       = mem_wr_addr_r;
            assign mem_wr_pixel      = mem_wr_pixel_r;
            assign frame_complete_rd = frame_complete_rd_r;

            xpm_fifo_async #(
                .CDC_SYNC_STAGES     (2),
                .DOUT_RESET_VALUE    ("0"),
                .ECC_MODE            ("no_ecc"),
                .FIFO_MEMORY_TYPE    ("auto"),
                .FIFO_READ_LATENCY   (0),
                .FIFO_WRITE_DEPTH    (1024),
                .FULL_RESET_VALUE    (0),
                .PROG_EMPTY_THRESH   (10),
                .PROG_FULL_THRESH    (900),
                .RD_DATA_COUNT_WIDTH (11),
                .READ_DATA_WIDTH     (FIFO_WIDTH),
                .READ_MODE           ("fwft"),
                .RELATED_CLOCKS      (FIFO_RELATED_CLOCKS),
                .SIM_ASSERT_CHK      (0),
                .USE_ADV_FEATURES    ("0000"),
                .WAKEUP_TIME         (0),
                .WRITE_DATA_WIDTH    (FIFO_WIDTH),
                .WR_DATA_COUNT_WIDTH (11)
            ) u_wr_cdc_fifo (
                .sleep         (1'b0),
                .rst           (~rst_n),
                .wr_clk        (wr_clk),
                .wr_en         (wr_sample_now),
                .din           (wr_fifo_din),
                .full          (wr_fifo_full_i),
                .overflow      (),
                .wr_rst_busy   (),
                .wr_ack        (),
                .wr_data_count (),
                .almost_full   (),
                .prog_full     (),
                .rd_clk        (rd_clk),
                .rd_en         (rd_fifo_pop),
                .dout          (rd_fifo_dout),
                .empty         (rd_fifo_empty),
                .underflow     (),
                .rd_rst_busy   (),
                .data_valid    (),
                .rd_data_count (),
                .almost_empty  (),
                .prog_empty    (),
                .injectsbiterr (1'b0),
                .injectdbiterr (1'b0),
                .sbiterr       (),
                .dbiterr       ()
            );
        end else begin : gen_direct_wr
            assign wr_fifo_full      = 1'b0;
            assign mem_wr_en         = wr_sample_now;
            assign mem_wr_addr       = wr_addr;
            assign mem_wr_pixel      = wr_pixel_packed;
            assign frame_complete_rd = wr_sample_now && (wr_addr == (FRAME_PIXELS - 1));
        end
    endgenerate

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A             (FRAME_ADDR_W),
        .ADDR_WIDTH_B             (FRAME_ADDR_W),
        .AUTO_SLEEP_TIME          (0),
        .BYTE_WRITE_WIDTH_A       (PACKED_PIXEL_W),
        .CLOCKING_MODE            (CLOCKING_MODE_STR),
        .ECC_MODE                 ("no_ecc"),
        .MEMORY_INIT_FILE         ("none"),
        .MEMORY_INIT_PARAM        ("0"),
        .MEMORY_OPTIMIZATION      ("true"),
        .MEMORY_PRIMITIVE         (MEMORY_PRIMITIVE_STR),
        .MEMORY_SIZE              (FRAME_BITS),
        .MESSAGE_CONTROL          (0),
        .READ_DATA_WIDTH_B        (PACKED_PIXEL_W),
        .READ_LATENCY_B           (READ_LATENCY),
        .READ_RESET_VALUE_B       ("0"),
        .RST_MODE_B               ("SYNC"),
        .SIM_ASSERT_CHK           (0),
        .USE_EMBEDDED_CONSTRAINT  (0),
        .USE_MEM_INIT             (1),
        .WAKEUP_TIME              ("disable_sleep"),
        .WRITE_DATA_WIDTH_A       (PACKED_PIXEL_W),
        .WRITE_MODE_B             ("read_first")
    ) u_framebuf (
        .sleep          (1'b0),
        .clka           (rd_clk),
        .ena            (mem_wr_en),
        .wea            (mem_wr_en),
        .addra          (mem_wr_addr),
        .dina           (mem_wr_pixel),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (rd_clk),
        .rstb           (~rst_n),
        .enb            (rd_en),
        .regceb         (1'b1),
        .addrb          (rd_addr),
        .doutb          (rd_pixel_buf),
        .sbiterrb       (),
        .dbiterrb       ()
    );
endmodule
