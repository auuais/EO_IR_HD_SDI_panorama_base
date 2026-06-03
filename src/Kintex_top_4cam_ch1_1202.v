module Kintex_top_4cam_1ch(
    // FPGA global reset
    input  wire        FPGA_RESET,

    // EO Camera 4
    input  wire        CAM4_PCLK,
    input  wire [7:0]  CAM4_YOUT,
    input  wire [7:0]  CAM4_COUT,
    input  wire        STROBE_OUT0,
    output wire        TRIG_IN4,


    // DEBUG output port (CAM4 기반)
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

assign TRIG_IN4 = STROBE_OUT0;

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
// CAM4 PCLK BUFG
/////////////////////////////////////////////
wire CAM4_PCLK_bufg;

IBUF U_cam4_pclk_ibuf (
    .I(CAM4_PCLK),
    .O(CAM4_PCLK_bufg)
);
//필요하면 BUFG 추가
//BUFG U_cam4_pclk_bufg (
//    .I(CAM4_PCLK_ibufg),
//    .O(CAM4_PCLK_bufg)
//);

/////////////////////////////////////////////
// EO CAMERA data latch 
/////////////////////////////////////////////
reg [7:0] CAM4_YOUT_1d, CAM4_COUT_1d;

always @(posedge CAM4_PCLK_bufg or negedge nRESET) begin
    if (!nRESET) begin
        CAM4_YOUT_1d <= 8'h00;
        CAM4_COUT_1d <= 8'h00;
    end else begin
        CAM4_YOUT_1d <= CAM4_YOUT;
        CAM4_COUT_1d <= CAM4_COUT;
    end
end

/////////////////////////////////////////////
/////////////////////////////////////////////
reg [7:0] cam4_y_d0, cam4_y_d1, cam4_y_d2;

always @(posedge CAM4_PCLK_bufg or negedge nRESET) begin
    if(!nRESET) begin
        cam4_y_d2 <= 8'h00;
        cam4_y_d1 <= 8'h00;
        cam4_y_d0 <= 8'h00;  
    end else begin
        cam4_y_d2 <= cam4_y_d1;
        cam4_y_d1 <= cam4_y_d0;
        cam4_y_d0 <= CAM4_YOUT;  
    end
end

// TRS prefix (FF 00 00)
wire cam4_ff   = (cam4_y_d2 == 8'hFF);
wire cam4_00_1 = (cam4_y_d1 == 8'h00);
wire cam4_00_2 = (cam4_y_d0 == 8'h00);

wire cam4_mkr_fnd = cam4_ff && cam4_00_1 && cam4_00_2;

wire cam4_f_now = CAM4_YOUT[6];
wire cam4_v_now = CAM4_YOUT[5];
wire cam4_h_now = CAM4_YOUT[4];

reg cam4_f_bit, cam4_v_bit, cam4_h_bit;
reg cam4_hsync, cam4_vsync;
//reg cam4_de;
reg cam4_act_video;

wire cam4_sav = cam4_mkr_fnd && (cam4_h_now == 1'b0);
wire cam4_eav = cam4_mkr_fnd && (cam4_h_now == 1'b1);

// HCNT 
reg [11:0] HCNT;

always @(posedge CAM4_PCLK_bufg or negedge nRESET) begin
    if(!nRESET) begin
        cam4_f_bit     <= 1'b0;
        cam4_v_bit     <= 1'b0;
        cam4_h_bit     <= 1'b0;
        cam4_act_video <= 1'b0;
        //cam4_de        <= 1'b0;
        cam4_hsync     <= 1'b0;
        cam4_vsync     <= 1'b0;
        HCNT           <= 12'b0;
    end else begin
        if (cam4_mkr_fnd) begin
            cam4_f_bit <= cam4_f_now;
            cam4_v_bit <= cam4_v_now;
            cam4_h_bit <= cam4_h_now;
        end

        if (cam4_sav)
            cam4_act_video <= 1'b1;   
        else if (cam4_eav)
            cam4_act_video <= 1'b0;   

        if (cam4_eav)
            HCNT <= 12'b0;
        else if (cam4_act_video || cam4_sav)
            HCNT <= HCNT + 12'b1; 

        if (cam4_mkr_fnd) begin
            cam4_hsync <= cam4_h_now;   
            cam4_vsync <= cam4_v_now;
        end
    end
end

wire cam4_hsync1920 = (HCNT > 0 && HCNT < 1921);

/////////////////////////////////////////////
// DEBUG 포트 (CAM4 기준)
/////////////////////////////////////////////
assign IEG0_PCLK  = CAM4_PCLK_bufg;
//assign IEG0_HSYNC = cam4_hsync;
assign IEG0_HSYNC = cam4_hsync1920 & !cam4_vsync;
assign IEG0_VSYNC = cam4_vsync;

// IEG0_DOUT[10]   FPGA_reset으로 jumper
// IEG0_DOUT[0]    SDA, IEG0_DOUT[1]    SCL
//assign IEG0_DOUT  = {
//                   //CAM4_YOUT_1d,        // [19:12] Y data
//                    HCNT[11:0],        // [19:12] Y data
//                    cam4_hsync,          // [7]
//                    cam4_vsync,          // [6]
//                    cam4_sav,            // [5]
//                    cam4_eav,            // [4]
//                    cam4_ff,             // [3]
//                    cam4_00_1,           // [2]
//                    cam4_00_2,           // [1]
//                    cam4_mkr_fnd         // [0]
//                    };
assign IEG0_DOUT  = {CAM4_YOUT_1d,2'b0,CAM4_COUT_1d,2'b0}; 
//assign IEG0_DOUT  = {CAM4_YOUT_1d,2'b0,CAM4_COUT_1d}; 

/////////////////////////////////////////////
// DEBUG 포트 (복사본)
/////////////////////////////////////////////
assign IEG1_PCLK  = CAM4_PCLK_bufg;
assign IEG1_HSYNC = cam4_hsync1920 & !cam4_vsync;
assign IEG1_VSYNC = cam4_vsync;
//assign IEG1_DOUT  = IEG0_DOUT;
assign IEG1_DOUT  = {CAM4_YOUT_1d,2'b0,CAM4_COUT_1d,2'b0}; 

/////////////////////////////////////////////
// EO camera trigger (cam4 only)
/////////////////////////////////////////////

endmodule
