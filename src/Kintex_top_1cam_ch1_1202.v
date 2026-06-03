
module Kintex_top_1cam_1ch(
    // FPGA global reset
    input  wire        FPGA_RESET,

    // EO Camera 1
    input  wire        CAM1_PCLK,
    input  wire [7:0]  CAM1_YOUT,
    input  wire [7:0]  CAM1_COUT,
    input  wire        STROBE_OUT0,
    output wire        TRIG_IN1,

    // DEBUG output port (CAM1 )
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

assign TRIG_IN1 = STROBE_OUT0;

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
// CAM1 PCLK BUFG 
/////////////////////////////////////////////
wire CAM1_PCLK_bufg;

IBUF U_cam1_pclk_ibuf (
    .I(CAM1_PCLK),
    .O(CAM1_PCLK_bufg)
);
//필요하면 BUFG 추가
//BUFG U_cam1_pclk_bufg (
//    .I(CAM1_PCLK_ibufg),
//    .O(CAM1_PCLK_bufg)
//);

/////////////////////////////////////////////
// EO CAMERA data latch 
/////////////////////////////////////////////
reg [7:0] CAM1_YOUT_1d, CAM1_COUT_1d;

always @(posedge CAM1_PCLK_bufg or negedge nRESET) begin
    if (!nRESET) begin
        CAM1_YOUT_1d <= 8'h00;
        CAM1_COUT_1d <= 8'h00;
    end else begin
        CAM1_YOUT_1d <= CAM1_YOUT;
        CAM1_COUT_1d <= CAM1_COUT;
    end
end

/////////////////////////////////////////////
// BT.1120 TRS(FF 00 00 XY) 검출용 Y 시프트
/////////////////////////////////////////////
reg [7:0] cam1_y_d0, cam1_y_d1, cam1_y_d2;

always @(posedge CAM1_PCLK_bufg or negedge nRESET) begin
    if(!nRESET) begin
        cam1_y_d2 <= 8'h00;
        cam1_y_d1 <= 8'h00;
        cam1_y_d0 <= 8'h00;  
    end else begin
        cam1_y_d2 <= cam1_y_d1;
        cam1_y_d1 <= cam1_y_d0;
        cam1_y_d0 <= CAM1_YOUT;  
    end
end

// TRS prefix (FF 00 00) 검출
wire cam1_ff   = (cam1_y_d2 == 8'hFF);
wire cam1_00_1 = (cam1_y_d1 == 8'h00);
wire cam1_00_2 = (cam1_y_d0 == 8'h00);

wire cam1_mkr_fnd = cam1_ff && cam1_00_1 && cam1_00_2;

wire cam1_f_now = CAM1_YOUT[6];
wire cam1_v_now = CAM1_YOUT[5];
wire cam1_h_now = CAM1_YOUT[4];

reg cam1_f_bit, cam1_v_bit, cam1_h_bit;
reg cam1_hsync, cam1_vsync;
//reg cam1_de;
reg cam1_act_video;

// SAV / EAV  (BT.1120: H=0 SAV, H=1 EAV)
wire cam1_sav = cam1_mkr_fnd && (cam1_h_now == 1'b0);
wire cam1_eav = cam1_mkr_fnd && (cam1_h_now == 1'b1);

// HCNT 
reg [11:0] HCNT;

always @(posedge CAM1_PCLK_bufg or negedge nRESET) begin
    if(!nRESET) begin
        cam1_f_bit     <= 1'b0;
        cam1_v_bit     <= 1'b0;
        cam1_h_bit     <= 1'b0;
        cam1_act_video <= 1'b0;
        //cam1_de        <= 1'b0;
        cam1_hsync     <= 1'b0;
        cam1_vsync     <= 1'b0;
        HCNT           <= 12'b0;
    end else begin
        if (cam1_mkr_fnd) begin
            cam1_f_bit <= cam1_f_now;
            cam1_v_bit <= cam1_v_now;
            cam1_h_bit <= cam1_h_now;
        end

        if (cam1_sav)
            cam1_act_video <= 1'b1;   
        else if (cam1_eav)
            cam1_act_video <= 1'b0;   

        if (cam1_eav)
            HCNT <= 12'b0;
        else if (cam1_act_video || cam1_sav)
            HCNT <= HCNT + 12'b1; 

        if (cam1_mkr_fnd) begin
            cam1_hsync <= cam1_h_now;   
            cam1_vsync <= cam1_v_now;
        end
    end
end

wire cam1_hsync1920 = (HCNT > 0 && HCNT < 1921);

/////////////////////////////////////////////
// DEBUG port (CAM1 )
/////////////////////////////////////////////
assign IEG0_PCLK  = CAM1_PCLK_bufg;
//assign IEG0_HSYNC = cam1_hsync;
assign IEG0_HSYNC = cam1_hsync1920 & !cam1_vsync;
assign IEG0_VSYNC = cam1_vsync;

// IEG0_DOUT[10]   FPGA_reset으로 jumper
// IEG0_DOUT[0]    SDA, IEG0_DOUT[1]    SCL
//assign IEG0_DOUT  = {
//                   //CAM1_YOUT_1d,        // [19:12] Y data
//                    HCNT[11:0],        // [19:12] Y data
//                    cam1_hsync,          // [7]
//                    cam1_vsync,          // [6]
//                    cam1_sav,            // [5]
//                    cam1_eav,            // [4]
//                    cam1_ff,             // [3]
//                    cam1_00_1,           // [2]
//                    cam1_00_2,           // [1]
//                    cam1_mkr_fnd         // [0]
//                    };
assign IEG0_DOUT  = {CAM1_YOUT_1d,2'b0,CAM1_COUT_1d,2'b0}; 
//assign IEG0_DOUT  = {CAM1_YOUT_1d,2'b0,CAM1_COUT_1d}; 

/////////////////////////////////////////////
// DEBUG port  
/////////////////////////////////////////////
assign IEG1_PCLK  = CAM1_PCLK_bufg;
assign IEG1_HSYNC = cam1_hsync1920 & !cam1_vsync;
assign IEG1_VSYNC = cam1_vsync;
//assign IEG1_DOUT  = IEG0_DOUT;
assign IEG1_DOUT  = {CAM1_YOUT_1d,2'b0,CAM1_COUT_1d,2'b0}; 

/////////////////////////////////////////////
// EO camera trigger (cam1 only)
/////////////////////////////////////////////

endmodule
