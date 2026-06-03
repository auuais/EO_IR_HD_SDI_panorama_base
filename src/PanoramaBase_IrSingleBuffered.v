module PanoramaBase_IrSingleBuffered(
    input  wire        rst_n,
    input  wire        rd_clk,
    input  wire [2:0]  single_sel,
    input  wire        cam0_wr_clk,
    input  wire        cam0_wr_hsync,
    input  wire        cam0_wr_vsync,
    input  wire [7:0]  cam0_wr_pixel,
    input  wire        cam1_wr_clk,
    input  wire        cam1_wr_hsync,
    input  wire        cam1_wr_vsync,
    input  wire [7:0]  cam1_wr_pixel,
    input  wire        cam2_wr_clk,
    input  wire        cam2_wr_hsync,
    input  wire        cam2_wr_vsync,
    input  wire [7:0]  cam2_wr_pixel,
    input  wire        cam3_wr_clk,
    input  wire        cam3_wr_hsync,
    input  wire        cam3_wr_vsync,
    input  wire [7:0]  cam3_wr_pixel,
    input  wire        cam4_wr_clk,
    input  wire        cam4_wr_hsync,
    input  wire        cam4_wr_vsync,
    input  wire [7:0]  cam4_wr_pixel,
    input  wire        cam5_wr_clk,
    input  wire        cam5_wr_hsync,
    input  wire        cam5_wr_vsync,
    input  wire [7:0]  cam5_wr_pixel,
    output wire        hd_de,
    output wire        hd_hsync,
    output wire        hd_vsync,
    output wire [19:0] hd_dout
);
    localparam integer SRC_W         = 640;
    localparam integer SRC_H         = 512;
    localparam integer FRAME_ADDR_W  = 19;
    localparam integer READ_LATENCY  = 2;

    localparam integer HD_ACTIVE_W   = 1920;
    localparam integer HD_ACTIVE_H   = 1080;
    localparam integer HD_TOTAL_W    = 2200;
    localparam integer HD_TOTAL_H    = 1125;
    localparam integer SAV_WORDS     = 4;
    localparam integer EAV_WORDS     = 4;
    localparam integer X_OFF         = (HD_ACTIVE_W - SRC_W) / 2;
    localparam integer Y_OFF         = (HD_ACTIVE_H - SRC_H) / 2;

    reg [11:0] h_cnt;
    reg [10:0] v_cnt;
    reg [READ_LATENCY-1:0] use_img_pipe;
    reg [3*READ_LATENCY-1:0] cam_pipe;

    reg        hd_de_r;
    reg        hd_hsync_r;
    reg        hd_vsync_r;
    reg [19:0] hd_dout_r;

    reg [2:0]  next_cam_idx_r;
    reg [9:0]  next_local_x_r;
    reg [8:0]  next_local_y_r;

    wire [7:0] cam0_rd_pixel, cam1_rd_pixel, cam2_rd_pixel;
    wire [7:0] cam3_rd_pixel, cam4_rd_pixel, cam5_rd_pixel;
    wire       cam0_frame_valid, cam1_frame_valid, cam2_frame_valid;
    wire       cam3_frame_valid, cam4_frame_valid, cam5_frame_valid;

    assign hd_de    = hd_de_r;
    assign hd_hsync = hd_hsync_r;
    assign hd_vsync = hd_vsync_r;
    assign hd_dout  = hd_dout_r;

    wire cur_vblank = (v_cnt >= HD_ACTIVE_H);
    wire cur_sav    = (h_cnt < SAV_WORDS);
    wire cur_active = (h_cnt >= SAV_WORDS) && (h_cnt < (SAV_WORDS + HD_ACTIVE_W)) && (v_cnt < HD_ACTIVE_H);
    wire cur_eav    = (h_cnt >= (SAV_WORDS + HD_ACTIVE_W)) &&
                      (h_cnt <  (SAV_WORDS + HD_ACTIVE_W + EAV_WORDS));

    wire end_line   = (h_cnt == HD_TOTAL_W - 1);
    wire end_frame  = end_line && (v_cnt == HD_TOTAL_H - 1);
    wire [11:0] h_next = end_line ? 12'd0 : (h_cnt + 12'd1);
    wire [10:0] v_next = end_line ? (end_frame ? 11'd0 : (v_cnt + 11'd1)) : v_cnt;
    wire next_active = (h_next >= SAV_WORDS) && (h_next < (SAV_WORDS + HD_ACTIVE_W)) && (v_next < HD_ACTIVE_H);
    wire [11:0] next_x = h_next - SAV_WORDS;
    wire [10:0] next_y = v_next;
    wire [1:0]  cur_eav_idx = h_cnt - (SAV_WORDS + HD_ACTIVE_W);
    wire        next_inside_single = next_active &&
                                     (next_x >= X_OFF) && (next_x < (X_OFF + SRC_W)) &&
                                     (next_y >= Y_OFF) && (next_y < (Y_OFF + SRC_H));

    wire [FRAME_ADDR_W-1:0] next_img_addr =
        (next_local_y_r * SRC_W) + next_local_x_r;

    wire selected_frame_valid =
        (next_cam_idx_r == 3'd0) ? cam0_frame_valid :
        (next_cam_idx_r == 3'd1) ? cam1_frame_valid :
        (next_cam_idx_r == 3'd2) ? cam2_frame_valid :
        (next_cam_idx_r == 3'd3) ? cam3_frame_valid :
        (next_cam_idx_r == 3'd4) ? cam4_frame_valid :
                                   cam5_frame_valid;

    wire next_use_img = next_inside_single && selected_frame_valid;

    wire cam0_rd_en = next_use_img && (next_cam_idx_r == 3'd0);
    wire cam1_rd_en = next_use_img && (next_cam_idx_r == 3'd1);
    wire cam2_rd_en = next_use_img && (next_cam_idx_r == 3'd2);
    wire cam3_rd_en = next_use_img && (next_cam_idx_r == 3'd3);
    wire cam4_rd_en = next_use_img && (next_cam_idx_r == 3'd4);
    wire cam5_rd_en = next_use_img && (next_cam_idx_r == 3'd5);

    wire [2:0] cur_cam_idx = cam_pipe[(3*READ_LATENCY)-1 -: 3];
    wire [7:0] sel_pixel =
        (cur_cam_idx == 3'd0) ? cam0_rd_pixel :
        (cur_cam_idx == 3'd1) ? cam1_rd_pixel :
        (cur_cam_idx == 3'd2) ? cam2_rd_pixel :
        (cur_cam_idx == 3'd3) ? cam3_rd_pixel :
        (cur_cam_idx == 3'd4) ? cam4_rd_pixel :
                                cam5_rd_pixel;

    always @* begin
        next_cam_idx_r = single_sel;
        next_local_x_r = 10'd0;
        next_local_y_r = 9'd0;
        if (next_inside_single) begin
            next_local_x_r = next_x - X_OFF;
            next_local_y_r = next_y - Y_OFF;
        end
    end

    function [7:0] bt1120_xy;
        input f_bit;
        input v_bit;
        input h_bit;
        begin
            bt1120_xy = {1'b1,
                         f_bit,
                         v_bit,
                         h_bit,
                         (v_bit ^ h_bit),
                         (f_bit ^ h_bit),
                         (f_bit ^ v_bit),
                         (f_bit ^ v_bit ^ h_bit)};
        end
    endfunction

    function [19:0] bt1120_trs_word;
        input [1:0] idx;
        input       f_bit;
        input       v_bit;
        input       h_bit;
        reg [7:0] xy;
        begin
            xy = bt1120_xy(f_bit, v_bit, h_bit);
            case (idx)
                2'd0: bt1120_trs_word = {10'h3FF, 10'h3FF};
                2'd1: bt1120_trs_word = {10'h000, 10'h000};
                2'd2: bt1120_trs_word = {10'h000, 10'h000};
                default: bt1120_trs_word = {{xy, 2'b00}, {xy, 2'b00}};
            endcase
        end
    endfunction

    IR640x512_GrayFrameBuffer_Single u_cam0_fb (
        .rst_n(rst_n), .wr_clk(cam0_wr_clk), .wr_hsync(cam0_wr_hsync), .wr_vsync(cam0_wr_vsync), .wr_pixel(cam0_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam0_rd_en), .rd_addr(next_img_addr), .rd_pixel(cam0_rd_pixel), .frame_valid(cam0_frame_valid)
    );
    IR640x512_GrayFrameBuffer_Single u_cam1_fb (
        .rst_n(rst_n), .wr_clk(cam1_wr_clk), .wr_hsync(cam1_wr_hsync), .wr_vsync(cam1_wr_vsync), .wr_pixel(cam1_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam1_rd_en), .rd_addr(next_img_addr), .rd_pixel(cam1_rd_pixel), .frame_valid(cam1_frame_valid)
    );
    IR640x512_GrayFrameBuffer_Single u_cam2_fb (
        .rst_n(rst_n), .wr_clk(cam2_wr_clk), .wr_hsync(cam2_wr_hsync), .wr_vsync(cam2_wr_vsync), .wr_pixel(cam2_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam2_rd_en), .rd_addr(next_img_addr), .rd_pixel(cam2_rd_pixel), .frame_valid(cam2_frame_valid)
    );
    IR640x512_GrayFrameBuffer_Single u_cam3_fb (
        .rst_n(rst_n), .wr_clk(cam3_wr_clk), .wr_hsync(cam3_wr_hsync), .wr_vsync(cam3_wr_vsync), .wr_pixel(cam3_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam3_rd_en), .rd_addr(next_img_addr), .rd_pixel(cam3_rd_pixel), .frame_valid(cam3_frame_valid)
    );
    IR640x512_GrayFrameBuffer_Single u_cam4_fb (
        .rst_n(rst_n), .wr_clk(cam4_wr_clk), .wr_hsync(cam4_wr_hsync), .wr_vsync(cam4_wr_vsync), .wr_pixel(cam4_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam4_rd_en), .rd_addr(next_img_addr), .rd_pixel(cam4_rd_pixel), .frame_valid(cam4_frame_valid)
    );
    IR640x512_GrayFrameBuffer_Single u_cam5_fb (
        .rst_n(rst_n), .wr_clk(cam5_wr_clk), .wr_hsync(cam5_wr_hsync), .wr_vsync(cam5_wr_vsync), .wr_pixel(cam5_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam5_rd_en), .rd_addr(next_img_addr), .rd_pixel(cam5_rd_pixel), .frame_valid(cam5_frame_valid)
    );

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            h_cnt       <= 12'd0;
            v_cnt       <= 11'd0;
            use_img_pipe<= {READ_LATENCY{1'b0}};
            cam_pipe    <= {3*READ_LATENCY{1'b0}};
            hd_de_r     <= 1'b0;
            hd_hsync_r  <= 1'b0;
            hd_vsync_r  <= 1'b0;
            hd_dout_r   <= {10'd64, 10'd512};
        end else begin
            use_img_pipe <= {use_img_pipe[READ_LATENCY-2:0], next_use_img};
            cam_pipe     <= {cam_pipe[(3*(READ_LATENCY-1))-1:0], next_cam_idx_r};

            hd_de_r    <= cur_active;
            hd_hsync_r <= cur_active;
            hd_vsync_r <= ~cur_vblank;

            if (cur_sav) begin
                hd_dout_r <= bt1120_trs_word(h_cnt[1:0], 1'b0, cur_vblank, 1'b0);
            end else if (cur_eav) begin
                hd_dout_r <= bt1120_trs_word(cur_eav_idx, 1'b0, cur_vblank, 1'b1);
            end else if (cur_active) begin
                if (use_img_pipe[READ_LATENCY-1])
                    hd_dout_r <= {{sel_pixel, 2'b00}, 10'd512};
                else
                    hd_dout_r <= {10'd64, 10'd512};
            end else begin
                hd_dout_r <= {10'd64, 10'd512};
            end

            h_cnt <= h_next;
            v_cnt <= v_next;
        end
    end
endmodule

module IR640x512_GrayFrameBuffer_Single #(
    parameter integer SRC_W        = 640,
    parameter integer SRC_H        = 512,
    parameter integer FRAME_ADDR_W = 19,
    parameter integer READ_LATENCY = 2
)(
    input  wire                    rst_n,
    input  wire                    wr_clk,
    input  wire                    wr_hsync,
    input  wire                    wr_vsync,
    input  wire [7:0]              wr_pixel,
    input  wire                    rd_clk,
    input  wire                    rd_en,
    input  wire [FRAME_ADDR_W-1:0] rd_addr,
    output wire [7:0]              rd_pixel,
    output reg                     frame_valid,
    output reg                     frame_pulse
);
    localparam integer FRAME_PIXELS = SRC_W * SRC_H;
    localparam integer FRAME_BITS   = FRAME_PIXELS * 8;

    reg [FRAME_ADDR_W-1:0] wr_addr;
    reg                    wr_vsync_d;
    reg                    wr_en;
    reg                    frame_toggle_wr;
    reg                    frame_toggle_meta;
    reg                    frame_toggle_sync;
    reg                    frame_toggle_sync_d;

    always @(posedge wr_clk) begin
        if (!rst_n) begin
            wr_addr         <= {FRAME_ADDR_W{1'b0}};
            wr_vsync_d      <= 1'b0;
            wr_en           <= 1'b0;
            frame_toggle_wr <= 1'b0;
        end else begin
            wr_vsync_d <= wr_vsync;
            wr_en      <= 1'b0;

            if (wr_vsync && !wr_vsync_d)
                wr_addr <= {FRAME_ADDR_W{1'b0}};

            if (wr_vsync && wr_hsync && (wr_addr < FRAME_PIXELS)) begin
                wr_en   <= 1'b1;
                wr_addr <= wr_addr + {{(FRAME_ADDR_W-1){1'b0}}, 1'b1};
            end

            if (!wr_vsync && wr_vsync_d) begin
                if (wr_addr != {FRAME_ADDR_W{1'b0}})
                    frame_toggle_wr <= ~frame_toggle_wr;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            frame_toggle_meta   <= 1'b0;
            frame_toggle_sync   <= 1'b0;
            frame_toggle_sync_d <= 1'b0;
            frame_valid         <= 1'b0;
            frame_pulse         <= 1'b0;
        end else begin
            frame_toggle_meta   <= frame_toggle_wr;
            frame_toggle_sync   <= frame_toggle_meta;
            frame_toggle_sync_d <= frame_toggle_sync;
            frame_pulse <= 1'b0;
            if (frame_toggle_sync != frame_toggle_sync_d) begin
                frame_valid <= 1'b1;
                frame_pulse <= 1'b1;
            end
        end
    end

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A             (FRAME_ADDR_W),
        .ADDR_WIDTH_B             (FRAME_ADDR_W),
        .AUTO_SLEEP_TIME          (0),
        .BYTE_WRITE_WIDTH_A       (8),
        .CLOCKING_MODE            ("independent_clock"),
        .ECC_MODE                 ("no_ecc"),
        .MEMORY_INIT_FILE         ("none"),
        .MEMORY_INIT_PARAM        ("0"),
        .MEMORY_OPTIMIZATION      ("true"),
        .MEMORY_PRIMITIVE         ("block"),
        .MEMORY_SIZE              (FRAME_BITS),
        .MESSAGE_CONTROL          (0),
        .READ_DATA_WIDTH_B        (8),
        .READ_LATENCY_B           (READ_LATENCY),
        .READ_RESET_VALUE_B       ("0"),
        .RST_MODE_B               ("SYNC"),
        .SIM_ASSERT_CHK           (0),
        .USE_EMBEDDED_CONSTRAINT  (0),
        .USE_MEM_INIT             (1),
        .WAKEUP_TIME              ("disable_sleep"),
        .WRITE_DATA_WIDTH_A       (8),
        .WRITE_MODE_B             ("read_first")
    ) u_framebuf (
        .sleep          (1'b0),
        .clka           (wr_clk),
        .ena            (wr_en),
        .wea            (wr_en),
        .addra          (wr_addr),
        .dina           (wr_pixel),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (rd_clk),
        .rstb           (~rst_n),
        .enb            (rd_en),
        .regceb         (1'b1),
        .addrb          (rd_addr),
        .doutb          (rd_pixel),
        .sbiterrb       (),
        .dbiterrb       ()
    );
endmodule
