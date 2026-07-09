//============================================================================
// PanoramaBase_DdrBlackFrame  -  clean rewrite (2026-06-03)
//
// IR-single live video through a DDR4 ping-pong output framebuffer.
//
//   IR camera  --(cam pclk)-->  per-camera BRAM frame buffer
//        |                          | frame_pulse (in ui_clk domain)
//        v                          v
//   ui_clk COPY: BRAM -> DDR write-bank, then guarded 16-pixel DDR app beats.
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
    input  wire        eo0_wr_clk,
    input  wire        eo0_wr_hsync,
    input  wire        eo0_wr_vsync,
    input  wire [19:0] eo0_wr_pixel,
    input  wire        eo1_wr_clk,
    input  wire        eo1_wr_hsync,
    input  wire        eo1_wr_vsync,
    input  wire [19:0] eo1_wr_pixel,
    input  wire        eo2_wr_clk,
    input  wire        eo2_wr_hsync,
    input  wire        eo2_wr_vsync,
    input  wire [19:0] eo2_wr_pixel,
    input  wire        eo3_wr_clk,
    input  wire        eo3_wr_hsync,
    input  wire        eo3_wr_vsync,
    input  wire [19:0] eo3_wr_pixel,
    input  wire        eo4_wr_clk,
    input  wire        eo4_wr_hsync,
    input  wire        eo4_wr_vsync,
    input  wire [19:0] eo4_wr_pixel,
    input  wire        eo5_wr_clk,
    input  wire        eo5_wr_hsync,
    input  wire        eo5_wr_vsync,
    input  wire [19:0] eo5_wr_pixel,
    input  wire        c0_sys_clk_p,
    input  wire        c0_sys_clk_n,
    output wire [16:0] c0_ddr4_adr,
    output wire [1:0]  c0_ddr4_ba,
    output wire [0:0]  c0_ddr4_cke,
    output wire [0:0]  c0_ddr4_cs_n,
    inout  wire [5:0]  c0_ddr4_dm_dbi_n,
    inout  wire [47:0] c0_ddr4_dq,
    inout  wire [5:0]  c0_ddr4_dqs_c,
    inout  wire [5:0]  c0_ddr4_dqs_t,
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
    // DDR content source select (compile-time bring-up target for this
    // build).  SRC_RAMP is the Stage-A IR/ramp-over-DDR proof (640x512,
    // centered window).  SRC_EOSTK is the Stage-B EO 3x2 panorama composited
    // through DDR (1920x960, top-aligned with a black band below -- matches
    // the proven BRAM/URAM reference project's stack layout).  SRC_EO0
    // (2026-07-07, see docs/DDR_EO_PANORAMA_FIX_PLAN.md section 18.11) is a
    // diagnostic-only option: streams ONLY the cam0 640x480 decimated tile
    // through DDR with NO compositor/tile-select mux at all.  SRC_EO0RAW
    // (2026-07-07, section 18.14) goes one step further: cam0 at full
    // native 1920x1080, with NO decimation either (SRC_EO0 still ran every
    // pixel through the crop/subsample logic each real tile uses -- this
    // option removes that too, so the only thing between the camera and
    // the DDR round trip is the unavoidable wr_clk->rd_clk CDC). Flip this
    // one localparam and rebuild to change source; everything downstream
    // (geometry, renderer window, copy engine) follows automatically.
    //------------------------------------------------------------------------
    localparam [1:0] SRC_RAMP   = 2'd0;
    localparam [1:0] SRC_EOSTK  = 2'd1;
    localparam [1:0] SRC_EO0    = 2'd2;
    localparam [1:0] SRC_EO0RAW = 2'd3;
    localparam [1:0] SRC_SEL    = SRC_EOSTK;

    //------------------------------------------------------------------------
    // Geometry / DDR layout
    //------------------------------------------------------------------------
    localparam integer RAMP_SRC_W    = 640,  RAMP_SRC_H    = 512;
    localparam integer EOSTK_SRC_W   = 1920, EOSTK_SRC_H   = 960;
    localparam integer EO0_SRC_W     = 640,  EO0_SRC_H     = 480;
    localparam integer EO0RAW_SRC_W  = 1920, EO0RAW_SRC_H  = 1080;
    localparam integer SRC_W = (SRC_SEL == SRC_EOSTK)  ? EOSTK_SRC_W  :
                               (SRC_SEL == SRC_EO0)    ? EO0_SRC_W    :
                               (SRC_SEL == SRC_EO0RAW) ? EO0RAW_SRC_W : RAMP_SRC_W;
    localparam integer SRC_H = (SRC_SEL == SRC_EOSTK)  ? EOSTK_SRC_H  :
                               (SRC_SEL == SRC_EO0)    ? EO0_SRC_H    :
                               (SRC_SEL == SRC_EO0RAW) ? EO0RAW_SRC_H : RAMP_SRC_H;

    // RAMP/IR window and the EO0-only diagnostic window are both centered in
    // the 1920x1080 active area; the EO panorama and the full-native-res
    // EO0RAW diagnostic both fill the entire active area (EO0RAW exactly
    // fills it at 1920x1080, so its offset is (0,0) same as the stack).
    localparam integer RAMP_X_OFF  = (1920 - RAMP_SRC_W) / 2;   // 640
    localparam integer RAMP_Y_OFF  = (1080 - RAMP_SRC_H) / 2;   // 284
    localparam integer EOSTK_X_OFF = 0;
    localparam integer EOSTK_Y_OFF = 0;
    localparam integer EO0_X_OFF   = (1920 - EO0_SRC_W) / 2;    // 640
    localparam integer EO0_Y_OFF   = (1080 - EO0_SRC_H) / 2;    // 300
    localparam integer EO0RAW_X_OFF = 0;
    localparam integer EO0RAW_Y_OFF = 0;
    localparam integer WIN_X_OFF = (SRC_SEL == SRC_EOSTK)  ? EOSTK_X_OFF  :
                                   (SRC_SEL == SRC_EO0)    ? EO0_X_OFF    :
                                   (SRC_SEL == SRC_EO0RAW) ? EO0RAW_X_OFF : RAMP_X_OFF;
    localparam integer WIN_Y_OFF = (SRC_SEL == SRC_EOSTK)  ? EOSTK_Y_OFF  :
                                   (SRC_SEL == SRC_EO0)    ? EO0_Y_OFF    :
                                   (SRC_SEL == SRC_EO0RAW) ? EO0RAW_Y_OFF : RAMP_Y_OFF;

    localparam integer DDR_APP_DATA_W  = 384;              // x48 DDR4 UI: 48 DQ * BL8
    localparam integer DDR_APP_MASK_W  = DDR_APP_DATA_W / 8;
    // Hardware captures show that one complete x16 component contribution
    // (128 bits per BL8) is corrupt: 8/32 pixels at x64 and the same 8/24
    // pixels at x48. In the x48 lane map, the logical top 128 app-data bits
    // still use original physical byte lanes 6/7, locating the fault on that
    // x16 device/interface. Keep all source pixels in the clean low 256 bits
    // and leave app_data[383:256] unused.
    // This is lossless; no image data is stored in the failing component.
    localparam integer DDR_GUARD_OFFSET_BITS = 0;
    localparam integer DDR_PAYLOAD_BITS      = 256;
    localparam integer PIXELS_PER_BEAT       = DDR_PAYLOAD_BITS / 16;
    localparam [5:0]   PIXELS_PER_BEAT_COUNT = PIXELS_PER_BEAT;
    localparam [5:0]   PIXELS_PER_BEAT_LAST  = PIXELS_PER_BEAT - 1;
    localparam [20:0]  FRAME_PIXELS  = SRC_W * SRC_H;      // 1,843,200 (EO) / 327,680 (ramp) / 2,073,600 (EO0RAW)
    localparam [16:0]  BEATS_TOTAL   = FRAME_PIXELS / PIXELS_PER_BEAT; // 115,200 (EO) / 20,480 (ramp) / 19,200 (EO0) / 129,600 (EO0RAW)
    localparam [28:0]  ADDR_STRIDE   = 29'd8;              // app_addr units per BL8 beat
    localparam [28:0]  BANK0_BASE    = 29'd0;
    localparam [28:0]  BANK1_BASE    = BEATS_TOTAL * ADDR_STRIDE; // 921,600 (EO) / 163,840 (ramp) / 153,600 (EO0) / 1,036,800 (EO0RAW)
    // 2026-07-07: tried temporarily dropping this to 4 (see
    // docs/DDR_EO_PANORAMA_FIX_PLAN.md section 17) to test whether the
    // ILA-confirmed first-64-bit-chunk-of-every-read-burst corruption was
    // caused by deep MIG-internal read pipelining. Stratifying the ILA
    // capture by actual outstanding depth at return showed 100% corruption
    // at EVERY depth from 1 to 16 in both the depth<=16 and depth<=4
    // builds, including depth=1 (a single isolated read, zero pipelining
    // overlap) -- conclusively ruling out pipelining depth as a factor.
    // Reverted to 16 (no benefit at 4, and 16 is better for throughput).
    localparam [6:0]   MAX_OUTSTANDING = 7'd16;
    // VT-tracking keepalive-read threshold (docs/DDR_READ_CADENCE_VT_TRACKING_FIX_PLAN.md).
    // First hardware pass at 150 cycles (~643ns) cut the worst-case gap from
    // 6344.6ns to 1023.9ns (10 captures) -- a huge improvement, but one
    // capture landed just over the 1us limit. Root cause (confirmed via the
    // new keepalive_want/cmd_pend/read_gap_counter ILA probes): the
    // keepalive command launched promptly at the threshold, but then sat in
    // cmd_pend for ~87 extra ui_clk cycles (~372ns) waiting on
    // c0_ddr4_app_rdy -- almost certainly the MIG servicing a periodic DDR4
    // refresh (tRFC), which blocks the native interface regardless of what
    // this RTL requests. Lowered to 60 cycles (~257ns) so that even a full
    // repeat of that ~90-cycle stall (60+90=150 cycles=~643ns) still lands
    // comfortably under the 233-cycle/1000ns PG150 limit, rather than
    // chasing the exact refresh timing.
    localparam [9:0]   KEEPALIVE_THRESHOLD = 10'd60;
    localparam [15:0]  BLACK_PIXEL   = 16'h1080;     // Y=0x10, C=0x80 (neutral)
    localparam [DDR_APP_DATA_W-1:0] BLACK_BURST =
        {128'd0, {PIXELS_PER_BEAT{BLACK_PIXEL}}};

    // DIAGNOSTIC BISECTION (SRC_SEL==SRC_RAMP builds only): when 1, the copy
    // writes a known raster ramp (luma = pixel_index[7:0]) into DDR instead of
    // the captured camera pixel.  Everything else (copy write, DDR store,
    // scan, unpack, render) runs exactly as in the live path.  Clean diagonal
    // ramp on screen  => the whole DDR pipeline is correct and the live fault
    // is the BRAM/camera data.  Garbled or green/underflow => the fault is in
    // the write/DDR/scan/render path.  Set to 0 for live IR.  When 1, the copy
    // is also self-triggered every display frame (camera-independent) so the
    // DDR write/scan/render path is exercised with a known ramp regardless of
    // which IR camera is connected.
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
    wire         c0_ddr4_app_en;
    wire         c0_ddr4_app_hi_pri;
    wire         c0_ddr4_app_wdf_end;
    wire         c0_ddr4_app_wdf_wren;
    wire         c0_ddr4_app_rd_data_end;
    wire         c0_ddr4_app_rd_data_valid;
    wire         c0_ddr4_app_rdy;
    wire         c0_ddr4_app_wdf_rdy;
    wire [28:0]  c0_ddr4_app_addr;
    wire [2:0]   c0_ddr4_app_cmd;
    wire [DDR_APP_DATA_W-1:0] c0_ddr4_app_wdf_data;
    wire [DDR_APP_MASK_W-1:0] c0_ddr4_app_wdf_mask;
    wire [DDR_APP_DATA_W-1:0] c0_ddr4_app_rd_data;

    assign init_calib_complete_o = c0_init_calib_complete;

    //------------------------------------------------------------------------
    // MIG native-interface command/data launch registers.  PG150 requires the
    // enable/command (and, independently, the write-data strobes) to be HELD
    // until the matching *_rdy is seen high in the same cycle -- a one-cycle
    // pulse qualified only by the *previous* cycle's rdy (the old design) can
    // be silently dropped whenever rdy deasserts (refresh/ZQ/queue pressure),
    // permanently leaking the outstanding-read counter (stuck scan, solid
    // green) or misaligning the write command/data pairing (corrupted DDR
    // contents, noise).  These regs are combinationally exposed on the app_*
    // ports and only cleared once the MIG actually accepts them.
    //------------------------------------------------------------------------
    reg          cmd_pend;
    reg          cmd_is_rd;
    reg          cmd_is_keepalive; // 1 = this command is a VT-tracking dummy
                                    // read (see docs/DDR_READ_CADENCE_VT_TRACKING_FIX_PLAN.md),
                                    // not real scan data
    reg  [28:0]  cmd_addr_q;
    reg          wdf_pend;
    reg  [DDR_APP_DATA_W-1:0] wdf_data_q;
    reg          w_cmd_done;   // write command phase already accepted (sticky, write ops only)
    reg          w_wdf_done;   // write data phase already accepted (sticky, write ops only)

    wire write_cmd_pending = cmd_pend && !cmd_is_rd;
    wire app_en_held       = cmd_pend &&
                             (cmd_is_rd || !wdf_pend || w_wdf_done || c0_ddr4_app_wdf_rdy);
    wire app_wdf_wren_held = wdf_pend &&
                             (!write_cmd_pending || w_cmd_done || c0_ddr4_app_rdy);

    assign c0_ddr4_app_en       = app_en_held;
    assign c0_ddr4_app_hi_pri   = 1'b0;
    assign c0_ddr4_app_cmd      = cmd_is_rd ? 3'b001 : 3'b000;
    assign c0_ddr4_app_addr     = cmd_addr_q;
    assign c0_ddr4_app_wdf_wren = app_wdf_wren_held;
    assign c0_ddr4_app_wdf_end  = app_wdf_wren_held;
    assign c0_ddr4_app_wdf_data = wdf_pend ? wdf_data_q : BLACK_BURST;
    assign c0_ddr4_app_wdf_mask = {DDR_APP_MASK_W{1'b0}};

    wire cmd_fire    = app_en_held && c0_ddr4_app_rdy;
    wire wdf_fire    = app_wdf_wren_held && c0_ddr4_app_wdf_rdy;
    wire issue_busy  = cmd_pend || wdf_pend;
    wire read_retiring  = cmd_pend && cmd_is_rd && cmd_fire;
    wire write_retiring = issue_busy && !cmd_is_rd &&
                          (w_cmd_done || cmd_fire) && (w_wdf_done || wdf_fire);

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
    wire        pix_fifo_overflow;
    wire        pix_fifo_underflow;

    // USE_ADV_FEATURES bit map (xpm_fifo.sv): bit0=overflow, bit1=prog_full,
    // bit8=underflow, bit9=prog_empty -> "0303" enables exactly those four.
    // The previous "0004" enabled only wr_data_count (an unconnected port),
    // which left prog_full/prog_empty hard-wired to constant 0/1 and disabled
    // all flow control on both FIFOs below.
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
        .USE_ADV_FEATURES    ("0303"),
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
        .overflow      (pix_fifo_overflow),
        .rd_en         (pix_fifo_rd_en),
        .dout          (pix_fifo_dout),
        .empty         (pix_fifo_empty),
        .prog_empty    (pix_fifo_prog_empty),
        .underflow     (pix_fifo_underflow),
        .wr_rst_busy   (pix_fifo_wr_rst_busy),
        .rd_rst_busy   (pix_fifo_rd_rst_busy),
        .sleep         (1'b0),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0)
    );

    // Read-data/write-enable alignment fix (plan section 20): beat_fifo_wr_en
    // is a registered pulse, only visible the cycle AFTER
    // c0_ddr4_app_rd_data_valid was actually sampled true -- but beat_fifo's
    // din was wired straight to the live c0_ddr4_app_rd_data bus with no
    // latching, so the FIFO was capturing whatever the MIG happened to be
    // driving one cycle LATER, not the word that was actually valid. Latch
    // the data on the SAME cycle as the valid check, in lockstep with
    // beat_fifo_wr_en, so both become visible together one cycle later.
    reg [DDR_APP_DATA_W-1:0] rd_data_capture;

    wire         beat_fifo_prog_full;
    wire         beat_fifo_empty;
    wire [DDR_APP_DATA_W-1:0] beat_fifo_dout;
    reg          beat_fifo_wr_en;
    reg          beat_fifo_rd_en;
    wire         beat_fifo_full;
    wire         beat_fifo_overflow;
    wire         beat_fifo_underflow;

    xpm_fifo_sync #(
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("block"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (128),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (8),
        .PROG_FULL_THRESH    (64),
        .RD_DATA_COUNT_WIDTH (7),
        .READ_DATA_WIDTH     (DDR_APP_DATA_W),
        .READ_MODE           ("fwft"),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0303"),
        .WAKEUP_TIME         (0),
        .WR_DATA_COUNT_WIDTH (7),
        .WRITE_DATA_WIDTH    (DDR_APP_DATA_W)
    ) u_beat_fifo (
        .rst           (ui_rst),
        .wr_clk        (c0_ddr4_ui_clk),
        .din           (rd_data_capture),
        .wr_en         (beat_fifo_wr_en),
        .full          (beat_fifo_full),
        .prog_full     (beat_fifo_prog_full),
        .overflow      (beat_fifo_overflow),
        .rd_en         (beat_fifo_rd_en),
        .dout          (beat_fifo_dout),
        .empty         (beat_fifo_empty),
        .underflow     (beat_fifo_underflow),
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
    // Copy / scan / arbiter state (ui_clk).  Declared here, BEFORE the
    // SRC_SEL generate block below, because Vivado's synthesis elaborator
    // (unlike the simulator) binds an assign/reference inside a generate
    // block to an implicit LOCAL net if the real module-scope declaration
    // appears later in the file, rather than forward-referencing it -- so
    // copy_active/fb_write_pending/copy_px_valid/copy_px_data/eo_frames_valid
    // must all be declared before g_src_eostk/g_src_ramp use them.
    //------------------------------------------------------------------------
    reg        running;            // calibration complete, pipeline live
    reg        dbg_pulse_seen;
    reg        dbg_wpend_seen;
    reg        dbg_grant_seen;
    reg        dbg_copydone_seen;
    reg        dbg_scan_issue_seen;
    reg        dbg_rddata_seen;
    reg        dbg_pixwrite_seen;
    reg        dbg_beat_overflow;     // sticky: beat_fifo overflowed (should never happen post-fix)
    // Sticky: MIG rdy was low on a launch cycle (proves the hold-FSM actually
    // waited at least once). Has no logic consumer by design -- it exists for
    // hardware bring-up ILA probing only, so mark_debug/dont_touch keep
    // synthesis from trimming it as dead logic.
    (* mark_debug = "true", dont_touch = "true" *)
    reg        dbg_cmd_retry_seen;

    // BRAM -> pack -> DDR write (copy).  fb_rd_en_d1/d2/fb_rd_busy live inside
    // the g_src_ramp generate branch below (ramp-source-only implementation
    // detail); copy_active/fb_write_pending/fb_pack_* are source-agnostic.
    reg        copy_active;
    reg        fb_write_pending;
    reg [5:0]  fb_pack_count;
    reg [16:0] fb_burst_count;
    reg [DDR_APP_DATA_W-1:0] fb_pack_buf;
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

    // VT-tracking keepalive-read mechanism v2 (docs/DDR_READ_CADENCE_VT_TRACKING_FIX_PLAN.md,
    // revert-and-redo of the plan section 22.4 v1 attempt). Counts ui_clk
    // cycles since the last ACCEPTED read command (real scan or dummy
    // keepalive -- read_retiring covers both). Saturates instead of
    // wrapping so the KEEPALIVE_THRESHOLD comparison stays stable
    // indefinitely if arbitration contention ever delays a keepalive
    // launch past the raw threshold value.
    reg  [9:0] read_gap_counter;

    // Explicit register-ring read-return tag queue. v2 deliberately does
    // NOT reuse an XPM FWFT FIFO here: the v1 attempt popped an XPM tag
    // FIFO directly on c0_ddr4_app_rd_data_valid and is the leading
    // suspect for the blank-screen regression it caused (a FWFT dout
    // timing mismatch could silently misclassify real scan completions as
    // keepalive-discard). One bit per accepted read command (0=real scan,
    // 1=keepalive dummy), pushed on read_retiring, classified+popped on
    // c0_ddr4_app_rd_data_valid -- the native interface returns
    // completions strictly in issue order, so a plain in-order ring
    // buffer is an exact match, no reordering to account for. Depth 32
    // gives 2x margin over MAX_OUTSTANDING so it can never overflow in
    // normal operation; rd_tag_overflow/underflow are sticky hardware
    // bring-up alarms, not expected to ever fire.
    localparam integer RD_TAG_DEPTH  = 32;
    localparam integer RD_TAG_AWIDTH = 5;   // log2(RD_TAG_DEPTH)
    reg                     rd_tag_mem [0:RD_TAG_DEPTH-1];
    reg [RD_TAG_AWIDTH-1:0] rd_tag_head;
    reg [RD_TAG_AWIDTH-1:0] rd_tag_tail;
    reg [RD_TAG_AWIDTH:0]   rd_tag_count;   // 0..32, one extra bit vs the index width
    reg                     rd_tag_overflow;
    reg                     rd_tag_underflow;
    // Classification of the return CURRENTLY completing (valid the same
    // cycle as c0_ddr4_app_rd_data_valid, read from the queue tail BEFORE
    // it advances this same cycle -- ordinary synchronous-FIFO
    // read-before-pop semantics, not FWFT).
    wire rd_return_is_keepalive = rd_tag_mem[rd_tag_tail];

    // frame-boundary flush/resync: see flush_active state machine below
    reg        flush_active;
    reg        flush_commit_pending;

    // beat_fifo -> pix_fifo unpack
    reg [DDR_APP_DATA_W-1:0] unpack_shift;
    reg [5:0]   unpack_count;

    // renderer frame-boundary pulse, synchronized into ui_clk
    reg        ftog_meta, ftog_sync, ftog_sync_d;

    wire [28:0] wr_bank_base = wr_bank ? BANK1_BASE : BANK0_BASE;
    wire [28:0] rd_bank_base = rd_bank ? BANK1_BASE : BANK0_BASE;

    wire frame_edge = (ftog_sync != ftog_sync_d);

    //------------------------------------------------------------------------
    // Camera (eo0)'s own frame boundary, synchronized into ui_clk.  Used only
    // by SRC_EO0RAW's pure-streaming copy trigger (see g_src_eo0raw below):
    // unlike frame_edge (display-triggered, valid because an on-chip
    // full-frame buffer already holds committed data for g_src_eostk/
    // g_src_eo0), a streaming source has no complete on-chip frame to fall
    // back on, so its copy pass must start exactly when the camera itself
    // begins a new frame, or the pass would start mid-frame.  Declared here
    // (module scope, unconditional) rather than inside the generate branch
    // because copy_start_trig below references it directly -- see the
    // forward-reference note above copy_active for why that matters to
    // Vivado's elaborator.
    //------------------------------------------------------------------------
    reg eo0_vsync_d_wr, eo0_ftog_wr;
    always @(posedge eo0_wr_clk) begin
        if (!rst_n) begin
            eo0_vsync_d_wr <= 1'b0;
            eo0_ftog_wr    <= 1'b0;
        end else begin
            eo0_vsync_d_wr <= eo0_wr_vsync;
            if (eo0_vsync_d_wr && ~eo0_wr_vsync)  // falling edge = frame start
                eo0_ftog_wr <= ~eo0_ftog_wr;
        end
    end

    reg eo0_ftog_meta, eo0_ftog_sync, eo0_ftog_sync_d;
    always @(posedge c0_ddr4_ui_clk) begin
        if (ui_rst) begin
            eo0_ftog_meta   <= 1'b0;
            eo0_ftog_sync   <= 1'b0;
            eo0_ftog_sync_d <= 1'b0;
        end else begin
            eo0_ftog_meta   <= eo0_ftog_wr;
            eo0_ftog_sync   <= eo0_ftog_meta;
            eo0_ftog_sync_d <= eo0_ftog_sync;
        end
    end
    wire eo0_frame_edge_ui = (eo0_ftog_sync != eo0_ftog_sync_d);

    //------------------------------------------------------------------------
    // Shared interface between the SRC_SEL-selected copy-side pixel producer
    // (g_src_eostk / g_src_ramp generate branches below) and the
    // source-agnostic pack/write-launch back-end.
    //------------------------------------------------------------------------
    wire        copy_px_valid;    // pulses once per pixel ready to pack
    wire [15:0] copy_px_data;     // packed {hi8,lo8} value, valid when copy_px_valid
    wire        eo_frames_valid;  // all six EO tile buffers have captured >=1 frame

    // Qualifies "begin a new copy": free-running on the display frame edge for
    // the buffered EO panorama and cam0-only diagnostic sources (the tiles
    // are always-fresh rolling captures and the ping-pong bank isolates
    // tearing at the DDR level) once real camera data exists; the pure
    // streaming cam0-raw source instead free-runs on the camera's OWN frame
    // edge (see eo0_frame_edge_ui above); unchanged PATTERN_TEST-or-live-IR-
    // pulse trigger for the ramp.
    wire copy_start_trig = (SRC_SEL == SRC_EO0RAW)
        ? (eo0_frame_edge_ui && eo_frames_valid)
        : (SRC_SEL == SRC_EOSTK || SRC_SEL == SRC_EO0)
        ? (frame_edge && eo_frames_valid)
        : ((PATTERN_TEST && frame_edge) || (!PATTERN_TEST && sel_pulse && ir_single_ui));

    // Scan wants to issue a read this cycle (rdy handshake handled by the
    // held-launch FSM below, not sampled here).
    wire scan_want = running && scan_active &&
                     !beat_fifo_prog_full &&
                     !pix_fifo_wr_rst_busy && (outstanding < MAX_OUTSTANDING);
    // Copy wants to issue a write this cycle.
    wire write_want = running && copy_active && fb_write_pending;

    // VT-tracking keepalive dummy-read address: read from the bank NOT
    // currently being written, so it never races the in-flight write
    // engine. The data is always discarded downstream (rd_return_is_keepalive
    // gates beat_fifo_wr_en below), so which specific address within that
    // bank is read does not matter -- only that it is a valid,
    // already-initialized DDR address.
    wire [28:0] keepalive_addr = wr_bank ? BANK0_BASE : BANK1_BASE;

    // keepalive_want: desire to issue a dummy read to keep the DQS gate's
    // VT tracking active during write-heavy stretches where scan_want
    // would otherwise be false for a long time (plan section 22.3's
    // confirmed 6.3x-over-spec read-gap violation). Explicitly excludes
    // flush_active -- the v1 attempt's leading suspected root cause of the
    // blank-screen regression: a dummy read outstanding during flush could
    // keep the flush-completion check (outstanding==0) from ever becoming
    // true, stalling the frame-boundary commit indefinitely.
    wire keepalive_want = running && !flush_active && !scan_want &&
                          (read_gap_counter >= KEEPALIVE_THRESHOLD) &&
                          (outstanding < MAX_OUTSTANDING) &&
                          (rd_tag_count < RD_TAG_DEPTH);

    // keepalive_launch: the actual cycle a keepalive read is selected by
    // the arbiter (below) and loaded into the held-command register --
    // distinct from keepalive_want, which can stay asserted across
    // multiple cycles while a write command is being held/accepted.
    wire keepalive_launch = !issue_busy && !scan_want && keepalive_want;

    //------------------------------------------------------------------------
    // Copy-side pixel source (SRC_SEL-selected, compile-time).  Produces
    // copy_px_valid/copy_px_data for the source-agnostic pack/write engine
    // further below.  Only one of these two branches is ever elaborated.
    //------------------------------------------------------------------------
    generate
    if (SRC_SEL == SRC_EOSTK) begin : g_src_eostk
        //--------------------------------------------------------------------
        // EO 3x2 panorama: six cameras, each decimated/cropped to a 640x480
        // tile by the proven EO1920x1080_Decimate3_FrameBuffer (verbatim
        // from the BRAM/URAM reference project, EOStackModules.v). The
        // compositor below walks the composed 1920x960 canvas in raster
        // order, pulling one pixel per cycle from whichever tile the current
        // (x,y) falls into.
        //
        // CLOCKING (2026-07-07 retiming -- see docs/DDR_EO_PANORAMA_FIX_PLAN.md
        // section 10 for the full measurement history): the walk and all six
        // tile buffers run on rd_clk (74.25MHz, same as the donor project),
        // NOT c0_ddr4_ui_clk (300MHz) as an earlier version had them. Root
        // cause of that earlier version's unclosed timing: each tile is a
        // ~142-block BRAM cascade (or 75-block URAM), and at this die's
        // resulting BRAM occupancy, placement could not keep a cascade's
        // blocks close enough together for their shared address/enable
        // broadcast to route within one 3.332ns cycle -- confirmed because
        // every failing endpoint lived in the mmcm_clkout0 clock group while
        // every other domain had >+5ns slack, and because the donor project
        // runs the IDENTICAL 142-RAMB36 tile shape at HIGHER chip-wide BRAM
        // utilization and closes with +0.433ns to spare, entirely because it
        // clocks those memories at 10ns instead of 3.332ns. The 300MHz domain
        // never needed random access into the tiles -- only the composed
        // pixel STREAM (55.3 Mpx/s average; a 1-px/cycle rd_clk walk yields
        // 74.25 Mpx/s and finishes a full 1,843,200-px frame in 24.8ms,
        // inside the 33.3ms/30Hz BT.1120 cadence) -- so the walk/tiles now
        // hand pixels to the ui_clk pack engine through one small async FIFO
        // instead of being clocked by ui_clk directly.
        //--------------------------------------------------------------------
        wire [19:0] eo0_rd_pixel, eo1_rd_pixel, eo2_rd_pixel, eo3_rd_pixel, eo4_rd_pixel, eo5_rd_pixel;
        wire        eo0_frame_valid, eo1_frame_valid, eo2_frame_valid;
        wire        eo3_frame_valid, eo4_frame_valid, eo5_frame_valid;
        wire        eo_frames_valid_rd = eo0_frame_valid && eo1_frame_valid && eo2_frame_valid &&
                                          eo3_frame_valid && eo4_frame_valid && eo5_frame_valid;

        // copy_active (ui_clk) -> rd_clk: slow, monotonic-per-copy level,
        // plain 2-FF sync is correct (same convention the renderer already
        // uses for frame_valid elsewhere in this file).
        reg copy_active_meta, copy_active_rd;
        always @(posedge rd_clk) begin
            if (!rst_n) begin
                copy_active_meta <= 1'b0;
                copy_active_rd   <= 1'b0;
            end else begin
                copy_active_meta <= copy_active;
                copy_active_rd   <= copy_active_meta;
            end
        end

        // eo_frames_valid (rd_clk, only ever rises once and stays high -- see
        // EO1920x1080_Decimate3_FrameBuffer) -> ui_clk, same 2-FF convention.
        reg eo_frames_valid_meta, eo_frames_valid_ui;
        always @(posedge c0_ddr4_ui_clk) begin
            if (ui_rst) begin
                eo_frames_valid_meta <= 1'b0;
                eo_frames_valid_ui   <= 1'b0;
            end else begin
                eo_frames_valid_meta <= eo_frames_valid_rd;
                eo_frames_valid_ui   <= eo_frames_valid_meta;
            end
        end
        assign eo_frames_valid = eo_frames_valid_ui;

        // Copy-stream CDC FIFO wires (instance further below, after the walk
        // state it's read alongside); declared here so copy_issue's
        // reference to copyfifo_prog_full has an in-scope declaration above
        // it textually.
        wire        copyfifo_full, copyfifo_empty, copyfifo_prog_full;
        wire        copyfifo_overflow, copyfifo_underflow;
        wire [15:0] copyfifo_dout;
        wire        copyfifo_rd_en;

        //--------------------------------------------------------------------
        // Raster walk state (rd_clk domain), increment-only counters -- NOT
        // a multiply. An earlier version computed the tile address as
        // "tile_y * 640 + tile_x" combinationally every cycle; that
        // synthesized to a DSP48 multiplier whose output fanned out,
        // unregistered, into the address/enable ports of all six tile
        // memories -- fine at 74.25MHz, measured far too slow for 300MHz.
        // row_base is updated only once per display row (960 times per
        // frame, both giving it ample slack and, since it changes by a fixed
        // +640 each time, needing only a plain adder); col_in_tile and
        // row_in_tile only ever increment or reset -- also plain adders.
        //--------------------------------------------------------------------
        reg  [9:0]  col_in_tile;     // 0..639: X position within the current tile
        reg  [1:0]  col_group;       // 0,1,2: which horizontal tile
        reg  [8:0]  row_in_tile;     // 0..479: Y position within the current tile row-group
        reg         row_group;       // 0,1: which vertical tile-group
        reg  [18:0] row_base;        // row_in_tile*640, maintained by +640 accumulation
        reg         copy_walk_done;  // this copy has issued all FRAME_PIXELS reads

        wire        copy_issue     = copy_active_rd && !copy_walk_done && !copyfifo_prog_full;
        wire [18:0] copy_tile_addr = row_base + {9'd0, col_in_tile};   // plain 19-bit adder

        wire eo0_rd_en = copy_issue && !row_group && (col_group == 2'd0);
        wire eo1_rd_en = copy_issue && !row_group && (col_group == 2'd1);
        wire eo2_rd_en = copy_issue && !row_group && (col_group == 2'd2);
        wire eo3_rd_en = copy_issue &&  row_group && (col_group == 2'd0);
        wire eo4_rd_en = copy_issue &&  row_group && (col_group == 2'd1);
        wire eo5_rd_en = copy_issue &&  row_group && (col_group == 2'd2);

        wire col_last    = (col_in_tile == 10'd639);
        wire colgrp_last = (col_group == 2'd2);
        wire row_last    = (row_in_tile == 9'd479);

        // Read latency reverted to the donor's proven default: the tile
        // memories are back on the 10ns rd_clk domain, where 2 cycles is
        // ample (routed reports at 300MHz measured the worst URAM-cascade
        // read path at ~5.6ns total -- comfortably inside 10ns). Vivado's
        // memory compiler may still print an advisory ("UltraRAM ...
        // under-pipelined ... recommended 7 stages") -- that recommendation
        // targets a 3.332ns clock; it does not apply to this 10ns domain and
        // is expected/harmless.
        localparam integer EO_READ_LATENCY = 2;

        // Exactly one tile fits URAM at native 16-bit width (128 URAM288
        // total / 75 needed per tile -- KU15P cannot fit a second); the
        // other five explicitly use "block" (BRAM, matching the donor
        // project's own default primitive) -- a deterministic split rather
        // than Vivado's per-instance fallback heuristic, which over-
        // subscribed URAM (6x75=450>128) when given extra pipeline headroom.
        //
        // u_eo_fb0 uses the donor's own cam0 "same clock" exception
        // (USE_ASYNC_FIFO(0)/common_clock, direct combinational write path,
        // no CDC): with the tile read clock on rd_clk, eo0's write clock
        // (eo0_wr_clk = eo0_pclk) and rd_clk really are the same clock --
        // an independent-clock async FIFO between them trips a bitgen DRC
        // (the donor project's own README documents hitting exactly this).
        //
        // CORRECTION 2026-07-07 (see docs/DDR_EO_PANORAMA_FIX_PLAN.md
        // section 18.3/18.6): a source-level reading of eo0_pclk's origin
        // (the cam0 receiver's `wire CAM0_PCLK_bufg = CAM0_PCLK;` in
        // Kintex_top_0cam_ch1_0108.v, i.e. no explicit BUFG, vs. rd_clk
        // being the top-level's own `BUFG u_cam0_pclk_bufg` copy of the
        // same pin) looked like two distinct clock-tree nets with an
        // uncharacterized skew, and this exception was briefly REMOVED
        // (switched to USE_ASYNC_FIFO(1) like tiles 1-5) on that theory.
        // That was WRONG: implementation immediately hit `DRC AVAL-245
        // Independent_clock_check` on this exact RAM, stating outright
        // that "the two clock pins... are driven by the same driver" --
        // i.e. Vivado's actual synthesized/placed netlist merges these
        // nets (almost certainly clock-network optimization recognizing
        // eo0_pclk and rd_clk as electrically equivalent once traced
        // through, regardless of the RTL-level BUFG-vs-no-BUFG structural
        // difference). Trust the DRC over source-level net-tracing by eye
        // for clock-identity questions -- reverted to the original,
        // correct form.
        EO1920x1080_Decimate3_FrameBuffer #(
            .MEMORY_PRIMITIVE_STR("ultra"), .READ_LATENCY(EO_READ_LATENCY),
            .CLOCKING_MODE_STR("common_clock"), .FIFO_RELATED_CLOCKS(1), .USE_ASYNC_FIFO(0)
        ) u_eo_fb0 (
            .rst_n(rst_n), .wr_clk(eo0_wr_clk), .wr_hsync(eo0_wr_hsync), .wr_vsync(eo0_wr_vsync), .wr_pixel(eo0_wr_pixel),
            .rd_clk(rd_clk), .rd_frame_start(1'b0), .rd_en(eo0_rd_en), .rd_addr(copy_tile_addr),
            .rd_pixel(eo0_rd_pixel), .frame_valid(eo0_frame_valid));
        EO1920x1080_Decimate3_FrameBuffer #(.MEMORY_PRIMITIVE_STR("block"), .READ_LATENCY(EO_READ_LATENCY)) u_eo_fb1 (
            .rst_n(rst_n), .wr_clk(eo1_wr_clk), .wr_hsync(eo1_wr_hsync), .wr_vsync(eo1_wr_vsync), .wr_pixel(eo1_wr_pixel),
            .rd_clk(rd_clk), .rd_frame_start(1'b0), .rd_en(eo1_rd_en), .rd_addr(copy_tile_addr),
            .rd_pixel(eo1_rd_pixel), .frame_valid(eo1_frame_valid));
        EO1920x1080_Decimate3_FrameBuffer #(.MEMORY_PRIMITIVE_STR("block"), .READ_LATENCY(EO_READ_LATENCY)) u_eo_fb2 (
            .rst_n(rst_n), .wr_clk(eo2_wr_clk), .wr_hsync(eo2_wr_hsync), .wr_vsync(eo2_wr_vsync), .wr_pixel(eo2_wr_pixel),
            .rd_clk(rd_clk), .rd_frame_start(1'b0), .rd_en(eo2_rd_en), .rd_addr(copy_tile_addr),
            .rd_pixel(eo2_rd_pixel), .frame_valid(eo2_frame_valid));
        EO1920x1080_Decimate3_FrameBuffer #(.MEMORY_PRIMITIVE_STR("block"), .READ_LATENCY(EO_READ_LATENCY)) u_eo_fb3 (
            .rst_n(rst_n), .wr_clk(eo3_wr_clk), .wr_hsync(eo3_wr_hsync), .wr_vsync(eo3_wr_vsync), .wr_pixel(eo3_wr_pixel),
            .rd_clk(rd_clk), .rd_frame_start(1'b0), .rd_en(eo3_rd_en), .rd_addr(copy_tile_addr),
            .rd_pixel(eo3_rd_pixel), .frame_valid(eo3_frame_valid));
        EO1920x1080_Decimate3_FrameBuffer #(.MEMORY_PRIMITIVE_STR("block"), .READ_LATENCY(EO_READ_LATENCY)) u_eo_fb4 (
            .rst_n(rst_n), .wr_clk(eo4_wr_clk), .wr_hsync(eo4_wr_hsync), .wr_vsync(eo4_wr_vsync), .wr_pixel(eo4_wr_pixel),
            .rd_clk(rd_clk), .rd_frame_start(1'b0), .rd_en(eo4_rd_en), .rd_addr(copy_tile_addr),
            .rd_pixel(eo4_rd_pixel), .frame_valid(eo4_frame_valid));
        EO1920x1080_Decimate3_FrameBuffer #(.MEMORY_PRIMITIVE_STR("block"), .READ_LATENCY(EO_READ_LATENCY)) u_eo_fb5 (
            .rst_n(rst_n), .wr_clk(eo5_wr_clk), .wr_hsync(eo5_wr_hsync), .wr_vsync(eo5_wr_vsync), .wr_pixel(eo5_wr_pixel),
            .rd_clk(rd_clk), .rd_frame_start(1'b0), .rd_en(eo5_rd_en), .rd_addr(copy_tile_addr),
            .rd_pixel(eo5_rd_pixel), .frame_valid(eo5_frame_valid));

        // {row_group,col_group} delayed by EO_READ_LATENCY (rd_clk domain),
        // matching how long the EO tile buffers take to return the pixel at
        // copy_tile_addr.
        reg [3*EO_READ_LATENCY-1:0] eo_cam_pipe;
        reg [EO_READ_LATENCY-1:0]   eo_use_pipe;
        always @(posedge rd_clk) begin
            if (!rst_n) begin
                eo_cam_pipe <= {(3*EO_READ_LATENCY){1'b0}};
                eo_use_pipe <= {EO_READ_LATENCY{1'b0}};
            end else begin
                eo_cam_pipe <= {eo_cam_pipe[3*EO_READ_LATENCY-4:0], row_group, col_group};
                eo_use_pipe <= {eo_use_pipe[EO_READ_LATENCY-2:0], copy_issue};
            end
        end
        wire        eo_cur_row_group = eo_cam_pipe[3*EO_READ_LATENCY-1];
        wire [1:0]  eo_cur_col_group = eo_cam_pipe[3*EO_READ_LATENCY-2 -: 2];
        wire [19:0] eo_cur_pixel   = (!eo_cur_row_group && eo_cur_col_group == 2'd0) ? eo0_rd_pixel :
                                     (!eo_cur_row_group && eo_cur_col_group == 2'd1) ? eo1_rd_pixel :
                                     (!eo_cur_row_group && eo_cur_col_group == 2'd2) ? eo2_rd_pixel :
                                     ( eo_cur_row_group && eo_cur_col_group == 2'd0) ? eo3_rd_pixel :
                                     ( eo_cur_row_group && eo_cur_col_group == 2'd1) ? eo4_rd_pixel : eo5_rd_pixel;

        // EO1920x1080_Decimate3_FrameBuffer's rd_pixel is already restored to
        // 20 bits ({Y[7:0],2'b00,C[7:0],2'b00}); re-extract the packed 16-bit
        // {Y[7:0],C[7:0]} form the shared pack buffer expects everywhere else
        // in this file, rather than modifying the proven donor module.
        wire        copyfifo_wr_en = eo_use_pipe[EO_READ_LATENCY-1];
        // Packed YCbCr 4:2:2: one luma byte and the camera's alternating
        // Cb/Cr byte per pixel. The decimator selects complete chroma pairs,
        // and every 640-pixel tile boundary is even, so Cb/Cr phase remains
        // aligned across the 3x2 panorama.
        wire [15:0] copyfifo_din   = {eo_cur_pixel[19:12],
                                      eo_cur_pixel[9:2]};

        always @(posedge rd_clk) begin
            if (!rst_n || !copy_active_rd) begin
                col_in_tile    <= 10'd0;
                col_group      <= 2'd0;
                row_in_tile    <= 9'd0;
                row_group      <= 1'b0;
                row_base       <= 19'd0;
                copy_walk_done <= 1'b0;
            end else if (copy_issue) begin
                if (!col_last) begin
                    col_in_tile <= col_in_tile + 10'd1;
                end else begin
                    col_in_tile <= 10'd0;
                    if (!colgrp_last) begin
                        col_group <= col_group + 2'd1;
                    end else begin
                        col_group <= 2'd0;
                        if (!row_last) begin
                            row_in_tile <= row_in_tile + 9'd1;
                            row_base    <= row_base + 19'd640;
                        end else begin
                            row_in_tile <= 9'd0;
                            row_base    <= 19'd0;
                            if (!row_group)
                                row_group <= 1'b1;
                            else
                                copy_walk_done <= 1'b1;
                        end
                    end
                end
            end
        end

        //--------------------------------------------------------------------
        // Copy-stream CDC: rd_clk (74.25MHz walk/tiles) -> ui_clk (300MHz
        // pack engine). This is the only new element of the 2026-07-07
        // retiming -- everything above runs at rd_clk now; everything below
        // (and the whole pack/scan/write-launch FSM outside this generate
        // block) is unchanged, still ui_clk. (copyfifo_* wires are declared
        // up near the walk-state section above, before copy_issue's own
        // declaration references copyfifo_prog_full -- forward references
        // within a single generate branch are ordinary two-pass Verilog
        // elaboration and fine, but keeping declaration-before-use
        // throughout avoids ever needing to reason about it again.)
        //--------------------------------------------------------------------
        xpm_fifo_async #(
            .DOUT_RESET_VALUE    ("0"),
            .ECC_MODE            ("no_ecc"),
            .FIFO_MEMORY_TYPE    ("auto"),
            .FIFO_READ_LATENCY   (0),
            .FIFO_WRITE_DEPTH    (512),
            .FULL_RESET_VALUE    (0),
            .PROG_EMPTY_THRESH   (10),
            .PROG_FULL_THRESH    (448),
            .RD_DATA_COUNT_WIDTH (10),
            .READ_DATA_WIDTH     (16),
            .READ_MODE           ("fwft"),
            .SIM_ASSERT_CHK      (0),
            .USE_ADV_FEATURES    ("0303"),
            .WAKEUP_TIME         (0),
            .WR_DATA_COUNT_WIDTH (10),
            .WRITE_DATA_WIDTH    (16),
            .CDC_SYNC_STAGES     (2),
            .RELATED_CLOCKS      (0)
        ) u_copy_cdc_fifo (
            .sleep         (1'b0),
            .rst           (~rst_n),
            .wr_clk        (rd_clk),
            .wr_en         (copyfifo_wr_en),
            .din           (copyfifo_din),
            .full          (copyfifo_full),
            .overflow      (copyfifo_overflow),
            .wr_rst_busy   (),
            .wr_ack        (),
            .wr_data_count (),
            .almost_full   (),
            .prog_full     (copyfifo_prog_full),
            .rd_clk        (c0_ddr4_ui_clk),
            .rd_en         (copyfifo_rd_en),
            .dout          (copyfifo_dout),
            .empty         (copyfifo_empty),
            .underflow     (copyfifo_underflow),
            .rd_rst_busy   (),
            .data_valid    (),
            .rd_data_count (),
            .almost_empty  (),
            .prog_empty    (),
            .injectsbiterr (1'b0),
            .injectdbiterr (1'b0)
        );

        // ui_clk side: pop exactly one pixel per cycle whenever the pack
        // engine is mid-copy, not itself stalled on a pending write, and the
        // FIFO has data (FWFT: pop and consume in the same cycle). Idle-
        // drain any residual pixels if a copy is aborted (e.g. calibration
        // lost mid-copy) so a stale pixel can never bleed into the next
        // copy; that path is expected to never fire in normal operation
        // (pixel production/consumption are exactly conserved per copy), so
        // it is latched into a sticky ILA-only diagnostic rather than wired
        // to any functional signal.
        wire copy_px_take   = copy_active && !fb_write_pending && !copyfifo_empty;
        wire copy_idle_drain = !copy_active && !copyfifo_empty;
        assign copyfifo_rd_en = copy_px_take || copy_idle_drain;
        assign copy_px_valid  = copy_px_take;
        assign copy_px_data   = copyfifo_dout;

        (* mark_debug = "true", dont_touch = "true" *)
        reg dbg_copyfifo_resid;
        always @(posedge c0_ddr4_ui_clk) begin
            if (ui_rst)
                dbg_copyfifo_resid <= 1'b0;
            else if (copy_idle_drain)
                dbg_copyfifo_resid <= 1'b1;
        end

        //--------------------------------------------------------------------
        // Hardware bring-up ILA #3 (dbg_ila_2, compositor tile-select walk)
        // was instantiated here 2026-07-07 (see plan section 18.8) and has
        // since been removed (2026-07-08): its job -- verifying col_group/
        // row_group cycling and the eo*_rd_en tile-select mux -- was
        // conclusively confirmed correct twice on hardware (16374/16374
        // events matched their expected tile with zero mismatches on the
        // most recent capture, plan section 18.8/re-verification during
        // section 19.1), and it was blocking synthesis after the DDR4 IP
        // regeneration in section 20 for unrelated reasons (stale
        // out-of-context reference). Re-add via a fresh create_ip if the
        // compositor walk ever needs live re-verification again.
    end else if (SRC_SEL == SRC_EO0) begin : g_src_eo0
        //--------------------------------------------------------------------
        // Diagnostic-only single-camera source (2026-07-07, see
        // docs/DDR_EO_PANORAMA_FIX_PLAN.md section 18.11): streams ONLY the
        // cam0 640x480 decimated tile through DDR. No compositor, no
        // tile-select mux, no col_group/row_group cycling at all -- just
        // one EO1920x1080_Decimate3_FrameBuffer and a trivial single-tile
        // walk. Purpose: isolate whether the already-confirmed DDR read
        // corruption (section 16, present even in the SRC_RAMP build,
        // which has no EO logic at all) is sufficient by itself to explain
        // the segment-duplication look the user reported on the full
        // 6-camera stack, now that the compositor walk itself has been
        // hardware-proven correct (section 18.8) and is no longer a
        // suspect. This branch is a trimmed copy of g_src_eostk's
        // machinery (CDC synchronizers, walk, copy CDC FIFO, ui_clk-side
        // pop) with the 6-way tile-select removed -- see g_src_eostk above
        // for the fuller commentary on each piece; not repeated here.
        //--------------------------------------------------------------------
        wire [19:0] eo0_rd_pixel_solo;
        wire        eo0_frame_valid_solo;

        reg copy_active_meta, copy_active_rd;
        always @(posedge rd_clk) begin
            if (!rst_n) begin
                copy_active_meta <= 1'b0;
                copy_active_rd   <= 1'b0;
            end else begin
                copy_active_meta <= copy_active;
                copy_active_rd   <= copy_active_meta;
            end
        end

        reg eo_frames_valid_meta, eo_frames_valid_ui;
        always @(posedge c0_ddr4_ui_clk) begin
            if (ui_rst) begin
                eo_frames_valid_meta <= 1'b0;
                eo_frames_valid_ui   <= 1'b0;
            end else begin
                eo_frames_valid_meta <= eo0_frame_valid_solo;
                eo_frames_valid_ui   <= eo_frames_valid_meta;
            end
        end
        assign eo_frames_valid = eo_frames_valid_ui;

        wire        copyfifo_full, copyfifo_empty, copyfifo_prog_full;
        wire        copyfifo_overflow, copyfifo_underflow;
        wire [15:0] copyfifo_dout;
        wire        copyfifo_rd_en;

        reg  [9:0]  col_in_tile;
        reg  [8:0]  row_in_tile;
        reg  [18:0] row_base;
        reg         copy_walk_done;

        wire        copy_issue     = copy_active_rd && !copy_walk_done && !copyfifo_prog_full;
        wire [18:0] copy_tile_addr = row_base + {9'd0, col_in_tile};

        wire eo0_rd_en_solo = copy_issue;

        wire col_last = (col_in_tile == 10'd639);
        wire row_last = (row_in_tile == 9'd479);

        localparam integer EO_READ_LATENCY = 2;

        EO1920x1080_Decimate3_FrameBuffer #(
            .MEMORY_PRIMITIVE_STR("ultra"), .READ_LATENCY(EO_READ_LATENCY),
            .CLOCKING_MODE_STR("common_clock"), .FIFO_RELATED_CLOCKS(1), .USE_ASYNC_FIFO(0)
        ) u_eo_fb0 (
            .rst_n(rst_n), .wr_clk(eo0_wr_clk), .wr_hsync(eo0_wr_hsync), .wr_vsync(eo0_wr_vsync), .wr_pixel(eo0_wr_pixel),
            .rd_clk(rd_clk), .rd_frame_start(1'b0), .rd_en(eo0_rd_en_solo), .rd_addr(copy_tile_addr),
            .rd_pixel(eo0_rd_pixel_solo), .frame_valid(eo0_frame_valid_solo));

        reg [EO_READ_LATENCY-1:0] eo_use_pipe;
        always @(posedge rd_clk) begin
            if (!rst_n)
                eo_use_pipe <= {EO_READ_LATENCY{1'b0}};
            else
                eo_use_pipe <= {eo_use_pipe[EO_READ_LATENCY-2:0], copy_issue};
        end
        wire        copyfifo_wr_en = eo_use_pipe[EO_READ_LATENCY-1];
        // Preserve the camera's alternating Cb/Cr byte for YCbCr 4:2:2.
        wire [15:0] copyfifo_din   = {eo0_rd_pixel_solo[19:12],
                                      eo0_rd_pixel_solo[9:2]};

        always @(posedge rd_clk) begin
            if (!rst_n || !copy_active_rd) begin
                col_in_tile    <= 10'd0;
                row_in_tile    <= 9'd0;
                row_base       <= 19'd0;
                copy_walk_done <= 1'b0;
            end else if (copy_issue) begin
                if (!col_last) begin
                    col_in_tile <= col_in_tile + 10'd1;
                end else begin
                    col_in_tile <= 10'd0;
                    if (!row_last) begin
                        row_in_tile <= row_in_tile + 9'd1;
                        row_base    <= row_base + 19'd640;
                    end else begin
                        row_in_tile    <= 9'd0;
                        row_base       <= 19'd0;
                        copy_walk_done <= 1'b1;
                    end
                end
            end
        end

        xpm_fifo_async #(
            .DOUT_RESET_VALUE    ("0"),
            .ECC_MODE            ("no_ecc"),
            .FIFO_MEMORY_TYPE    ("auto"),
            .FIFO_READ_LATENCY   (0),
            .FIFO_WRITE_DEPTH    (512),
            .FULL_RESET_VALUE    (0),
            .PROG_EMPTY_THRESH   (10),
            .PROG_FULL_THRESH    (448),
            .RD_DATA_COUNT_WIDTH (10),
            .READ_DATA_WIDTH     (16),
            .READ_MODE           ("fwft"),
            .SIM_ASSERT_CHK      (0),
            .USE_ADV_FEATURES    ("0303"),
            .WAKEUP_TIME         (0),
            .WR_DATA_COUNT_WIDTH (10),
            .WRITE_DATA_WIDTH    (16),
            .CDC_SYNC_STAGES     (2),
            .RELATED_CLOCKS      (0)
        ) u_copy_cdc_fifo (
            .sleep         (1'b0),
            .rst           (~rst_n),
            .wr_clk        (rd_clk),
            .wr_en         (copyfifo_wr_en),
            .din           (copyfifo_din),
            .full          (copyfifo_full),
            .overflow      (copyfifo_overflow),
            .wr_rst_busy   (),
            .wr_ack        (),
            .wr_data_count (),
            .almost_full   (),
            .prog_full     (copyfifo_prog_full),
            .rd_clk        (c0_ddr4_ui_clk),
            .rd_en         (copyfifo_rd_en),
            .dout          (copyfifo_dout),
            .empty         (copyfifo_empty),
            .underflow     (copyfifo_underflow),
            .rd_rst_busy   (),
            .data_valid    (),
            .rd_data_count (),
            .almost_empty  (),
            .prog_empty    (),
            .injectsbiterr (1'b0),
            .injectdbiterr (1'b0)
        );

        wire copy_px_take   = copy_active && !fb_write_pending && !copyfifo_empty;
        wire copy_idle_drain = !copy_active && !copyfifo_empty;
        assign copyfifo_rd_en = copy_px_take || copy_idle_drain;
        assign copy_px_valid  = copy_px_take;
        assign copy_px_data   = copyfifo_dout;

        (* mark_debug = "true", dont_touch = "true" *)
        reg dbg_copyfifo_resid;
        always @(posedge c0_ddr4_ui_clk) begin
            if (ui_rst)
                dbg_copyfifo_resid <= 1'b0;
            else if (copy_idle_drain)
                dbg_copyfifo_resid <= 1'b1;
        end
    end else if (SRC_SEL == SRC_EO0RAW) begin : g_src_eo0raw
        //--------------------------------------------------------------------
        // Diagnostic-only single-camera, FULL NATIVE RESOLUTION source
        // (2026-07-08 rewrite, see docs/DDR_EO_PANORAMA_FIX_PLAN.md section
        // 18.15): streams cam0 at its true 1920x1080 resolution through DDR
        // with NO decimation and NO compositor.  The first attempt at this
        // stored a whole native-resolution frame ON-CHIP before ever
        // touching DDR (EO1920x1080_RawFrameBuffer) -- that needed 1034
        // RAMB36E2 against only 984 available and hit a hard implementation
        // capacity failure.  That was the wrong shape: DDR is *supposed* to
        // be the frame buffer here, not on-chip BRAM/URAM.  This version is
        // a genuine streaming pass-through -- camera pixels are pushed
        // straight into the same small CDC FIFO every other source uses to
        // cross eo0_wr_clk into ui_clk, in raster order, as they arrive.
        // There is no on-chip full-frame storage at all, so the resource
        // footprint is trivial (one ~2K-deep FIFO) regardless of resolution.
        //
        // Because there is no complete on-chip frame to read back from, a
        // copy pass can't start "whenever the display wants a fresh bank"
        // the way g_src_eostk/g_src_eo0 do -- it must start exactly when the
        // camera itself begins a new frame, or the pass would begin mid-
        // frame and tear.  copy_start_trig (module scope, above) special-
        // cases SRC_EO0RAW to use eo0_frame_edge_ui (synced from eo0_wr_clk)
        // instead of the display-side frame_edge for this reason.  Verified
        // DDR write throughput comfortably exceeds the camera's real-time
        // pixel rate (section 17), so the write engine always finishes
        // packing one frame's worth of pixels well before the next camera
        // frame begins -- the CDC FIFO only ever needs to smooth momentary
        // arbitration backpressure, never hold anywhere near a whole frame.
        //--------------------------------------------------------------------
        reg eo0raw_frames_valid;
        always @(posedge c0_ddr4_ui_clk) begin
            if (ui_rst)                  eo0raw_frames_valid <= 1'b0;
            else if (eo0_frame_edge_ui)  eo0raw_frames_valid <= 1'b1;
        end
        assign eo_frames_valid = eo0raw_frames_valid;

        wire        copyfifo_full, copyfifo_empty;
        wire        copyfifo_overflow, copyfifo_underflow;
        wire [15:0] copyfifo_dout;
        wire        copyfifo_rd_en;

        wire        eo0_wr_frame_active = ~eo0_wr_vsync;
        wire        eo0_wr_sample_now   = eo0_wr_frame_active && eo0_wr_hsync && !copyfifo_full;
        // Preserve the camera's alternating Cb/Cr byte for YCbCr 4:2:2.
        wire [15:0] eo0_wr_pixel_packed = {eo0_wr_pixel[19:12],
                                           eo0_wr_pixel[9:2]};

        // Sticky: camera produced an active pixel while the CDC FIFO was
        // full -- should never happen given the bandwidth headroom above;
        // exists purely for hardware bring-up visibility, matching this
        // project's established dbg_*_seen convention.
        (* mark_debug = "true", dont_touch = "true" *)
        reg dbg_eo0raw_fifo_ovf_seen;
        always @(posedge eo0_wr_clk) begin
            if (!rst_n) dbg_eo0raw_fifo_ovf_seen <= 1'b0;
            else if (eo0_wr_frame_active && eo0_wr_hsync && copyfifo_full)
                dbg_eo0raw_fifo_ovf_seen <= 1'b1;
        end

        xpm_fifo_async #(
            .DOUT_RESET_VALUE    ("0"),
            .ECC_MODE            ("no_ecc"),
            .FIFO_MEMORY_TYPE    ("auto"),
            .FIFO_READ_LATENCY   (0),
            .FIFO_WRITE_DEPTH    (2048),
            .FULL_RESET_VALUE    (0),
            .PROG_EMPTY_THRESH   (10),
            .PROG_FULL_THRESH    (1984),
            .RD_DATA_COUNT_WIDTH (12),
            .READ_DATA_WIDTH     (16),
            .READ_MODE           ("fwft"),
            .SIM_ASSERT_CHK      (0),
            .USE_ADV_FEATURES    ("0303"),
            .WAKEUP_TIME         (0),
            .WR_DATA_COUNT_WIDTH (12),
            .WRITE_DATA_WIDTH    (16),
            .CDC_SYNC_STAGES     (2),
            .RELATED_CLOCKS      (0)
        ) u_copy_cdc_fifo (
            .sleep         (1'b0),
            .rst           (~rst_n),
            .wr_clk        (eo0_wr_clk),
            .wr_en         (eo0_wr_sample_now),
            .din           (eo0_wr_pixel_packed),
            .full          (copyfifo_full),
            .overflow      (copyfifo_overflow),
            .wr_rst_busy   (),
            .wr_ack        (),
            .wr_data_count (),
            .almost_full   (),
            .prog_full     (),
            .rd_clk        (c0_ddr4_ui_clk),
            .rd_en         (copyfifo_rd_en),
            .dout          (copyfifo_dout),
            .empty         (copyfifo_empty),
            .underflow     (copyfifo_underflow),
            .rd_rst_busy   (),
            .data_valid    (),
            .rd_data_count (),
            .almost_empty  (),
            .prog_empty    (),
            .injectsbiterr (1'b0),
            .injectdbiterr (1'b0)
        );

        wire copy_px_take   = copy_active && !fb_write_pending && !copyfifo_empty;
        wire copy_idle_drain = !copy_active && !copyfifo_empty;
        assign copyfifo_rd_en = copy_px_take || copy_idle_drain;
        assign copy_px_valid  = copy_px_take;
        assign copy_px_data   = copyfifo_dout;

        (* mark_debug = "true", dont_touch = "true" *)
        reg dbg_copyfifo_resid;
        always @(posedge c0_ddr4_ui_clk) begin
            if (ui_rst)
                dbg_copyfifo_resid <= 1'b0;
            else if (copy_idle_drain)
                dbg_copyfifo_resid <= 1'b1;
        end
    end else begin : g_src_ramp
        //--------------------------------------------------------------------
        // Stage-A IR/ramp source (unchanged from the proven DDR bring-up):
        // one outstanding BRAM read at a time, 2-cycle latency.  fb_rd_en and
        // fb_rd_addr are declared at module scope (the unconditional IR
        // capture buffers above reference them); this block is their only
        // driver in this build.
        //--------------------------------------------------------------------
        assign eo_frames_valid = 1'b0;  // unused source in this build

        reg fb_rd_busy;
        reg fb_rd_en_d1, fb_rd_en_d2;

        always @(posedge c0_ddr4_ui_clk) begin
            if (ui_rst || !copy_active) begin
                fb_rd_en    <= 1'b0;
                fb_rd_en_d1 <= 1'b0;
                fb_rd_en_d2 <= 1'b0;
                fb_rd_addr  <= 19'd0;
                fb_rd_busy  <= 1'b0;
            end else begin
                fb_rd_en    <= 1'b0;
                fb_rd_en_d1 <= fb_rd_en;
                fb_rd_en_d2 <= fb_rd_en_d1;

                if (!fb_rd_busy && !fb_write_pending && (fb_rd_addr < FRAME_PIXELS)) begin
                    fb_rd_en   <= 1'b1;
                    fb_rd_busy <= 1'b1;
                end

                if (fb_rd_en_d2) begin
                    fb_rd_busy <= 1'b0;
                    fb_rd_addr <= fb_rd_addr + 19'd1;
                end
            end
        end

        assign copy_px_valid = fb_rd_en_d2;
        assign copy_px_data  = PATTERN_TEST ? {fb_rd_addr[7:0], 8'h80}   // known raster ramp
                                             : {sel_rd_pixel,    8'h80}; // live captured pixel
    end
    endgenerate

    always @(posedge c0_ddr4_ui_clk) begin
        if (ui_rst) begin
            running          <= 1'b0;
            cmd_pend         <= 1'b0;
            cmd_is_rd        <= 1'b0;
            cmd_is_keepalive <= 1'b0;
            cmd_addr_q       <= 29'd0;
            wdf_pend         <= 1'b0;
            wdf_data_q       <= BLACK_BURST;
            w_cmd_done       <= 1'b0;
            w_wdf_done       <= 1'b0;
            pix_fifo_wr_en   <= 1'b0;
            pix_fifo_wr_data <= 16'd0;
            beat_fifo_wr_en  <= 1'b0;
            beat_fifo_rd_en  <= 1'b0;
            fb_write_pending <= 1'b0;
            fb_pack_count    <= 6'd0;
            fb_burst_count   <= 17'd0;
            fb_pack_buf      <= {DDR_APP_DATA_W{1'b0}};
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
            dbg_beat_overflow<= 1'b0;
            dbg_cmd_retry_seen <= 1'b0;
            scan_active      <= 1'b0;
            rd_data_capture  <= {DDR_APP_DATA_W{1'b0}};
            read_gap_counter <= 10'd0;
            flush_active     <= 1'b0;
            flush_commit_pending <= 1'b0;
            rd_addr          <= BANK0_BASE;
            rd_issue_count   <= 17'd0;
            outstanding      <= 7'd0;
            unpack_shift     <= {DDR_APP_DATA_W{1'b0}};
            unpack_count     <= 6'd0;
            ftog_meta        <= 1'b0;
            ftog_sync        <= 1'b0;
            ftog_sync_d      <= 1'b0;
        end else begin
            // --- default strobes (single-cycle) ---
            pix_fifo_wr_en       <= 1'b0;
            beat_fifo_wr_en      <= 1'b0;
            beat_fifo_rd_en      <= 1'b0;

            // renderer frame-toggle CDC (rd_clk -> ui_clk)
            ftog_meta   <= renderer_frame_toggle;
            ftog_sync   <= ftog_meta;
            ftog_sync_d <= ftog_sync;

            outstanding_next = outstanding;

            //----------------------------------------------------------------
            // beat_fifo -> 16x16b guarded-payload unpack -> pix_fifo.
            // The high 128-bit failing-component region is never rendered.
            // Suspended during a
            // frame-boundary flush (stale beats are drained and discarded by
            // the third branch instead of being unpacked into new pixels).
            //----------------------------------------------------------------
            if (!flush_active && (unpack_count != 0) && !pix_fifo_full && !pix_fifo_wr_rst_busy) begin
                pix_fifo_wr_en   <= 1'b1;
                pix_fifo_wr_data <= unpack_shift[15:0];
                unpack_shift     <= {16'd0, unpack_shift[DDR_APP_DATA_W-1:16]};
                unpack_count     <= unpack_count - 6'd1;
                dbg_pixwrite_seen<= 1'b1;
            end else if (!flush_active && !beat_fifo_empty && !pix_fifo_prog_full && !pix_fifo_wr_rst_busy) begin
                beat_fifo_rd_en   <= 1'b1;
                unpack_shift      <= {
                    {(DDR_APP_DATA_W-DDR_PAYLOAD_BITS){1'b0}},
                    beat_fifo_dout[DDR_GUARD_OFFSET_BITS +: DDR_PAYLOAD_BITS]
                };
                unpack_count      <= PIXELS_PER_BEAT_COUNT;
            end else if (flush_active && (outstanding == 7'd0) && !beat_fifo_empty) begin
                beat_fifo_rd_en <= 1'b1;   // drain and discard stale beats
            end

            // DDR read data returns -> push to beat_fifo, decrement outstanding.
            // Defensively gate on !beat_fifo_full (should be unreachable given
            // MAX_OUTSTANDING+PROG_FULL_THRESH margin below the FIFO depth);
            // the sticky overflow alarm below is the authoritative check.
            if (c0_ddr4_app_rd_data_valid) begin
                dbg_rddata_seen <= 1'b1;
                rd_data_capture <= c0_ddr4_app_rd_data;
                // Only real scan completions may enter beat_fifo -- a
                // keepalive dummy completion is discarded here (v1's
                // suspected bug was exactly this classification going
                // wrong; see rd_return_is_keepalive's declaration comment).
                if (!rd_return_is_keepalive && !beat_fifo_full)
                    beat_fifo_wr_en <= 1'b1;
                if (outstanding_next != 0)
                    outstanding_next = outstanding_next - 7'd1;
            end

            // Sticky "should never happen" alarms (real logic regression if set).
            if (beat_fifo_overflow || pix_fifo_overflow)
                dbg_beat_overflow <= 1'b1;

            //----------------------------------------------------------------
            // Pack whatever the active source (RAMP/IR or EO panorama,
            // SRC_SEL-selected generate branch above) produces into the
            // DDR app beat buffer. Source-agnostic: 16 packed 16-bit pixels
            // per burst in the clean low 256-bit region.
            //----------------------------------------------------------------
            if (copy_px_valid) begin
                fb_pack_buf[DDR_GUARD_OFFSET_BITS +
                            {fb_pack_count, 4'b0000} +: 16] <= copy_px_data;
                if (fb_pack_count == PIXELS_PER_BEAT_LAST)
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
                flush_active  <= 1'b0;
                flush_commit_pending <= 1'b0;
                cmd_pend      <= 1'b0;
                wdf_pend      <= 1'b0;
                w_cmd_done    <= 1'b0;
                w_wdf_done    <= 1'b0;
                pending_valid <= 1'b0;
                frame_valid   <= 1'b0;
                dbg_pulse_seen<= 1'b0;
                dbg_wpend_seen<= 1'b0;
                dbg_grant_seen<= 1'b0;
                dbg_copydone_seen <= 1'b0;
                dbg_scan_issue_seen <= 1'b0;
                dbg_rddata_seen  <= 1'b0;
                dbg_pixwrite_seen<= 1'b0;
                dbg_beat_overflow<= 1'b0;
                dbg_cmd_retry_seen <= 1'b0;
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

                if (copy_start_trig)
                    dbg_pulse_seen <= 1'b1;

                //------------------------------------------------------------
                // Start a copy once the active source (RAMP/IR or EO panorama,
                // see copy_start_trig above) has a fresh frame ready.  An
                // already-running copy is NEVER aborted by a mode/source
                // change (that teardown was the old "committed-then-lost /
                // cyan" bug) -- copy_start_trig is simply ignored while
                // copy_active, so the in-flight copy always finishes.
                //------------------------------------------------------------
                if (copy_start_trig && !copy_active) begin
                    copy_active      <= 1'b1;
                    wr_addr          <= wr_bank_base;
                    fb_pack_count    <= 6'd0;
                    fb_burst_count   <= 17'd0;
                    fb_write_pending <= 1'b0;
                    fb_pack_buf      <= {DDR_APP_DATA_W{1'b0}};
                end

                if (fb_write_pending)
                    dbg_wpend_seen <= 1'b1;

                //------------------------------------------------------------
                // Frame-boundary commit / flush-and-resync (issues no DDR
                // command itself).  If the previous scan left anything
                // in-flight or unconsumed (stuck/slow scan, leftover beats,
                // partial unpack), do NOT commit on this edge: drain
                // everything cleanly first and commit one frame later. Any
                // transient stall then becomes a deterministic one-frame
                // repeat of the last committed bank instead of a permanent
                // stream desync.
                //------------------------------------------------------------
                if (frame_edge) begin
                    if (flush_active) begin
                        // Still cleaning up from the previous edge; remember
                        // that the renderer has already reset stream_started
                        // and start the scan as soon as this flush completes.
                        flush_commit_pending <= 1'b1;
                    end else if (scan_active || (outstanding != 7'd0) ||
                                 !beat_fifo_empty || (unpack_count != 6'd0)) begin
                        scan_active  <= 1'b0;
                        flush_active <= 1'b1;
                        flush_commit_pending <= 1'b1;
                        unpack_shift <= {DDR_APP_DATA_W{1'b0}};
                        unpack_count <= 6'd0;
                    end else begin
                        flush_commit_pending <= 1'b0;
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
                            unpack_shift    <= {DDR_APP_DATA_W{1'b0}};
                        end
                    end
                end

                // Flush completes once every in-flight read has returned
                // (outstanding drained naturally by the rd_data_valid logic
                // above) and beat_fifo has been emptied by the unpack chain's
                // drain branch above.
                if (flush_active && (outstanding == 7'd0) && beat_fifo_empty) begin
                    flush_active <= 1'b0;
                    if (flush_commit_pending) begin
                        flush_commit_pending <= 1'b0;
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
                            unpack_shift    <= {DDR_APP_DATA_W{1'b0}};
                        end
                    end
                end

                //------------------------------------------------------------
                // DDR command launch/retire (held-enable FSM).  Only one
                // command is ever in flight; the next one is not launched
                // until the previous command -- and, for writes, its write
                // data -- has actually been accepted by the MIG (app_rdy /
                // app_wdf_rdy sampled the SAME cycle as the held app_en /
                // app_wdf_wren, per PG150).  Read (scan) has priority over
                // write (copy) so the display FIFO never starves; the copy
                // has a full frame of slack and fills the gaps.
                //------------------------------------------------------------
                if (cmd_pend && !c0_ddr4_app_rdy)     dbg_cmd_retry_seen <= 1'b1;
                if (wdf_pend && !c0_ddr4_app_wdf_rdy) dbg_cmd_retry_seen <= 1'b1;

                if (cmd_fire) cmd_pend <= 1'b0;
                if (wdf_fire) wdf_pend <= 1'b0;
                if (cmd_fire && !cmd_is_rd) w_cmd_done <= 1'b1;
                if (wdf_fire)               w_wdf_done <= 1'b1;

                if (read_retiring) begin
                    outstanding_next = outstanding_next + 7'd1;
                    read_gap_counter <= 10'd0;
                    // Only a REAL scan read may advance the scan walk --
                    // a keepalive dummy read occupies an MIG command slot
                    // (already reflected in outstanding_next above) but
                    // must never consume scan progress.
                    if (!cmd_is_keepalive) begin
                        dbg_scan_issue_seen <= 1'b1;
                        if (rd_issue_count == BEATS_TOTAL - 1) begin
                            scan_active    <= 1'b0;
                            rd_issue_count <= 17'd0;
                        end else begin
                            rd_issue_count <= rd_issue_count + 17'd1;
                            rd_addr        <= rd_addr + ADDR_STRIDE;
                        end
                    end
                end else if (read_gap_counter != 10'd1023) begin
                    read_gap_counter <= read_gap_counter + 10'd1;
                end

                if (write_retiring) begin
                    dbg_grant_seen   <= 1'b1;
                    fb_write_pending <= 1'b0;
                    fb_pack_count    <= 6'd0;
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

                if (!issue_busy) begin
                    if (scan_want) begin
                        cmd_pend         <= 1'b1;
                        cmd_is_rd        <= 1'b1;
                        cmd_is_keepalive <= 1'b0;
                        cmd_addr_q       <= rd_addr;
                    end else if (keepalive_want) begin
                        cmd_pend         <= 1'b1;
                        cmd_is_rd        <= 1'b1;
                        cmd_is_keepalive <= 1'b1;
                        cmd_addr_q       <= keepalive_addr;
                    end else if (write_want) begin
                        cmd_pend         <= 1'b1;
                        cmd_is_rd        <= 1'b0;
                        cmd_is_keepalive <= 1'b0;
                        cmd_addr_q       <= wr_addr;
                        wdf_pend         <= 1'b1;
                        wdf_data_q       <= fb_pack_buf;
                        w_cmd_done       <= 1'b0;
                        w_wdf_done       <= 1'b0;
                    end
                end
            end

            outstanding <= outstanding_next;
        end
    end

    //------------------------------------------------------------------------
    // Read-return tag queue push/pop (see the rd_tag_* declarations above
    // for why this is a plain explicit ring buffer, not an XPM FWFT FIFO).
    // Push happens on read_retiring (any accepted read, real or
    // keepalive); pop happens on c0_ddr4_app_rd_data_valid -- the native
    // interface returns completions strictly in issue order, so a plain
    // FIFO in issue order is an exact match. Handles push+pop landing on
    // the same cycle correctly (net count unchanged, both pointers
    // advance independently).
    //------------------------------------------------------------------------
    always @(posedge c0_ddr4_ui_clk) begin
        if (ui_rst) begin
            rd_tag_head      <= {RD_TAG_AWIDTH{1'b0}};
            rd_tag_tail      <= {RD_TAG_AWIDTH{1'b0}};
            rd_tag_count     <= {(RD_TAG_AWIDTH+1){1'b0}};
            rd_tag_overflow  <= 1'b0;
            rd_tag_underflow <= 1'b0;
        end else begin
            if (read_retiring) begin
                if (rd_tag_count == RD_TAG_DEPTH) begin
                    rd_tag_overflow <= 1'b1;   // sticky -- should never happen
                end else begin
                    rd_tag_mem[rd_tag_head] <= cmd_is_keepalive;
                    rd_tag_head <= (rd_tag_head == RD_TAG_DEPTH-1) ? {RD_TAG_AWIDTH{1'b0}} : rd_tag_head + 5'd1;
                end
            end
            if (c0_ddr4_app_rd_data_valid) begin
                if (rd_tag_count == 0) begin
                    rd_tag_underflow <= 1'b1;  // sticky -- should never happen
                end else begin
                    rd_tag_tail <= (rd_tag_tail == RD_TAG_DEPTH-1) ? {RD_TAG_AWIDTH{1'b0}} : rd_tag_tail + 5'd1;
                end
            end
            case ({read_retiring && (rd_tag_count != RD_TAG_DEPTH),
                   c0_ddr4_app_rd_data_valid && (rd_tag_count != 0)})
                2'b10:   rd_tag_count <= rd_tag_count + 6'd1;
                2'b01:   rd_tag_count <= rd_tag_count - 6'd1;
                default: rd_tag_count <= rd_tag_count;   // 00 (idle) or 11 (push+pop cancel out)
            endcase
        end
    end

    // In the EO panorama and cam0-only diagnostic builds the copy trigger is
    // free-running on eo_frames_valid rather than gated by ir_single_ui, so
    // the "mode not enabled" pre-commit diagnostic no longer applies to any
    // processed mode.
    wire renderer_mode_enabled = (SRC_SEL == SRC_EOSTK || SRC_SEL == SRC_EO0 || SRC_SEL == SRC_EO0RAW) ? 1'b1 : ir_single_ui;

    //------------------------------------------------------------------------
    // Hardware bring-up ILA (2026-07-07, see docs/DDR_EO_PANORAMA_FIX_PLAN.md
    // sections 13-15): probes the shared write/pack and read/unpack path to
    // find the vertical-stripe corruption bug the SRC_RAMP bisection proved
    // lives in this source-agnostic back end, not the EO-specific front end.
    // Section 13/14's narrower probes (16-bit corners) proved the write side
    // is clean and pinned the corruption to c0_ddr4_app_rd_data bits[15:0],
    // but section 15's calibration margin dashboard showed byte0 (bits[7:0])
    // has perfectly ordinary margins -- ruling out a per-byte analog issue
    // and pointing instead at a specific time-slot/chunk within the BL8
    // burst assembly. probe5/probe11/probe14 were widened from
    // 16-bit corners to full 64-bit corners to check whether bytes 2-7 at
    // the same chunk position as the already-known-bad byte0/1 are ALSO
    // wrong (time-slot theory) or clean (byte-specific theory survives).
    // First attempt concatenated two disjoint 64-bit ranges into one wide
    // port ({sig[511:448], sig[63:0]}); Vivado's debug-probe auto-naming
    // only produced a usable name for a 32-bit fragment of that (a MAP of
    // "probe5[31:0]", confirmed via report_property on the hw_probe object
    // -- the other 96 bits were simply inaccessible by name, not corrupt
    // data, but unusable all the same). Fixed by giving each single
    // CONTIGUOUS 64-bit range its own dedicated probe port (probe19-24)
    // instead of concatenating disjoint ranges -- probe6/wr_addr[15:0] etc.
    // (simple contiguous slices, no concatenation) always named correctly,
    // which is what motivated this restructuring. probe5/11/14 reverted to
    // their original 32-bit first+last-pixel form. Temporary bring-up
    // instrumentation -- remove once root cause is fixed.
    //------------------------------------------------------------------------
    dbg_ila_0 u_dbg_ila_0 (
        .clk     (c0_ddr4_ui_clk),
        .probe0  (copy_px_valid),
        .probe1  (copy_px_data),
        .probe2  (fb_pack_count),
        .probe3  (fb_write_pending),
        .probe4  (write_retiring),
        .probe5  ({wdf_data_q[DDR_APP_DATA_W-1 -: 16], wdf_data_q[15:0]}),
        .probe6  (wr_addr[15:0]),
        .probe7  ({cmd_pend, cmd_is_rd, c0_ddr4_app_rdy, wdf_pend, c0_ddr4_app_wdf_rdy}),
        .probe8  (read_retiring),
        .probe9  (rd_addr[15:0]),
        .probe10 (c0_ddr4_app_rd_data_valid),
        .probe11 ({c0_ddr4_app_rd_data[DDR_APP_DATA_W-1 -: 16], c0_ddr4_app_rd_data[15:0]}),
        .probe12 (outstanding),
        .probe13 ({beat_fifo_wr_en, beat_fifo_rd_en, beat_fifo_empty, beat_fifo_full}),
        .probe14 ({beat_fifo_dout[DDR_APP_DATA_W-1 -: 16], beat_fifo_dout[15:0]}),
        .probe15 (unpack_count),
        .probe16 ({pix_fifo_wr_en, pix_fifo_wr_data}),
        .probe17 ({scan_active, copy_active, flush_active, frame_edge}),
        .probe18 ({dbg_beat_overflow, dbg_cmd_retry_seen}),
        .probe19 (wdf_data_q[63:0]),
        .probe20 (dbg_bus[63:0]),
        .probe21 (c0_ddr4_app_rd_data[63:0]),
        .probe22 (dbg_bus[127:64]),
        .probe23 (dbg_bus[191:128]),
        .probe24 (dbg_bus[255:192]),
        // Keepalive v2 visibility (docs/DDR_READ_CADENCE_VT_TRACKING_FIX_PLAN.md
        // phase 0): added before re-attempting the fix so a next hardware
        // failure shows WHY instead of just "black screen" -- directly
        // distinguishes the two leading v1-regression hypotheses (flush
        // interaction vs. tag-queue desync) rather than reasoning blind.
        .probe25 ({rd_tag_overflow, rd_tag_underflow, keepalive_want, keepalive_launch,
                   cmd_is_keepalive, rd_return_is_keepalive, frame_valid}),
        .probe26 (read_gap_counter),
        .probe27 (rd_tag_count)
    );

    //------------------------------------------------------------------------
    // HD renderer (rd_clk).  Streams the committed frame into the SRC_SEL
    // window (centered 640x512 for the ramp, top-aligned 1920x960 for the EO
    // panorama); black elsewhere.  All ui_clk control inputs crossed via 2-FF
    // synchronizers.
    //------------------------------------------------------------------------
    PanoramaBase_HdDdrRenderer #(
        .SRC_W (SRC_W),
        .SRC_H (SRC_H),
        .X_OFF (WIN_X_OFF),
        .Y_OFF (WIN_Y_OFF)
    ) u_hd_renderer (
        .rst_n          (rst_n),
        .rd_clk         (rd_clk),
        .mode_enabled   (renderer_mode_enabled),
        .dbg_pulse_seen (dbg_pulse_seen),
        .dbg_wpend_seen (dbg_wpend_seen),
        .dbg_grant_seen (dbg_grant_seen),
        .dbg_copydone_seen(dbg_copydone_seen),
        .dbg_scan_issue_seen(dbg_scan_issue_seen),
        .dbg_rddata_seen(dbg_rddata_seen),
        .dbg_pixwrite_seen(dbg_pixwrite_seen),
        .dbg_beat_overflow(dbg_beat_overflow),
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
//  BT.1120 1080p60 timing generator + SRC_W x SRC_H window scan-out at
//  (X_OFF, Y_OFF); black elsewhere.  Defaults match the Stage-A centered
//  640x512 ramp/IR window; the parent overrides them per SRC_SEL (the EO
//  panorama build passes SRC_W=1920, SRC_H=960, X_OFF=Y_OFF=0).
//  frame_valid is the only control input; it is synchronized internally.
//============================================================================
module PanoramaBase_HdDdrRenderer #(
    parameter integer SRC_W = 640,
    parameter integer SRC_H = 512,
    parameter integer X_OFF = (1920 - 640) / 2,
    parameter integer Y_OFF = (1080 - 512) / 2
)(
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
    input  wire        dbg_beat_overflow,
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
    localparam [19:0]  BLACK       = {10'd64, 10'd512};          // Y=64, C=512

    // Vertical-blanking bookkeeping: pop and discard any pixels left in
    // pix_fifo from the previous frame during the first 20 blank lines, then
    // flip frame_toggle (which drives the ui_clk-side commit/flush) 25 blank
    // lines before active video resumes -- giving the new scan's data time to
    // clear the pix_fifo prefill threshold before line 0 needs it.
    localparam integer VBLANK_DRAIN_START = HD_ACTIVE_H;         // 1080
    localparam integer VBLANK_DRAIN_END   = HD_ACTIVE_H + 19;    // 1099
    localparam integer FRAME_TOGGLE_LINE  = HD_ACTIVE_H + 19;    // 1099

    reg [11:0] h_cnt;
    reg [10:0] v_cnt;
    reg        hd_de_r, hd_hsync_r, hd_vsync_r;
    reg [19:0] hd_dout_r;
    reg        stream_started;
    reg        frame_valid_meta, frame_valid_sync;
    reg [11:0] dbg_meta, dbg_sync;

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
    wire        vblank_drain_window = (v_cnt >= VBLANK_DRAIN_START[10:0]) && (v_cnt <= VBLANK_DRAIN_END[10:0]);
    wire        frame_toggle_line   = end_line && (v_cnt == FRAME_TOGGLE_LINE[10:0]);

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
            dbg_meta <= 12'd0;
            dbg_sync <= 12'd0;
        end else begin
            pix_rd_en <= 1'b0;

            // CDC: ui_clk frame_valid -> rd_clk
            frame_valid_meta <= frame_valid;
            frame_valid_sync <= frame_valid_meta;
            dbg_meta <= {dbg_beat_overflow, mode_enabled, dbg_pulse_seen, dbg_wpend_seen, dbg_grant_seen,
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

            // Drain any pixels left over from the previous frame's stream
            // (e.g. it starved or a mid-frame flush cut it short) before the
            // next scan's data starts arriving, so a stale pixel can never
            // bleed into the next frame's window.
            if (vblank_drain_window && !pix_empty)
                pix_rd_en <= 1'b1;

            // Flip the commit/flush toggle (seen by the ui_clk side as
            // frame_edge) 25 blank lines before active video resumes, instead
            // of at the true end of frame -- this gives the freshly-started
            // scan time to reach the pix_fifo prefill threshold before line 0.
            if (frame_toggle_line) begin
                frame_toggle   <= ~frame_toggle;
                stream_started <= 1'b0;
            end

            if (cur_sav) begin
                hd_dout_r <= bt1120_trs_word(h_cnt[1:0], 1'b0, cur_vblank, 1'b0);
            end else if (cur_eav) begin
                hd_dout_r <= bt1120_trs_word(cur_eav_idx, 1'b0, cur_vblank, 1'b1);
            end else if (cur_active && dbg_sync[11]) begin
                // Unmistakable full-active-region alarm: a FIFO overflow was
                // detected (should be structurally unreachable after the A1-A3
                // fixes). Placed after SAV/EAV so BT.1120 sync words are never
                // corrupted, but ahead of the window content so it can't be
                // missed. Does not gate on cur_inside_window on purpose.
                hd_dout_r <= {10'd512, 10'd128};
            end else if (cur_inside_window && frame_valid_sync && stream_started && !pix_empty) begin
                // BT.1120 YCbCr 4:2:2: Y on the upper component and the
                // alternating Cb/Cr sample on the lower component.
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

    //------------------------------------------------------------------------
    // Hardware bring-up ILA #2 (2026-07-07, see docs/DDR_EO_PANORAMA_FIX_PLAN.md
    // section 18): clocked on rd_clk (dbg_ila_0 is ui_clk-side only and
    // cannot see this module's internals), to directly answer whether the
    // renderer emits window content at the correct positions and to
    // quantify the in-window underrun "slip" mechanism identified in
    // section 18.2 (any pix_empty while inside the window and streaming
    // permanently displaces the rest of the frame, since the diagnostic-
    // color branch does not pop). Triggers on the starvation event itself
    // (cur_inside_window && pix_empty && stream_started) since that event
    // may be too infrequent for a free-running/other-condition trigger to
    // reliably land inside a 16384-sample window. Temporary bring-up
    // instrumentation -- remove once the geometry question is resolved.
    //------------------------------------------------------------------------
    wire dbg_starve_event = cur_inside_window && pix_empty && stream_started;

    dbg_ila_1 u_dbg_ila_1 (
        .clk     (rd_clk),
        .probe0  (pix_empty),
        .probe1  (pix_rd_en),
        .probe2  (stream_started),
        .probe3  (frame_valid_sync),
        .probe4  (cur_active),
        .probe5  (cur_inside_window),
        .probe6  (h_cnt),
        .probe7  (v_cnt),
        .probe8  (hd_dout_r),
        .probe9  (dbg_sync),
        .probe10 (dbg_starve_event)
    );
endmodule
