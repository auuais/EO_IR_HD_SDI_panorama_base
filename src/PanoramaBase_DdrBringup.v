module PanoramaBase_DdrBringup(
    input  wire        clk_for_por,
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
    output reg  [1:0]  status_code_o
);
    localparam [511:0] TEST_PATTERN = {
        64'h0123456789ABCDEF,
        64'h0011223344556677,
        64'h89ABCDEF01234567,
        64'h0F1E2D3C4B5A6978,
        64'hFEDCBA9876543210,
        64'h7766554433221100,
        64'h13579BDF2468ACE0,
        64'h55AA55AA55AA55AA
    };

    localparam [2:0]
        ST_WAIT_CAL = 3'd0,
        ST_ISSUE_WR = 3'd1,
        ST_ISSUE_RD = 3'd2,
        ST_WAIT_RD  = 3'd3,
        ST_PASS     = 3'd4,
        ST_FAIL     = 3'd5;

    reg [19:0] por_cnt = 20'd0;
    reg        sys_rst = 1'b1;
    always @(posedge clk_for_por) begin
        if (!sys_rst) begin
            por_cnt <= por_cnt;
        end else begin
            por_cnt <= por_cnt + 20'd1;
            if (&por_cnt[19:18])
                sys_rst <= 1'b0;
        end
    end

    wire        c0_init_calib_complete;
    wire        dbg_clk;
    wire [511:0] dbg_bus;
    wire        c0_ddr4_ui_clk;
    wire        c0_ddr4_ui_clk_sync_rst;
    reg         c0_ddr4_app_en;
    reg         c0_ddr4_app_hi_pri;
    reg         c0_ddr4_app_wdf_end;
    reg         c0_ddr4_app_wdf_wren;
    wire        c0_ddr4_app_rd_data_end;
    wire        c0_ddr4_app_rd_data_valid;
    wire        c0_ddr4_app_rdy;
    wire        c0_ddr4_app_wdf_rdy;
    reg  [28:0] c0_ddr4_app_addr;
    reg  [2:0]  c0_ddr4_app_cmd;
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

    reg [2:0] state;
    always @(posedge c0_ddr4_ui_clk) begin
        if (c0_ddr4_ui_clk_sync_rst) begin
            state <= ST_WAIT_CAL;
            status_code_o <= 2'd0;
            c0_ddr4_app_en <= 1'b0;
            c0_ddr4_app_hi_pri <= 1'b0;
            c0_ddr4_app_wdf_end <= 1'b0;
            c0_ddr4_app_wdf_wren <= 1'b0;
            c0_ddr4_app_addr <= 29'd0;
            c0_ddr4_app_cmd <= 3'd0;
            c0_ddr4_app_wdf_data <= TEST_PATTERN;
            c0_ddr4_app_wdf_mask <= 64'd0;
        end else begin
            c0_ddr4_app_en <= 1'b0;
            c0_ddr4_app_hi_pri <= 1'b0;
            c0_ddr4_app_wdf_end <= 1'b0;
            c0_ddr4_app_wdf_wren <= 1'b0;
            c0_ddr4_app_addr <= 29'd0;
            c0_ddr4_app_cmd <= 3'd0;
            c0_ddr4_app_wdf_data <= TEST_PATTERN;
            c0_ddr4_app_wdf_mask <= 64'd0;
            case (state)
                ST_WAIT_CAL: begin
                    status_code_o <= 2'd0;
                    if (c0_init_calib_complete) begin
                        state <= ST_ISSUE_WR;
                        status_code_o <= 2'd1;
                    end
                end
                ST_ISSUE_WR: begin
                    status_code_o <= 2'd1;
                    if (c0_ddr4_app_rdy && c0_ddr4_app_wdf_rdy) begin
                        c0_ddr4_app_en <= 1'b1;
                        c0_ddr4_app_cmd <= 3'b000;
                        c0_ddr4_app_wdf_wren <= 1'b1;
                        c0_ddr4_app_wdf_end <= 1'b1;
                        state <= ST_ISSUE_RD;
                    end
                end
                ST_ISSUE_RD: begin
                    status_code_o <= 2'd1;
                    if (c0_ddr4_app_rdy) begin
                        c0_ddr4_app_en <= 1'b1;
                        c0_ddr4_app_cmd <= 3'b001;
                        state <= ST_WAIT_RD;
                    end
                end
                ST_WAIT_RD: begin
                    status_code_o <= 2'd1;
                    if (c0_ddr4_app_rd_data_valid) begin
                        if (c0_ddr4_app_rd_data == TEST_PATTERN) begin
                            state <= ST_PASS;
                            status_code_o <= 2'd2;
                        end else begin
                            state <= ST_FAIL;
                            status_code_o <= 2'd3;
                        end
                    end
                end
                ST_PASS: begin
                    status_code_o <= 2'd2;
                end
                default: begin
                    status_code_o <= 2'd3;
                end
            endcase
        end
    end
