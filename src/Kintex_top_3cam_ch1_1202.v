module Kintex_top_3cam_1ch(
    // FPGA global reset
    input  wire        FPGA_RESET,

    // EO Camera 3
    input  wire        CAM3_PCLK,
    input  wire [7:0]  CAM3_YOUT,
    input  wire [7:0]  CAM3_COUT,
    input  wire        STROBE_OUT0,
    output wire        TRIG_IN3,

    output wire        IEG0_PCLK,
    output wire        IEG0_HSYNC,
    output wire        IEG0_VSYNC,
    output wire [19:0] IEG0_DOUT,

    //IEG0_DOUT 0,1 & 10
    output wire        IEG1_PCLK,
    output wire        IEG1_HSYNC,
    output wire        IEG1_VSYNC,
    output wire [19:0] IEG1_DOUT
);
assign TRIG_IN3 = STROBE_OUT0;
/////////////////////////////////////////////
// Reset buffer
/////////////////////////////////////////////
wire nRESET = 1'b1;
//wire nRESET;
//IBUF U_RESET_bufg (
//   .I(FPGA_RESET),
//   .O(nRESET)
//);

/////////////////////////////////////////////
// CAM3 PCLK BUFG
/////////////////////////////////////////////
wire CAM3_PCLK_bufg;

IBUF U_cam3_pclk_ibuf (
    .I(CAM3_PCLK),
    .O(CAM3_PCLK_bufg)
);
//필요하면 BUFG 추가
//BUFG U_cam3_pclk_bufg (
//    .I(CAM3_PCLK_ibufg),
//    .O(CAM3_PCLK_bufg)
//);

/////////////////////////////////////////////
// EO CAMERA data latch 
/////////////////////////////////////////////
reg [7:0] CAM3_YOUT_1d, CAM3_COUT_1d;

always @(posedge CAM3_PCLK_bufg or negedge nRESET) begin
    if (!nRESET) begin
        CAM3_YOUT_1d <= 8'h00;
        CAM3_COUT_1d <= 8'h00;
    end else begin
        CAM3_YOUT_1d <= CAM3_YOUT;
        CAM3_COUT_1d <= CAM3_COUT;
    end
end

/////////////////////////////////////////////
// BT.1120 TRS(FF 00 00 XY)
/////////////////////////////////////////////
reg [7:0] cam3_y_d0, cam3_y_d1, cam3_y_d2;

always @(posedge CAM3_PCLK_bufg or negedge nRESET) begin
    if(!nRESET) begin
        cam3_y_d2 <= 8'h00;
        cam3_y_d1 <= 8'h00;
        cam3_y_d0 <= 8'h00;  
    end else begin
        cam3_y_d2 <= cam3_y_d1;
        cam3_y_d1 <= cam3_y_d0;
        cam3_y_d0 <= CAM3_YOUT;  
    end
end

// TRS prefix (FF 00 00) 
wire cam3_ff   = (cam3_y_d2 == 8'hFF);
wire cam3_00_1 = (cam3_y_d1 == 8'h00);
wire cam3_00_2 = (cam3_y_d0 == 8'h00);

wire cam3_mkr_fnd = cam3_ff && cam3_00_1 && cam3_00_2;

wire cam3_f_now = CAM3_YOUT[6];
wire cam3_v_now = CAM3_YOUT[5];
wire cam3_h_now = CAM3_YOUT[4];

reg cam3_f_bit, cam3_v_bit, cam3_h_bit;
reg cam3_hsync, cam3_vsync;
reg cam3_act_video;

wire cam3_sav = cam3_mkr_fnd && (cam3_h_now == 1'b0);
wire cam3_eav = cam3_mkr_fnd && (cam3_h_now == 1'b1);

reg [11:0] HCNT;

always @(posedge CAM3_PCLK_bufg or negedge nRESET) begin
    if(!nRESET) begin
        cam3_f_bit     <= 1'b0;
        cam3_v_bit     <= 1'b0;
        cam3_h_bit     <= 1'b0;
        cam3_act_video <= 1'b0;
        //cam3_de        <= 1'b0;
        cam3_hsync     <= 1'b0;
        cam3_vsync     <= 1'b0;
        HCNT           <= 12'b0;
    end else begin
        if (cam3_mkr_fnd) begin
            cam3_f_bit <= cam3_f_now;
            cam3_v_bit <= cam3_v_now;
            cam3_h_bit <= cam3_h_now;
        end

        if (cam3_sav)
            cam3_act_video <= 1'b1;   // active 시작
        else if (cam3_eav)
            cam3_act_video <= 1'b0;   // active 종료

        if (cam3_eav)
            HCNT <= 12'b0;
        else if (cam3_act_video || cam3_sav)
            HCNT <= HCNT + 12'b1; 

        if (cam3_mkr_fnd) begin
            cam3_hsync <= cam3_h_now;   // 필요시 여기서 폴라리티 반전
            cam3_vsync <= cam3_v_now;
        end
    end
end

wire cam3_hsync1920 = (HCNT > 0 && HCNT < 1921);

/////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////
assign IEG0_PCLK  = CAM3_PCLK_bufg;
//assign IEG0_HSYNC = cam3_hsync;
assign IEG0_HSYNC = cam3_hsync1920 & !cam3_vsync;
assign IEG0_VSYNC = cam3_vsync;

// IEG0_DOUT[10]   FPGA_reset으로 jumper
// IEG0_DOUT[0]    SDA, IEG0_DOUT[1]    SCL
//assign IEG0_DOUT  = {
//                   //CAM3_YOUT_1d,        // [19:12] Y data
//                    HCNT[11:0],        // [19:12] Y data
//                    cam3_hsync,          // [7]
//                    cam3_vsync,          // [6]
//                    cam3_sav,            // [5]
//                    cam3_eav,            // [4]
//                    cam3_ff,             // [3]
//                    cam3_00_1,           // [2]
//                    cam3_00_2,           // [1]
//                    cam3_mkr_fnd         // [0]
//                    };
assign IEG0_DOUT  = {CAM3_YOUT_1d,2'b0,CAM3_COUT_1d,2'b0}; 
//assign IEG0_DOUT  = {CAM3_YOUT_1d,2'b0,CAM3_COUT_1d}; 

/////////////////////////////////////////////
// DEBUG 포트 (복사본)
/////////////////////////////////////////////
assign IEG1_PCLK  = CAM3_PCLK_bufg;
assign IEG1_HSYNC = cam3_hsync1920 & !cam3_vsync;
assign IEG1_VSYNC = cam3_vsync;
//assign IEG1_DOUT  = IEG0_DOUT;
assign IEG1_DOUT  = {CAM3_YOUT_1d,2'b0,CAM3_COUT_1d,2'b0}; 

/////////////////////////////////////////////
// EO camera trigger (cam3 only)
/////////////////////////////////////////////

endmodule
