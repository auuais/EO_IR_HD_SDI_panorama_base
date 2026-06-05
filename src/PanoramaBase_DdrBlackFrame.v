//============================================================================
// PanoramaBase_DdrBlackFrame  -  clean rewrite (2026-06-03)
//
// IR-single live video through a DDR4 ping-pong output framebuffer.
//
//   IR camera  --(cam pclk)-->  per-camera BRAM frame buffer
//        |                          | frame_pulse (in ui_clk domain)
//        v                          v
//   ui_clk COPY: BRAM -> DDR write-bank, 10240 x 512-bit bursts.
//        on completion: pending_bank = write-bank; flip write-bank.
//        v
//   ui_clk SCAN: at each HD frame boundary adopt the pending bank as the
//        read-bank and sweep it out of DDR -> beat_fifo -> unpack -> pix_fifo.
//        v
//   rd_clk RENDERER: BT.1120 timing, stream pix_fifo into a centered 640x512
//        window, black everywhere else.
//
// Why this version fixes the long-standing failures:
//  * NO mode teardown.  The UI streams SET_MODE rapidly (EO/IR/stack); the old
//    FSM reset ir_rd_frame_valid on every non-IR blip, destroying the committed
//    frame (the "cyan / committed-then-lost" symptom).  Here the IR pipeline
//    runs continuously and the TOP-LEVEL mux decides EO-vs-processed *display*.
//    The selected camera is latched per copy, so changing ir_sel simply takes
//    effect on the next captured frame -- no pipeline reset, no black-out.
//  * Single DDR command per ui_clk cycle (read-priority arbiter), so the
//    write-data strobes are never issued without their own write command.
//  * Every ui_clk<->rd_clk crossing is a 2-FF synchronizer (control) or the
//    async pix_fifo (pixels).  The companion XDC declares those domains
//    asynchronous (set_clock_groups) so they stop being timed as synchronous
//    paths -- that was the dominant source of the negative WNS.
//============================================================================
module PanoramaBase_DdrBlackFrame(
    input  wire        rst_n,
    input  wire        clk_for_por,
    input  wire        rd_clk,
    input  wire        ir_single_mode,
    input  wire [2:0]  ir_sel,
    input  wire        ir0_wr_clk,
    input  wire        ir0_wr_hsync,
    input  wire        ir0_wr_vsync,
    input  wire [7:0]  ir0_wr_pixel,
    input  wire        ir1_wr_clk,
    input  wire        ir1_wr_hsync,
    input  wire        ir1_wr_vsync,
    input  wire [7:0]  ir1_wr_pixel,
    input  wire        ir2_wr_clk,
    input  wire        ir2_wr_hsync,
    input  wire        ir2_wr_vsync,
    input  wire [7:0]  ir2_wr_pixel,
    input  wire        ir3_wr_clk,
    input  wire        ir3_wr_hsync,
    input  wire        ir3_wr_vsync,
    input  wire [7:0]  ir3_wr_pixel,
    input  wire        ir4_wr_clk,
    input  wire        ir4_wr_hsync,
    input  wire        ir4_wr_vsync,
    input  wire [7:0]  ir4_wr_pixel,
    input  wire        ir5_wr_clk,
    input  wire        ir5_wr_hsync,
    input  wire        ir5_wr_vsync,
    input  wire [7:0]  ir5_wr_pixel,
    input  wire        c0_sys_clk_p,
    input  wire        c0_sys_clk_n,
    output wire [16:0] c0_ddr4_adr,
    output wire [1:0]  c0_ddr4_ba,
    output wire [0:0]  c0_ddr4_cke,
    output wire [0:0]  c0_ddr4_cs_n,
    inout  wire [7:0]  c0_ddr4_dm_dbi_n,
    inout  wire [63:0] c0_ddr4_dq,
    inout  wire [7:0]  c0_ddr4_dqs_c,
    inout  wire [7:0]  c0_ddr4_dqs_t,
    output wire [0:0]  c0_ddr4_odt,
    output wire [0:0]  c0_ddr4_bg,
    output wire        c0_ddr4_reset_n,
    output wire        c0_ddr4_act_n,
    output wire [0:0]  c0_ddr4_ck_c,
    output wire [0:0]  c0_ddr4_ck_t,
    output wire        init_calib_complete_o,
    output wire        hd_de,
    output wire        hd_hsync,
    output wire        hd_vsync,
    output wire [19:0] hd_dout
);
    //------------------------------------------------------------------------
    // Geometry / DDR layout
    //------------------------------------------------------------------------
    localparam integer SRC_W         = 640;
    localparam integer SRC_H         = 512;
    localparam [18:0]  FRAME_PIXELS  = 19'd327680;   // 640*512
    localparam [16:0]  BEATS_TOTAL   = 17'd10240;    // 327680/32 pixels-per-beat
    localparam [28:0]  ADDR_STRIDE   = 29'd8;        // app_addr units per 512-bit beat
    localparam [28:0]  BANK0_BASE    = 29'd0;
    localparam [28:0]  BANK1_BASE    = BEATS_TOTAL * ADDR_STRIDE; // 81920
    localparam [6:0]   MAX_OUTSTANDING = 7'd32;
    localparam [15:0]  BLACK_PIXEL   = 16'h1080;     // Y=0x10, C=0x80 (neutral)
    localparam [511:0] BLACK_BURST   = {32{BLACK_PIXEL}};

    // DIAGNOSTIC BISECTION: when 1, the copy writes a known raster ramp
    // (luma = pixel_index[7:0]) into DDR instead of the captured camera pixel.
    // Everything else (copy write, DDR store, scan, unpack, render) runs exactly
    // as in the live path.  Clean diagonal ramp on screen  => the whole DDR
    // pipeline is correct and the live fault is the BRAM/camera data.  Garbled
    // or green/underflow => the fault is in the write/DDR/scan/render path.
    // Set back to 0 for live IR.  When 1, the copy is also self-triggered every
    // display frame (camera-independent) so the DDR write/scan/render path is
    // exercised with a known ramp regardless of which IR camera is connected.
    localparam         PATTERN_TEST  = 1'b1;

    //------------------------------------------------------------------------
    // Power-on reset for the MIG (free-running clk_for_por)
    //------------------------------------------------------------------------
    reg [19:0] por_cnt = 20'd0;
    reg        sys_rst = 1'b1;
    always @(posedge clk_for_por) begin
        if (sys_rst) begin
            por_cnt <= por_cnt + 20'd1;
            if (&por_cnt[19:18])
                sys_rst <= 1'b0;
        end
    end

    //------------------------------------------------------------------------
    // DDR4 MIG (native user interface) - instance preserved verbatim
    //------------------------------------------------------------------------
    wire         c0_init_calib_complete;
    wire         dbg_clk;
    wire [511:0] dbg_bus;
    wire         c0_ddr4_ui_clk;
    wire         c0_ddr4_ui_clk_sync_rst;
    reg          c0_ddr4_app_en;
    reg          c0_ddr4_app_hi_pri;
    reg          c0_ddr4_app_wdf_end;
    reg          c0_ddr4_app_wdf_wren;
    wire         c0_ddr4_app_rd_data_end;
    wire         c0_ddr4_app_rd_data_valid;
    wire         c0_ddr4_app_rdy;
    wire         c0_ddr4_app_wdf_rdy;
    reg  [28:0]  c0_ddr4_app_addr;
    reg  [2:0]   c0_ddr4_app_cmd;
    reg  [511:0] c0_ddr4_app_wdf_data;
    reg  [63:0]  c0_ddr4_app_wdf_mask;
    wire [511:0] c0_ddr4_app_rd_data;

    assign init_calib_complete_o = c0_init_calib_complete;

    ddr4_sub64 u_ddr4_sub64 (
        .c0_init_calib_complete(c0_init_calib_complete),
        .dbg_clk(dbg_clk),
        .c0_sys_clk_p(c0_sys_clk_p),
        .c0_sys_clk_n(c0_sys_clk_n),
        .dbg_bus(dbg_bus),
        .c0_ddr4_adr(c0_ddr4_adr),
        .c0_ddr4_ba(c0_ddr4_ba),
        .c0_ddr4_cke(c0_ddr4_cke),
        .c0_ddr4_cs_n(c0_ddr4_cs_n),
        .c0_ddr4_dm_dbi_n(c0_ddr4_dm_dbi_n),
        .c0_ddr4_dq(c0_ddr4_dq),
        .c0_ddr4_dqs_c(c0_ddr4_dqs_c),
        .c0_ddr4_dqs_t(c0_ddr4_dqs_t),
        .c0_ddr4_odt(c0_ddr4_odt),
        .c0_ddr4_bg(c0_ddr4_bg),
        .c0_ddr4_reset_n(c0_ddr4_reset_n),
        .c0_ddr4_act_n(c0_ddr4_act_n),
        .c0_ddr4_ck_c(c0_ddr4_ck_c),
        .c0_ddr4_ck_t(c0_ddr4_ck_t),
        .c0_ddr4_ui_clk(c0_ddr4_ui_clk),
        .c0_ddr4_ui_clk_sync_rst(c0_ddr4_ui_clk_sync_rst),
        .c0_ddr4_app_en(c0_ddr4_app_en),
        .c0_ddr4_app_hi_pri(c0_ddr4_app_hi_pri),
        .c0_ddr4_app_wdf_end(c0_ddr4_app_wdf_end),
        .c0_ddr4_app_wdf_wren(c0_ddr4_app_wdf_wren),
        .c0_ddr4_app_rd_data_end(c0_ddr4_app_rd_data_end),
        .c0_ddr4_app_rd_data_valid(c0_ddr4_app_rd_data_valid),
        .c0_ddr4_app_rdy(c0_ddr4_app_rdy),
        .c0_ddr4_app_wdf_rdy(c0_ddr4_app_wdf_rdy),
        .c0_ddr4_app_addr(c0_ddr4_app_addr),
        .c0_ddr4_app_cmd(c0_ddr4_app_cmd),
        .c0_ddr4_app_wdf_data(c0_ddr4_app_wdf_data),
        .c0_ddr4_app_wdf_mask(c0_ddr4_app_wdf_mask),
        .c0_ddr4_app_rd_data(c0_ddr4_app_rd_data),
        .sys_rst(sys_rst)
    );

    wire ui_rst = c0_ddr4_ui_clk_sync_rst;

    //------------------------------------------------------------------------
    // Pixel FIFO  (ui_clk write  ->  rd_clk read) and beat FIFO (ui_clk)
    // -- instances preserved verbatim from the proven build.
    //------------------------------------------------------------------------
    wire        pix_fifo_prog_full;
    wire        pix_fifo_prog_empty;
    wire        pix_fifo_empty;
    wire [15:0] pix_fifo_dout;
    wire        renderer_frame_toggle;
    reg         pix_fifo_wr_en;
    reg  [15:0] pix_fifo_wr_data;
    wire        pix_fifo_full;
    wire        pix_fifo_wr_rst_busy;
    wire        pix_fifo_rd_rst_busy;
    wire        pix_fifo_rd_en;

    xpm_fifo_async #(
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("block"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (8192),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (4096),
        .PROG_FULL_THRESH    (7800),
        .RD_DATA_COUNT_WIDTH (13),
        .READ_DATA_WIDTH     (16),
        .READ_MODE           ("fwft"),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0004"),
        .WAKEUP_TIME         (0),
        .WR_DATA_COUNT_WIDTH (13),
        .WRITE_DATA_WIDTH    (16),
        .CDC_SYNC_STAGES     (2),
        .RELATED_CLOCKS      (0)
    ) u_pix_fifo (
        .rst           (ui_rst),
        .wr_clk        (c0_ddr4_ui_clk),
        .rd_clk        (rd_clk),
        .din           (pix_fifo_wr_data),
        .wr_en         (pix_fifo_wr_en),
        .full          (pix_fifo_full),
        .prog_full     (pix_fifo_prog_full),
        .rd_en         (pix_fifo_rd_en),
        .dout          (pix_fifo_dout),
        .empty         (pix_fifo_empty),
        .prog_empty    (pix_fifo_prog_empty),
        .wr_rst_busy   (pix_fifo_wr_rst_busy),
        .rd_rst_busy   (pix_fifo_rd_rst_busy),
        .sleep         (1'b0),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0)
    );

    wire         beat_fifo_prog_full;
    wire         beat_fifo_empty;
    wire [511:0] beat_fifo_dout;
    reg          beat_fifo_wr_en;
    reg          beat_fifo_rd_en;
    wire         beat_fifo_full;

    xpm_fifo_sync #(
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("block"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (128),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (8),
        .PROG_FULL_THRESH    (96),
        .RD_DATA_COUNT_WIDTH (7),
        .READ_DATA_WIDTH     (512),
        .READ_MODE           ("fwft"),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0004"),
        .WAKEUP_TIME         (0),
        .WR_DATA_COUNT_WIDTH (7),
        .WRITE_DATA_WIDTH    (512)
    ) u_beat_fifo (
        .rst           (ui_rst),
        .wr_clk        (c0_ddr4_ui_clk),
        .din           (c0_ddr4_app_rd_data),
        .wr_en         (beat_fifo_wr_en),
        .full          (beat_fifo_full),
        .prog_full     (beat_fifo_prog_full),
        .rd_en         (beat_fifo_rd_en),
        .dout          (beat_fifo_dout),
        .empty         (beat_fifo_empty),
        .sleep         (1'b0),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0)
    );

    //------------------------------------------------------------------------
    // Control deglitch: synchronize {ir_single_mode, ir_sel} into ui_clk and
    // only accept a value once it has been stable for 2 ui_clk cycles.
    //------------------------------------------------------------------------
    reg [3:0] mode_meta, mode_sync, mode_sync_d, mode_stable;
    always @(posedge c0_ddr4_ui_clk) begin
        if (ui_rst) begin
            mode_meta   <= 4'd0;
            mode_sync   <= 4'd0;
            mode_sync_d <= 4'd0;
            mode_stable <= 4'd0;
        end else begin
            mode_meta   <= {ir_single_mode, ir_sel};
            mode_sync   <= mode_meta;
            mode_sync_d <= mode_sync;
            if (mode_sync == mode_sync_d)
                mode_stable <= mode_sync;
        end
    end
    wire       ir_single_ui = mode_stable[3];
    wire [2:0] ir_sel_ui    = mode_stable[2:0];

    //------------------------------------------------------------------------
    // Per-camera BRAM capture buffers (proven IR640x512_GrayFrameBuffer_Single,
    // defined in PanoramaBase_IrSingleBuffered.v).  Write side = camera pclk,
    // read side = ui_clk, frame_pulse/frame_valid produced in ui_clk domain.
    //------------------------------------------------------------------------
    reg        fb_rd_en;
    reg [18:0] fb_rd_addr;
    reg [2:0]  ir_sel_latched;

    wire [7:0] irfb0_pixel, irfb1_pixel, irfb2_pixel, irfb3_pixel, irfb4_pixel, irfb5_pixel;
    wire       irfb0_pulse, irfb1_pulse, irfb2_pulse, irfb3_pulse, irfb4_pulse, irfb5_pulse;

    wire       irfb0_rd_en = fb_rd_en && (ir_sel_latched == 3'd0);
    wire       irfb1_rd_en = fb_rd_en && (ir_sel_latched == 3'd1);
    wire       irfb2_rd_en = fb_rd_en && (ir_sel_latched == 3'd2);
    wire       irfb3_rd_en = fb_rd_en && (ir_sel_latched == 3'd3);
    wire       irfb4_rd_en = fb_rd_en && (ir_sel_latched == 3'd4);
    wire       irfb5_rd_en = fb_rd_en && (ir_sel_latched == 3'd5);

    IR640x512_GrayFrameBuffer_Single u_irfb0 (
        .rst_n(rst_n), .wr_clk(ir0_wr_clk), .wr_hsync(ir0_wr_hsync), .wr_vsync(ir0_wr_vsync), .wr_pixel(ir0_wr_pixel),
        .rd_clk(c0_ddr4_ui_clk), .rd_en(irfb0_rd_en), .rd_addr(fb_rd_addr), .rd_pixel(irfb0_pixel), .frame_valid(), .frame_pulse(irfb0_pulse));
    IR640x512_GrayFrameBuffer_Single u_irfb1 (
        .rst_n(rst_n), .wr_clk(ir1_wr_clk), .wr_hsync(ir1_wr_hsync), .wr_vsync(ir1_wr_vsync), .wr_pixel(ir1_wr_pixel),
        .rd_clk(c0_ddr4_ui_clk), .rd_en(irfb1_rd_en), .rd_addr(fb_rd_addr), .rd_pixel(irfb1_pixel), .frame_valid(), .frame_pulse(irfb1_pulse));
    IR640x512_GrayFrameBuffer_Single u_irfb2 (
        .rst_n(rst_n), .wr_clk(ir2_wr_clk), .wr_hsync(ir2_wr_hsync), .wr_vsync(ir2_wr_vsync), .wr_pixel(ir2_wr_pixel),
        .rd_clk(c0_ddr4_ui_clk), .rd_en(irfb2_rd_en), .rd_addr(fb_rd_addr), .rd_pixel(irfb2_pixel), .frame_valid(), .frame_pulse(irfb2_pulse));
    IR640x512_GrayFrameBuffer_Single u_irfb3 (
        .rst_n(rst_n), .wr_clk(ir3_wr_clk), .wr_hsync(ir3_wr_hsync), .wr_vsync(ir3_wr_vsync), .wr_pixel(ir3_wr_pixel),
        .rd_clk(c0_ddr4_ui_clk), .rd_en(irfb3_rd_en), .rd_addr(fb_rd_addr), .rd_pixel(irfb3_pixel), .frame_valid(), .frame_pulse(irfb3_pulse));
    IR640x512_GrayFrameBuffer_Single u_irfb4 (
        .rst_n(rst_n), .wr_clk(ir4_wr_clk), .wr_hsync(ir4_wr_hsync), .wr_vsync(ir4_wr_vsync), .wr_pixel(ir4_wr_pixel),
        .rd_clk(c0_ddr4_ui_clk), .rd_en(irfb4_rd_en), .rd_addr(fb_rd_addr), .rd_pixel(irfb4_pixel), .frame_valid(), .frame_pulse(irfb4_pulse));
    IR640x512_GrayFrameBuffer_Single u_irfb5 (
        .rst_n(rst_n), .wr_clk(ir5_wr_clk), .wr_hsync(ir5_wr_hsync), .wr_vsync(ir5_wr_vsync), .wr_pixel(ir5_wr_pixel),
        .rd_clk(c0_ddr4_ui_clk), .rd_en(irfb5_rd_en), .rd_addr(fb_rd_addr), .rd_pixel(irfb5_pixel), .frame_valid(), .frame_pulse(irfb5_pulse));

    wire [7:0] sel_rd_pixel = (ir_sel_latched == 3'd0) ? irfb0_pixel :
                              (ir_sel_latched == 3'd1) ? irfb1_pixel :
                              (ir_sel_latched == 3'd2) ? irfb2_pixel :
                              (ir_sel_latched == 3'd3) ? irfb3_pixel :
                              (ir_sel_latched == 3'd4) ? irfb4_pixel : irfb5_pixel;
    wire       sel_pulse    = (ir_sel_latched == 3'd0) ? irfb0_pulse :
                              (ir_sel_latched == 3'd1) ? irfb1_pulse :
                              (ir_sel_latched == 3'd2) ? irfb2_pulse :
                              (ir_sel_latched == 3'd3) ? irfb3_pulse :
                              (ir_sel_latched == 3'd4) ? irfb4_pulse : irfb5_pulse;

    //------------------------------------------------------------------------
    // Copy / scan / arbiter state (ui_clk)
    //------------------------------------------------------------------------
    reg        running;            // calibration complete, pipeline live
    reg        dbg_pulse_seen;
    reg        dbg_wpend_seen;
    reg        dbg_grant_seen;
    reg        dbg_copydone_seen;
    reg        dbg_scan_issue_seen;
    reg        dbg_rddata_seen;
    reg        dbg_pixwrite_seen;

    // BRAM -> pack -> DDR write (copy)
    reg        copy_active;
    reg        fb_rd_en_d1, fb_rd_en_d2;
    reg        fb_rd_busy;
    reg        fb_write_pending;
    reg [5:0]  fb_pack_count;
    reg [16:0] fb_burst_count;
    reg [511:0] fb_pack_buf;
    reg [28:0] wr_addr;

    // ping-pong bank bookkeeping
    reg        wr_bank;            // bank currently being written
    reg        rd_bank;            // bank currently being scanned out
    reg        pending_bank;       // freshly-completed bank awaiting commit
    reg        pending_valid;
    reg        frame_valid;        // at least one bank committed & displayable

    // DDR -> beat_fifo (scan)
    reg        scan_active;
    reg [28:0] rd_addr;
    reg [16:0] rd_issue_count;
    reg [6:0]  outstanding;
    reg [6:0]  outstanding_next;

    // beat_fifo -> pix_fifo unpack
    reg [511:0] unpack_shift;
    reg [5:0]   unpack_count;

    // renderer frame-boundary pulse, synchronized into ui_clk
    reg        ftog_meta, ftog_sync, ftog_sync_d;

    wire [28:0] wr_bank_base = wr_bank ? BANK1_BASE : BANK0_BASE;
    wire [28:0] rd_bank_base = rd_bank ? BANK1_BASE : BANK0_BASE;

    wire frame_edge = (ftog_sync != ftog_sync_d);

    // Scan may issue a read this cycle
    wire scan_ok = running && scan_active && c0_ddr4_app_rdy &&
                   !beat_fifo_prog_full &&
                   !pix_fifo_wr_rst_busy && (outstanding < MAX_OUTSTANDING);
    // Copy may issue a write this cycle
    wire write_ok = running && copy_active && fb_write_pending &&
                    c0_ddr4_app_rdy && c0_ddr4_app_wdf_rdy;

    always @(posedge c0_ddr4_ui_clk) begin
        if (ui_rst) begin
            running          <= 1'b0;
            c0_ddr4_app_en   <= 1'b0;
            c0_ddr4_app_hi_pri <= 1'b0;
            c0_ddr4_app_wdf_end <= 1'b0;
            c0_ddr4_app_wdf_wren <= 1'b0;
            c0_ddr4_app_addr <= 29'd0;
            c0_ddr4_app_cmd  <= 3'd0;
            c0_ddr4_app_wdf_data <= BLACK_BURST;
            c0_ddr4_app_wdf_mask <= 64'd0;
            pix_fifo_wr_en   <= 1'b0;
            pix_fifo_wr_data <= 16'd0;
            beat_fifo_wr_en  <= 1'b0;
            beat_fifo_rd_en  <= 1'b0;
            fb_rd_en         <= 1'b0;
            fb_rd_en_d1      <= 1'b0;
            fb_rd_en_d2      <= 1'b0;
            fb_rd_addr       <= 19'd0;
            fb_rd_busy       <= 1'b0;
            fb_write_pending <= 1'b0;
            fb_pack_count    <= 6'd0;
            fb_burst_count   <= 17'd0;
            fb_pack_buf      <= 512'd0;
            wr_addr          <= BANK0_BASE;
            copy_active      <= 1'b0;
            ir_sel_latched   <= 3'd0;
            wr_bank          <= 1'b0;
            rd_bank          <= 1'b0;
            pending_bank     <= 1'b0;
            pending_valid    <= 1'b0;
            frame_valid      <= 1'b0;
            dbg_pulse_seen   <= 1'b0;
            dbg_wpend_seen   <= 1'b0;
            dbg_grant_seen   <= 1'b0;
            dbg_copydone_seen<= 1'b0;
            dbg_scan_issue_seen <= 1'b0;
            dbg_rddata_seen  <= 1'b0;
            dbg_pixwrite_seen<= 1'b0;
            scan_active      <= 1'b0;
            rd_addr          <= BANK0_BASE;
            rd_issue_count   <= 17'd0;
            outstanding      <= 7'd0;
            unpack_shift     <= 512'd0;
            unpack_count     <= 6'd0;
            ftog_meta        <= 1'b0;
            ftog_sync        <= 1'b0;
            ftog_sync_d      <= 1'b0;
        end else begin
            // --- default strobes (single-cycle) ---
            c0_ddr4_app_en       <= 1'b0;
            c0_ddr4_app_hi_pri   <= 1'b0;
            c0_ddr4_app_wdf_wren <= 1'b0;
            c0_ddr4_app_wdf_end  <= 1'b0;
            c0_ddr4_app_addr     <= 29'd0;
            c0_ddr4_app_cmd      <= 3'd0;
            c0_ddr4_app_wdf_data <= BLACK_BURST;
            c0_ddr4_app_wdf_mask <= 64'd0;
            pix_fifo_wr_en       <= 1'b0;
            beat_fifo_wr_en      <= 1'b0;
            beat_fifo_rd_en      <= 1'b0;
            fb_rd_en             <= 1'b0;
            fb_rd_en_d1          <= fb_rd_en;
            fb_rd_en_d2          <= fb_rd_en_d1;

            // renderer frame-toggle CDC (rd_clk -> ui_clk)
            ftog_meta   <= renderer_frame_toggle;
            ftog_sync   <= ftog_meta;
            ftog_sync_d <= ftog_sync;

            outstanding_next = outstanding;

            //----------------------------------------------------------------
            // beat_fifo -> 32x16b unpack -> pix_fifo
            //----------------------------------------------------------------
            if ((unpack_count != 0) && !pix_fifo_full && !pix_fifo_wr_rst_busy) begin
                pix_fifo_wr_en   <= 1'b1;
                pix_fifo_wr_data <= unpack_shift[15:0];
                unpack_shift     <= {16'd0, unpack_shift[511:16]};
                unpack_count     <= unpack_count - 6'd1;
                dbg_pixwrite_seen<= 1'b1;
            end else if (!beat_fifo_empty && !pix_fifo_prog_full && !pix_fifo_wr_rst_busy) begin
                beat_fifo_rd_en <= 1'b1;
                unpack_shift    <= beat_fifo_dout;
                unpack_count    <= 6'd32;
            end

            // DDR read data returns -> push to beat_fifo, decrement outstanding
            if (c0_ddr4_app_rd_data_valid) begin
                beat_fifo_wr_en <= 1'b1;
                dbg_rddata_seen <= 1'b1;
                if (outstanding_next != 0)
                    outstanding_next = outstanding_next - 7'd1;
            end

            //----------------------------------------------------------------
            // BRAM read result -> pack into the 512-bit burst buffer.
            // fb_rd_addr is presented WITH fb_rd_en; the result is consumed two
            // cycles later (READ_LATENCY=2) at fb_rd_en_d2, where we advance the
            // address.  Each read yields exactly one packed pixel.
            //----------------------------------------------------------------
            if (fb_rd_en_d2) begin
                fb_pack_buf[{fb_pack_count, 4'b0000} +: 16] <=
                    PATTERN_TEST ? {fb_rd_addr[7:0], 8'h80}   // known raster ramp
                                 : {sel_rd_pixel,    8'h80};  // live captured pixel
                fb_rd_busy <= 1'b0;
                fb_rd_addr <= fb_rd_addr + 19'd1;
                if (fb_pack_count == 6'd31)
                    fb_write_pending <= 1'b1;
                else
                    fb_pack_count <= fb_pack_count + 6'd1;
            end

            if (!running) begin
                //------------------------------------------------------------
                // Wait for DDR calibration, then run forever.
                //------------------------------------------------------------
                copy_active   <= 1'b0;
                scan_active   <= 1'b0;
                pending_valid <= 1'b0;
                frame_valid   <= 1'b0;
                dbg_pulse_seen<= 1'b0;
                dbg_wpend_seen<= 1'b0;
                dbg_grant_seen<= 1'b0;
                dbg_copydone_seen <= 1'b0;
                dbg_scan_issue_seen <= 1'b0;
                dbg_rddata_seen  <= 1'b0;
                dbg_pixwrite_seen<= 1'b0;
                wr_bank       <= 1'b0;
                rd_bank       <= 1'b0;
                ir_sel_latched<= ir_sel_ui;
                if (c0_init_calib_complete)
                    running <= 1'b1;
            end else begin
                //------------------------------------------------------------
                // Track the selected camera while idle; freeze it during a copy
                // so a mode/camera change never tears down an in-flight copy.
                //------------------------------------------------------------
                if (!copy_active)
                    ir_sel_latched <= ir_sel_ui;

                if (sel_pulse)
                    dbg_pulse_seen <= 1'b1;

                //------------------------------------------------------------
                // Start a copy on a fresh captured frame for the selected cam.
                // Gated by ir_single_ui so we don't copy during EO/other modes,
                // but an already-running copy is NEVER aborted by a mode change
                // (that teardown was the old "committed-then-lost / cyan" bug).
                //------------------------------------------------------------
                // PATTERN_TEST: self-trigger one copy per display frame so the DDR
                // write/scan/render path is exercised with a known ramp even with no
                // camera on the forced slot.  Live mode triggers on the camera pulse.
                if ((( PATTERN_TEST && frame_edge) ||
                     (!PATTERN_TEST && sel_pulse && ir_single_ui)) && !copy_active) begin
                    copy_active      <= 1'b1;
                    wr_addr          <= wr_bank_base;
                    fb_rd_addr       <= 19'd0;
                    fb_pack_count    <= 6'd0;
                    fb_burst_count   <= 17'd0;
                    fb_rd_busy       <= 1'b0;
                    fb_write_pending <= 1'b0;
                    fb_pack_buf      <= 512'd0;
                end

                //------------------------------------------------------------
                // Issue BRAM reads, one outstanding at a time.
                //------------------------------------------------------------
                if (copy_active && !fb_rd_busy && !fb_write_pending && (fb_rd_addr < FRAME_PIXELS)) begin
                    fb_rd_en   <= 1'b1;
                    fb_rd_busy <= 1'b1;
                end

                if (fb_write_pending)
                    dbg_wpend_seen <= 1'b1;

                //------------------------------------------------------------
                // Frame-boundary commit (issues no DDR command): adopt a freshly
                // completed bank and (re)start a scan of the read bank so the
                // display refreshes every HD frame.
                //------------------------------------------------------------
                if (frame_edge && !scan_active) begin
                    if (pending_valid) begin
                        rd_bank       <= pending_bank;
                        pending_valid <= 1'b0;
                        frame_valid   <= 1'b1;
                        rd_addr       <= pending_bank ? BANK1_BASE : BANK0_BASE;
                    end else begin
                        rd_addr       <= rd_bank_base;
                    end
                    if (frame_valid || pending_valid) begin
                        scan_active     <= 1'b1;
                        rd_issue_count  <= 17'd0;
                        outstanding_next = 7'd0;
                        unpack_count    <= 6'd0;
                        unpack_shift    <= 512'd0;
                    end
                end

                //------------------------------------------------------------
                // Single DDR command arbiter: read (scan) has priority over
                // write (copy) so the display FIFO never underflows; the copy
                // has a full frame of slack and fills the gaps.
                //------------------------------------------------------------
                if (scan_ok) begin
                    c0_ddr4_app_en   <= 1'b1;
                    c0_ddr4_app_cmd  <= 3'b001;           // read
                    c0_ddr4_app_addr <= rd_addr;
                    dbg_scan_issue_seen <= 1'b1;
                    outstanding_next = outstanding_next + 7'd1;
                    if (rd_issue_count == BEATS_TOTAL - 1) begin
                        scan_active    <= 1'b0;
                        rd_issue_count <= 17'd0;
                    end else begin
                        rd_issue_count <= rd_issue_count + 17'd1;
                        rd_addr        <= rd_addr + ADDR_STRIDE;
                    end
                end else if (write_ok) begin
                    c0_ddr4_app_en       <= 1'b1;
                    c0_ddr4_app_cmd      <= 3'b000;       // write
                    c0_ddr4_app_addr     <= wr_addr;
                    c0_ddr4_app_wdf_data <= fb_pack_buf;
                    c0_ddr4_app_wdf_wren <= 1'b1;
                    c0_ddr4_app_wdf_end  <= 1'b1;
                    dbg_grant_seen       <= 1'b1;
                    fb_write_pending     <= 1'b0;
                    fb_pack_count        <= 6'd0;
                    if (fb_burst_count == BEATS_TOTAL - 1) begin
                        // copy complete: publish this bank, flip write bank
                        copy_active   <= 1'b0;
                        pending_bank  <= wr_bank;
                        pending_valid <= 1'b1;
                        dbg_copydone_seen <= 1'b1;
                        wr_bank       <= ~wr_bank;
                    end else begin
                        fb_burst_count <= fb_burst_count + 17'd1;
                        wr_addr        <= wr_addr + ADDR_STRIDE;
                    end
                end
            end

            outstanding <= outstanding_next;
        end
    end

    //------------------------------------------------------------------------
    // HD renderer (rd_clk).  Streams the committed frame into a centered
    // 640x512 window; black elsewhere.  All ui_clk control inputs crossed via
    // 2-FF synchronizers.
    //------------------------------------------------------------------------
    PanoramaBase_HdDdrRenderer u_hd_renderer (
        .rst_n          (rst_n),
        .rd_clk         (rd_clk),
        .mode_enabled   (ir_single_ui),
        .dbg_pulse_seen (dbg_pulse_seen),
        .dbg_wpend_seen (dbg_wpend_seen),
        .dbg_grant_seen (dbg_grant_seen),
        .dbg_copydone_seen(dbg_copydone_seen),
        .dbg_scan_issue_seen(dbg_scan_issue_seen),
        .dbg_rddata_seen(dbg_rddata_seen),
        .dbg_pixwrite_seen(dbg_pixwrite_seen),
        .copy_active    (copy_active),
        .pending_valid  (pending_valid),
        .scan_active    (scan_active),
        .frame_valid    (frame_valid),
        .pix_prefill_empty(pix_fifo_prog_empty),
        .pix_dout       (pix_fifo_dout),
        .pix_empty      (pix_fifo_empty),
        .pix_rd_en      (pix_fifo_rd_en),
        .frame_toggle   (renderer_frame_toggle),
        .hd_de          (hd_de),
        .hd_hsync       (hd_hsync),
        .hd_vsync       (hd_vsync),
        .hd_dout        (hd_dout)
    );
endmodule


//============================================================================
// PanoramaBase_HdDdrRenderer
//  BT.1120 1080p60 timing generator + centered 640x512 window scan-out.
//  frame_valid is the only control input; it is synchronized internally.
//============================================================================
module PanoramaBase_HdDdrRenderer(
    input  wire        rst_n,
    input  wire        rd_clk,
    input  wire        mode_enabled,
    input  wire        dbg_pulse_seen,
    input  wire        dbg_wpend_seen,
    input  wire        dbg_grant_seen,
    input  wire        dbg_copydone_seen,
    input  wire        dbg_scan_issue_seen,
    input  wire        dbg_rddata_seen,
    input  wire        dbg_pixwrite_seen,
    input  wire        copy_active,
    input  wire        pending_valid,
    input  wire        scan_active,
    input  wire        frame_valid,         // ui_clk-domain level (synced here)
    input  wire        pix_prefill_empty,   // pix_fifo prog_empty (rd_clk side)
    input  wire [15:0] pix_dout,
    input  wire        pix_empty,
    output reg         pix_rd_en,
    output reg         frame_toggle,
    output wire        hd_de,
    output wire        hd_hsync,
    output wire        hd_vsync,
    output wire [19:0] hd_dout
);
    localparam integer HD_ACTIVE_W = 1920;
    localparam integer HD_ACTIVE_H = 1080;
    localparam integer HD_TOTAL_W  = 2200;
    localparam integer HD_TOTAL_H  = 1125;
    localparam integer SAV_WORDS   = 4;
    localparam integer EAV_WORDS   = 4;
    localparam integer SRC_W       = 640;
    localparam integer SRC_H       = 512;
    localparam integer X_OFF       = (HD_ACTIVE_W - SRC_W) / 2;  // 640
    localparam integer Y_OFF       = (HD_ACTIVE_H - SRC_H) / 2;  // 284
    localparam [19:0]  BLACK       = {10'd64, 10'd512};          // Y=64, C=512

    reg [11:0] h_cnt;
    reg [10:0] v_cnt;
    reg        hd_de_r, hd_hsync_r, hd_vsync_r;
    reg [19:0] hd_dout_r;
    reg        stream_started;
    reg        frame_valid_meta, frame_valid_sync;
    reg [10:0] dbg_meta, dbg_sync;

    wire cur_vblank = (v_cnt >= HD_ACTIVE_H);
    wire cur_sav    = (h_cnt < SAV_WORDS);
    wire cur_active = (h_cnt >= SAV_WORDS) && (h_cnt < (SAV_WORDS + HD_ACTIVE_W)) && (v_cnt < HD_ACTIVE_H);
    wire cur_eav    = (h_cnt >= (SAV_WORDS + HD_ACTIVE_W)) && (h_cnt < (SAV_WORDS + HD_ACTIVE_W + EAV_WORDS));
    wire end_line   = (h_cnt == HD_TOTAL_W - 1);
    wire end_frame  = end_line && (v_cnt == HD_TOTAL_H - 1);
    wire [11:0] h_next = end_line ? 12'd0 : (h_cnt + 12'd1);
    wire [10:0] v_next = end_line ? (end_frame ? 11'd0 : (v_cnt + 11'd1)) : v_cnt;
    wire [1:0]  cur_eav_idx = h_cnt - (SAV_WORDS + HD_ACTIVE_W);
    wire [11:0] cur_x = h_cnt - SAV_WORDS;
    wire        cur_inside_window = cur_active &&
                                    (cur_x >= X_OFF) && (cur_x < (X_OFF + SRC_W)) &&
                                    (v_cnt >= Y_OFF) && (v_cnt < (Y_OFF + SRC_H));

    assign hd_de    = hd_de_r;
    assign hd_hsync = hd_hsync_r;
    assign hd_vsync = hd_vsync_r;
    assign hd_dout  = hd_dout_r;

    function [7:0] bt1120_xy;
        input f_bit; input v_bit; input h_bit;
        begin
            bt1120_xy = {1'b1, f_bit, v_bit, h_bit,
                         (f_bit ^ v_bit), (f_bit ^ h_bit),
                         (v_bit ^ h_bit), (f_bit ^ v_bit ^ h_bit)};
        end
    endfunction

    function [19:0] bt1120_trs_word;
        input [1:0] idx; input f_bit; input v_bit; input h_bit;
        reg [7:0] xy;
        begin
            xy = bt1120_xy(f_bit, v_bit, h_bit);
            case (idx)
                2'd0:    bt1120_trs_word = {10'h3FF, 10'h3FF};
                2'd1:    bt1120_trs_word = {10'h000, 10'h000};
                2'd2:    bt1120_trs_word = {10'h000, 10'h000};
                default: bt1120_trs_word = {{xy, 2'b00}, {xy, 2'b00}};
            endcase
        end
    endfunction

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            h_cnt <= 12'd0;
            v_cnt <= 11'd0;
            hd_de_r <= 1'b0;
            hd_hsync_r <= 1'b0;
            hd_vsync_r <= 1'b0;
            hd_dout_r <= BLACK;
            pix_rd_en <= 1'b0;
            frame_toggle <= 1'b0;
            stream_started <= 1'b0;
            frame_valid_meta <= 1'b0;
            frame_valid_sync <= 1'b0;
            dbg_meta <= 11'd0;
            dbg_sync <= 11'd0;
        end else begin
            pix_rd_en <= 1'b0;

            // CDC: ui_clk frame_valid -> rd_clk
            frame_valid_meta <= frame_valid;
            frame_valid_sync <= frame_valid_meta;
            dbg_meta <= {mode_enabled, dbg_pulse_seen, dbg_wpend_seen, dbg_grant_seen,
                         dbg_copydone_seen, dbg_scan_issue_seen, dbg_rddata_seen,
                         dbg_pixwrite_seen, copy_active, pending_valid, scan_active};
            dbg_sync <= dbg_meta;

            hd_de_r    <= cur_active;
            hd_hsync_r <= cur_active;
            hd_vsync_r <= ~cur_vblank;

            // Arm streaming once the prefill threshold is met (during pre-window
            // blanking) so EVERY in-window pixel consumes exactly one FIFO word.
            if (!stream_started && !pix_prefill_empty)
                stream_started <= 1'b1;

            if (end_frame) begin
                frame_toggle   <= ~frame_toggle;
                stream_started <= 1'b0;
            end

            if (cur_sav) begin
                hd_dout_r <= bt1120_trs_word(h_cnt[1:0], 1'b0, cur_vblank, 1'b0);
            end else if (cur_eav) begin
                hd_dout_r <= bt1120_trs_word(cur_eav_idx, 1'b0, cur_vblank, 1'b1);
            end else if (cur_inside_window && frame_valid_sync && stream_started && !pix_empty) begin
                // {Y[9:0], C[9:0]} : grayscale luma, neutral chroma (C byte = 0x80)
                hd_dout_r <= {{pix_dout[15:8], 2'b00}, {pix_dout[7:0], 2'b00}};
                pix_rd_en <= 1'b1;
            end else if (cur_inside_window && frame_valid_sync && !stream_started) begin
                // Orange: committed frame exists, but prefill threshold has not
                // yet been reached at the renderer.
                hd_dout_r <= {10'd900, 10'd700};
            end else if (cur_inside_window && frame_valid_sync && stream_started && pix_empty) begin
                // Underflow/readback diagnostics while a committed frame is
                // supposed to be streaming:
                // blue    = no DDR read ever issued
                // yellow  = reads issued, but no read data returned
                // magenta = read data returned, but no pixels were unpacked
                // green   = scan still active after pixels started flowing
                // red     = pixels did flow, but stream starved before window end
                if (!dbg_sync[5])
                    hd_dout_r <= {10'd128, 10'd896};
                else if (!dbg_sync[4])
                    hd_dout_r <= {10'd940, 10'd64};
                else if (!dbg_sync[3])
                    hd_dout_r <= {10'd700, 10'd700};
                else if (dbg_sync[0])
                    hd_dout_r <= {10'd128, 10'd256};
                else
                    hd_dout_r <= {10'd200, 10'd64};
            end else if (cur_inside_window && !frame_valid_sync) begin
                // Diagnostic palette while no committed frame is available:
                // dark blue   = mode not enabled
                // blue        = no frame pulse seen
                // red         = pulse seen, copy active, no packed burst
                // yellow      = packed burst seen, no DDR write grant yet
                // green       = DDR writes granted, copy active
                // magenta     = copy done, pending bank waiting for frame-edge commit
                // cyan        = copy done was seen historically, but no live frame_valid now
                // white       = fallback unexpected state
                if (!dbg_sync[10])
                    hd_dout_r <= {10'd64, 10'd64};
                else if (!dbg_sync[9])
                    hd_dout_r <= {10'd128, 10'd896};
                else if (dbg_sync[9] && !dbg_sync[8])
                    hd_dout_r <= {10'd200, 10'd64};
                else if (dbg_sync[8] && !dbg_sync[7])
                    hd_dout_r <= {10'd940, 10'd64};
                else if (dbg_sync[2] && dbg_sync[7] && !dbg_sync[1])
                    hd_dout_r <= {10'd128, 10'd256};
                else if (dbg_sync[1])
                    hd_dout_r <= {10'd700, 10'd700};
                else if (dbg_sync[6])
                    hd_dout_r <= {10'd128, 10'd896};
                else
                    hd_dout_r <= {10'd940, 10'd512};
            end else begin
                hd_dout_r <= BLACK;
            end

            h_cnt <= h_next;
            v_cnt <= v_next;
        end
    end
endmodule