endmodule

module PanoramaBase_StatusSync(
    input  wire       src_clk,
    input  wire [1:0] src_status,
    output reg  [1:0] dst_status
);
    reg [1:0] sync1;
    always @(posedge src_clk) begin
        sync1 <= src_status;
        dst_status <= sync1;
    end
endmodule

module PanoramaBase_HdStatusRenderer(
    input  wire        rst_n,
    input  wire        rd_clk,
    input  wire [1:0]  status,
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

    reg [11:0] h_cnt;
    reg [10:0] v_cnt;
    reg        hd_de_r;
    reg        hd_hsync_r;
    reg        hd_vsync_r;
    reg [19:0] hd_dout_r;

    assign hd_de = hd_de_r;
    assign hd_hsync = hd_hsync_r;
    assign hd_vsync = hd_vsync_r;
    assign hd_dout = hd_dout_r;

    wire cur_vblank = (v_cnt >= HD_ACTIVE_H);
    wire cur_sav    = (h_cnt < SAV_WORDS);
    wire cur_active = (h_cnt >= SAV_WORDS) && (h_cnt < (SAV_WORDS + HD_ACTIVE_W)) && (v_cnt < HD_ACTIVE_H);
    wire cur_eav    = (h_cnt >= (SAV_WORDS + HD_ACTIVE_W)) && (h_cnt < (SAV_WORDS + HD_ACTIVE_W + EAV_WORDS));
    wire end_line   = (h_cnt == HD_TOTAL_W - 1);
    wire end_frame  = end_line && (v_cnt == HD_TOTAL_H - 1);
    wire [11:0] h_next = end_line ? 12'd0 : (h_cnt + 12'd1);
    wire [10:0] v_next = end_line ? (end_frame ? 11'd0 : (v_cnt + 11'd1)) : v_cnt;
    wire [1:0]  cur_eav_idx = h_cnt - (SAV_WORDS + HD_ACTIVE_W);

    function [7:0] bt1120_xy;
        input f_bit;
        input v_bit;
        input h_bit;
        begin
            bt1120_xy = {1'b1, f_bit, v_bit, h_bit,
                         (f_bit ^ v_bit),
                         (f_bit ^ h_bit),
                         (v_bit ^ h_bit),
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

    reg [9:0] y_word;
    always @* begin
        case (status)
            2'd0: y_word = 10'd128 + {2'b00, h_cnt[9:2]};
            2'd1: y_word = (h_cnt[7] ^ v_cnt[6]) ? 10'd768 : 10'd256;
            2'd2: y_word = 10'd896;
            default: y_word = (h_cnt[6] ^ v_cnt[6]) ? 10'd64 : 10'd896;
        endcase
    end

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            h_cnt     <= 12'd0;
            v_cnt     <= 11'd0;
            hd_de_r   <= 1'b0;
            hd_hsync_r<= 1'b0;
            hd_vsync_r<= 1'b0;
            hd_dout_r <= {10'd64, 10'd512};
        end else begin
            hd_de_r    <= cur_active;
            hd_hsync_r <= cur_active;
            hd_vsync_r <= ~cur_vblank;

            if (cur_sav)
                hd_dout_r <= bt1120_trs_word(h_cnt[1:0], 1'b0, cur_vblank, 1'b0);
            else if (cur_eav)
                hd_dout_r <= bt1120_trs_word(cur_eav_idx, 1'b0, cur_vblank, 1'b1);
            else if (cur_active)
                hd_dout_r <= {y_word, 10'd512};
            else
                hd_dout_r <= {10'd64, 10'd512};

            h_cnt <= h_next;
            v_cnt <= v_next;
        end
    end
endmodule
