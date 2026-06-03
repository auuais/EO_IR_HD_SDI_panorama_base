module KintexTop_EO_IR_HD_SDI_panorama_base(
    input  wire         CAM0_PCLK,
    input  wire [7:0]   CAM0_YOUT,
    input  wire [7:0]   CAM0_COUT,

    input  wire         CAM1_PCLK,
    input  wire [7:0]   CAM1_YOUT,
    input  wire [7:0]   CAM1_COUT,
    output wire         TRIG_IN1,

    input  wire         CAM2_PCLK,
    input  wire [7:0]   CAM2_YOUT,
    input  wire [7:0]   CAM2_COUT,
    output wire         TRIG_IN2,

    input  wire         CAM3_PCLK,
    input  wire [7:0]   CAM3_YOUT,
    input  wire [7:0]   CAM3_COUT,
    output wire         TRIG_IN3,

    input  wire         CAM4_PCLK,
    input  wire [7:0]   CAM4_YOUT,
    input  wire [7:0]   CAM4_COUT,
    output wire         TRIG_IN4,

    input  wire         CAM5_PCLK,
    input  wire [7:0]   CAM5_YOUT,
    input  wire [7:0]   CAM5_COUT,
    output wire         TRIG_IN5,

    input  wire         STROBE_OUT0,

    input  wire         IRCAM0_PCLK,
    input  wire         IRCAM0_HSYNC,
    input  wire         IRCAM0_VSYNC,
    input  wire [15:0]  IRCAM0_DOUT,
    output wire         IRCAM0_GENLOCK,

    input  wire         IRCAM1_PCLK,
    input  wire         IRCAM1_HSYNC,
    input  wire         IRCAM1_VSYNC,
    input  wire [15:0]  IRCAM1_DOUT,
    output wire         IRCAM1_GENLOCK,

    input  wire         IRCAM2_PCLK,
    input  wire         IRCAM2_HSYNC,
    input  wire         IRCAM2_VSYNC,
    input  wire [15:0]  IRCAM2_DOUT,
    output wire         IRCAM2_GENLOCK,

    input  wire         IRCAM3_PCLK,
    input  wire         IRCAM3_HSYNC,
    input  wire         IRCAM3_VSYNC,
    input  wire [15:0]  IRCAM3_DOUT,
    output wire         IRCAM3_GENLOCK,

    input  wire         IRCAM4_PCLK,
    input  wire         IRCAM4_HSYNC,
    input  wire         IRCAM4_VSYNC,
    input  wire [15:0]  IRCAM4_DOUT,
    output wire         IRCAM4_GENLOCK,

    input  wire         IRCAM5_PCLK,
    input  wire         IRCAM5_HSYNC,
    input  wire         IRCAM5_VSYNC,
    input  wire [15:0]  IRCAM5_DOUT,
    output wire         IRCAM5_GENLOCK,

    output wire         HD_DE,
    output wire         HD_VSYNC,
    output wire         HD_HSYNC,
    output wire         HD_PCLK,
    output wire [19:0]  HD_DOUT,

    output wire         IEG0_PCLK,
    output wire         IEG0_HSYNC,
    output wire         IEG0_VSYNC,
    output wire [19:0]  IEG0_DOUT,

    output wire         IEG1_PCLK,
    output wire         IEG1_HSYNC,
    output wire         IEG1_VSYNC,
    output wire [19:0]  IEG1_DOUT,

    input  wire         SCL,
    inout  wire         SDA,

    input  wire         c0_sys_clk_p,
    input  wire         c0_sys_clk_n,
    output wire [16:0]  c0_ddr4_adr,
    output wire [1:0]   c0_ddr4_ba,
    output wire [0:0]   c0_ddr4_cke,
    output wire [0:0]   c0_ddr4_cs_n,
    inout  wire [7:0]   c0_ddr4_dm_dbi_n,
    inout  wire [63:0]  c0_ddr4_dq,
    inout  wire [7:0]   c0_ddr4_dqs_c,
    inout  wire [7:0]   c0_ddr4_dqs_t,
    output wire [0:0]   c0_ddr4_odt,
    output wire [0:0]   c0_ddr4_bg,
    output wire         c0_ddr4_reset_n,
    output wire         c0_ddr4_act_n,
    output wire [0:0]   c0_ddr4_ck_c,
    output wire [0:0]   c0_ddr4_ck_t
);

    wire nRESET = 1'b1;

    wire CAM0_PCLK_ibuf;
    wire CAM0_PCLK_bufg;
    IBUF u_cam0_pclk_ibuf (.I(CAM0_PCLK), .O(CAM0_PCLK_ibuf));
    BUFG u_cam0_pclk_bufg (.I(CAM0_PCLK_ibuf), .O(CAM0_PCLK_bufg));

    wire [3:0] cam_select_unused;
    wire [7:0] mode_current;
    Kintex_top_I2C_test #(
        .SLAVE_ADDR(7'h36),
        .SCLK_HZ(74_250_000),
        .POR_MS(100)
    ) u_i2c (
        .FPGA_RESET(1'b1),
        .SCLK_IN   (CAM0_PCLK_ibuf),
        .SCL       (SCL),
        .SDA       (SDA),
        .cam_select(cam_select_unused),
        .mode_out  (mode_current)
    );

    localparam FORCE_IR_SLOT_EN = 1'b1;
    localparam [2:0] FORCE_IR_SLOT = 3'd1; // User's IR1 corresponds to slot index 1.

    wire eo_single_mode_active = (mode_current >= 8'h07) && (mode_current <= 8'h0C);
    wire eo_stack_mode_active  = (mode_current == 8'h15);
    wire ir_single_mode_active = (mode_current <= 8'd5) || ((mode_current >= 8'h0D) && (mode_current <= 8'h12));
    wire ir_stack_mode_active  = (mode_current == 8'h14);
    wire processed_mode_active = eo_stack_mode_active || ir_single_mode_active || ir_stack_mode_active;
    wire [2:0] ir_sel_raw = (mode_current <= 8'd5) ? mode_current[2:0] :
                            ((mode_current >= 8'h0D) && (mode_current <= 8'h12)) ? (mode_current - 8'h0D) :
                            3'd0;
    wire [2:0] ir_sel = (FORCE_IR_SLOT_EN && ir_single_mode_active) ? FORCE_IR_SLOT : ir_sel_raw;

    wire [2:0] eo_sel = eo_single_mode_active ? (mode_current - 8'h07) : 3'd0;

    wire        eo0_pclk, eo0_hsync, eo0_vsync;
    wire [19:2] eo0_dout_19_2;
    wire [19:0] eo0_dout = {eo0_dout_19_2, 2'b00};
    wire        eo0_dbg_pclk, eo0_dbg_hsync, eo0_dbg_vsync;
    wire [19:0] eo0_dbg_dout;

    wire        eo1_pclk, eo1_hsync, eo1_vsync;
    wire [19:0] eo1_dout, eo1_dbg_dout;
    wire        eo1_dbg_pclk, eo1_dbg_hsync, eo1_dbg_vsync;

    wire        eo2_pclk, eo2_hsync, eo2_vsync;
    wire [19:0] eo2_dout, eo2_dbg_dout;
    wire        eo2_dbg_pclk, eo2_dbg_hsync, eo2_dbg_vsync;

    wire        eo3_pclk, eo3_hsync, eo3_vsync;
    wire [19:0] eo3_dout, eo3_dbg_dout;
    wire        eo3_dbg_pclk, eo3_dbg_hsync, eo3_dbg_vsync;

    wire        eo4_pclk, eo4_hsync, eo4_vsync;
    wire [19:0] eo4_dout, eo4_dbg_dout;
    wire        eo4_dbg_pclk, eo4_dbg_hsync, eo4_dbg_vsync;

    wire        eo5_pclk, eo5_hsync, eo5_vsync;
    wire [19:0] eo5_dout, eo5_dbg_dout;
    wire        eo5_dbg_pclk, eo5_dbg_hsync, eo5_dbg_vsync;

    Kintex_top_0cam_1ch u_eo0 (
        .FPGA_RESET (nRESET),
        .CAM0_PCLK  (CAM0_PCLK_ibuf),
        .CAM0_YOUT  (CAM0_YOUT),
        .CAM0_COUT  (CAM0_COUT),
        .IEG0_PCLK  (eo0_pclk),
        .IEG0_HSYNC (eo0_hsync),
        .IEG0_VSYNC (eo0_vsync),
        .IEG0_DOUT  (eo0_dout_19_2),
        .IEG1_PCLK  (eo0_dbg_pclk),
        .IEG1_HSYNC (eo0_dbg_hsync),
        .IEG1_VSYNC (eo0_dbg_vsync),
        .IEG1_DOUT  (eo0_dbg_dout)
    );

    Kintex_top_1cam_1ch u_eo1 (
        .FPGA_RESET (nRESET), .CAM1_PCLK(CAM1_PCLK), .CAM1_YOUT(CAM1_YOUT), .CAM1_COUT(CAM1_COUT),
        .STROBE_OUT0(STROBE_OUT0), .TRIG_IN1(TRIG_IN1),
        .IEG0_PCLK(eo1_pclk), .IEG0_HSYNC(eo1_hsync), .IEG0_VSYNC(eo1_vsync), .IEG0_DOUT(eo1_dout),
        .IEG1_PCLK(eo1_dbg_pclk), .IEG1_HSYNC(eo1_dbg_hsync), .IEG1_VSYNC(eo1_dbg_vsync), .IEG1_DOUT(eo1_dbg_dout)
    );
    Kintex_top_2cam_1ch u_eo2 (
        .FPGA_RESET (nRESET), .CAM2_PCLK(CAM2_PCLK), .CAM2_YOUT(CAM2_YOUT), .CAM2_COUT(CAM2_COUT),
        .STROBE_OUT0(STROBE_OUT0), .TRIG_IN2(TRIG_IN2),
        .IEG0_PCLK(eo2_pclk), .IEG0_HSYNC(eo2_hsync), .IEG0_VSYNC(eo2_vsync), .IEG0_DOUT(eo2_dout),
        .IEG1_PCLK(eo2_dbg_pclk), .IEG1_HSYNC(eo2_dbg_hsync), .IEG1_VSYNC(eo2_dbg_vsync), .IEG1_DOUT(eo2_dbg_dout)
    );
    Kintex_top_3cam_1ch u_eo3 (
        .FPGA_RESET (nRESET), .CAM3_PCLK(CAM3_PCLK), .CAM3_YOUT(CAM3_YOUT), .CAM3_COUT(CAM3_COUT),
        .STROBE_OUT0(STROBE_OUT0), .TRIG_IN3(TRIG_IN3),
        .IEG0_PCLK(eo3_pclk), .IEG0_HSYNC(eo3_hsync), .IEG0_VSYNC(eo3_vsync), .IEG0_DOUT(eo3_dout),
        .IEG1_PCLK(eo3_dbg_pclk), .IEG1_HSYNC(eo3_dbg_hsync), .IEG1_VSYNC(eo3_dbg_vsync), .IEG1_DOUT(eo3_dbg_dout)
    );
    Kintex_top_4cam_1ch u_eo4 (
        .FPGA_RESET (nRESET), .CAM4_PCLK(CAM4_PCLK), .CAM4_YOUT(CAM4_YOUT), .CAM4_COUT(CAM4_COUT),
        .STROBE_OUT0(STROBE_OUT0), .TRIG_IN4(TRIG_IN4),
        .IEG0_PCLK(eo4_pclk), .IEG0_HSYNC(eo4_hsync), .IEG0_VSYNC(eo4_vsync), .IEG0_DOUT(eo4_dout),
        .IEG1_PCLK(eo4_dbg_pclk), .IEG1_HSYNC(eo4_dbg_hsync), .IEG1_VSYNC(eo4_dbg_vsync), .IEG1_DOUT(eo4_dbg_dout)
    );
    Kintex_top_5cam_1ch u_eo5 (
        .FPGA_RESET (nRESET), .CAM5_PCLK(CAM5_PCLK), .CAM5_YOUT(CAM5_YOUT), .CAM5_COUT(CAM5_COUT),
        .STROBE_OUT0(STROBE_OUT0), .TRIG_IN5(TRIG_IN5),
        .IEG0_PCLK(eo5_pclk), .IEG0_HSYNC(eo5_hsync), .IEG0_VSYNC(eo5_vsync), .IEG0_DOUT(eo5_dout),
        .IEG1_PCLK(eo5_dbg_pclk), .IEG1_HSYNC(eo5_dbg_hsync), .IEG1_VSYNC(eo5_dbg_vsync), .IEG1_DOUT(eo5_dbg_dout)
    );

    wire eo_sel_pclk_mux = (eo_sel == 3'd0) ? eo0_pclk :
                           (eo_sel == 3'd1) ? eo1_pclk :
                           (eo_sel == 3'd2) ? eo2_pclk :
                           (eo_sel == 3'd3) ? eo3_pclk :
                           (eo_sel == 3'd4) ? eo4_pclk : eo5_pclk;
    wire EO_SEL_PCLK_BUFG;
    BUFG u_eo_sel_pclk_bufg (.I(eo_sel_pclk_mux), .O(EO_SEL_PCLK_BUFG));

    wire        EO_SEL_HSYNC = (eo_sel == 3'd0) ? eo0_hsync :
                               (eo_sel == 3'd1) ? eo1_hsync :
                               (eo_sel == 3'd2) ? eo2_hsync :
                               (eo_sel == 3'd3) ? eo3_hsync :
                               (eo_sel == 3'd4) ? eo4_hsync : eo5_hsync;
    wire        EO_SEL_VSYNC = (eo_sel == 3'd0) ? eo0_vsync :
                               (eo_sel == 3'd1) ? eo1_vsync :
                               (eo_sel == 3'd2) ? eo2_vsync :
                               (eo_sel == 3'd3) ? eo3_vsync :
                               (eo_sel == 3'd4) ? eo4_vsync : eo5_vsync;
    wire [19:0] EO_SEL_DOUT  = (eo_sel == 3'd0) ? eo0_dout :
                               (eo_sel == 3'd1) ? eo1_dout :
                               (eo_sel == 3'd2) ? eo2_dout :
                               (eo_sel == 3'd3) ? eo3_dout :
                               (eo_sel == 3'd4) ? eo4_dout : eo5_dout;
    wire        ddr_calib_done;
    wire        proc_hd_de;
    wire        proc_hd_hsync;
    wire        proc_hd_vsync;
    wire [19:0] proc_hd_dout;
    PanoramaBase_DdrBlackFrame u_ddr_black_frame (
        .rst_n                (nRESET),
        .clk_for_por          (CAM0_PCLK_bufg),
        .rd_clk               (CAM0_PCLK_bufg),
        .ir_single_mode       (ir_single_mode_active),
        .ir_sel               (ir_sel),
        .ir0_wr_clk           (IRCAM0_PCLK),
        .ir0_wr_hsync         (IRCAM0_HSYNC),
        .ir0_wr_vsync         (IRCAM0_VSYNC),
        .ir0_wr_pixel         (IRCAM0_DOUT[13:6]),
        .ir1_wr_clk           (IRCAM1_PCLK),
        .ir1_wr_hsync         (IRCAM1_HSYNC),
        .ir1_wr_vsync         (IRCAM1_VSYNC),
        .ir1_wr_pixel         (IRCAM1_DOUT[13:6]),
        .ir2_wr_clk           (IRCAM2_PCLK),
        .ir2_wr_hsync         (IRCAM2_HSYNC),
        .ir2_wr_vsync         (IRCAM2_VSYNC),
        .ir2_wr_pixel         (IRCAM2_DOUT[13:6]),
        .ir3_wr_clk           (IRCAM3_PCLK),
        .ir3_wr_hsync         (IRCAM3_HSYNC),
        .ir3_wr_vsync         (IRCAM3_VSYNC),
        .ir3_wr_pixel         (IRCAM3_DOUT[13:6]),
        .ir4_wr_clk           (IRCAM4_PCLK),
        .ir4_wr_hsync         (IRCAM4_HSYNC),
        .ir4_wr_vsync         (IRCAM4_VSYNC),
        .ir4_wr_pixel         (IRCAM4_DOUT[13:6]),
        .ir5_wr_clk           (IRCAM5_PCLK),
        .ir5_wr_hsync         (IRCAM5_HSYNC),
        .ir5_wr_vsync         (IRCAM5_VSYNC),
        .ir5_wr_pixel         (IRCAM5_DOUT[13:6]),
        .c0_sys_clk_p         (c0_sys_clk_p),
        .c0_sys_clk_n         (c0_sys_clk_n),
        .c0_ddr4_adr          (c0_ddr4_adr),
        .c0_ddr4_ba           (c0_ddr4_ba),
        .c0_ddr4_cke          (c0_ddr4_cke),
        .c0_ddr4_cs_n         (c0_ddr4_cs_n),
        .c0_ddr4_dm_dbi_n     (c0_ddr4_dm_dbi_n),
        .c0_ddr4_dq           (c0_ddr4_dq),
        .c0_ddr4_dqs_c        (c0_ddr4_dqs_c),
        .c0_ddr4_dqs_t        (c0_ddr4_dqs_t),
        .c0_ddr4_odt          (c0_ddr4_odt),
        .c0_ddr4_bg           (c0_ddr4_bg),
        .c0_ddr4_reset_n      (c0_ddr4_reset_n),
        .c0_ddr4_act_n        (c0_ddr4_act_n),
        .c0_ddr4_ck_c         (c0_ddr4_ck_c),
        .c0_ddr4_ck_t         (c0_ddr4_ck_t),
        .init_calib_complete_o(ddr_calib_done),
        .hd_de                (proc_hd_de),
        .hd_hsync             (proc_hd_hsync),
        .hd_vsync             (proc_hd_vsync),
        .hd_dout              (proc_hd_dout)
    );

    assign HD_PCLK  = eo_single_mode_active ? EO_SEL_PCLK_BUFG : processed_mode_active ? CAM0_PCLK_bufg : 1'b0;
    assign HD_DE    = eo_single_mode_active ? EO_SEL_HSYNC     : processed_mode_active ? proc_hd_de    : 1'b0;
    assign HD_HSYNC = eo_single_mode_active ? EO_SEL_HSYNC     : processed_mode_active ? proc_hd_hsync : 1'b0;
    assign HD_VSYNC = eo_single_mode_active ? EO_SEL_VSYNC     : processed_mode_active ? proc_hd_vsync : 1'b0;
    assign HD_DOUT  = eo_single_mode_active ? EO_SEL_DOUT      : processed_mode_active ? proc_hd_dout  : 20'h0;

    assign IEG0_PCLK  = 1'b0;
    assign IEG0_HSYNC = 1'b0;
    assign IEG0_VSYNC = 1'b0;
    assign IEG0_DOUT  = 20'h0;
    assign IEG1_PCLK  = 1'b0;
    assign IEG1_HSYNC = 1'b0;
    assign IEG1_VSYNC = 1'b0;
    assign IEG1_DOUT  = 20'h0;

    reg sig_60hz;
    localparam integer CLK_HZ        = 74_250_000;
    localparam integer FRAME_HZ_X10  = 600;
    localparam integer PERIOD_CYCLES = (CLK_HZ * 10) / FRAME_HZ_X10;
    localparam integer HIGH_CYCLES   = (PERIOD_CYCLES * 1) / 100;
    localparam integer CW = 22;
    reg [CW-1:0] cnt;

    always @(posedge CAM0_PCLK_bufg or negedge nRESET) begin
        if (!nRESET) begin
            cnt      <= {CW{1'b0}};
            sig_60hz <= 1'b0;
        end else begin
            if (cnt == PERIOD_CYCLES-1)
                cnt <= {CW{1'b0}};
            else
                cnt <= cnt + {{(CW-1){1'b0}}, 1'b1};
            sig_60hz <= (cnt < HIGH_CYCLES[CW-1:0]);
        end
    end

    assign IRCAM0_GENLOCK = sig_60hz;
    assign IRCAM1_GENLOCK = sig_60hz;
    assign IRCAM2_GENLOCK = sig_60hz;
    assign IRCAM3_GENLOCK = sig_60hz;
    assign IRCAM4_GENLOCK = sig_60hz;
    assign IRCAM5_GENLOCK = sig_60hz;

endmodule
