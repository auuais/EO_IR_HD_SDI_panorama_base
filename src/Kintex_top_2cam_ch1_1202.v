module Kintex_top_2cam_1ch(
    // FPGA global reset
    input  wire        FPGA_RESET,

    // EO Camera 2
    input  wire        CAM2_PCLK,
    input  wire [7:0]  CAM2_YOUT,
    input  wire [7:0]  CAM2_COUT,
    input  wire        STROBE_OUT0,
    output wire        TRIG_IN2,

    // DEBUG output port (CAM2 기반)
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

assign TRIG_IN2 = STROBE_OUT0;

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
// CAM2 PCLK BUFG 
/////////////////////////////////////////////
wire CAM2_PCLK_bufg;

IBUF U_cam2_pclk_ibuf (
    .I(CAM2_PCLK),
    .O(CAM2_PCLK_bufg)
);
//BUFG U_cam2_pclk_bufg (
//    .I(CAM2_PCLK_ibufg),
//    .O(CAM2_PCLK_bufg)
//);

/////////////////////////////////////////////
// EO CAMERA data latch 
/////////////////////////////////////////////
reg [7:0] CAM2_YOUT_1d, CAM2_COUT_1d;

always @(posedge CAM2_PCLK_bufg or negedge nRESET) begin
    if (!nRESET) begin
        CAM2_YOUT_1d <= 8'h00;
        CAM2_COUT_1d <= 8'h00;
    end else begin
        CAM2_YOUT_1d <= CAM2_YOUT;
        CAM2_COUT_1d <= CAM2_COUT;
    end
end

/////////////////////////////////////////////
// BT.1120 TRS(FF 00 00 XY)
/////////////////////////////////////////////
reg [7:0] cam2_y_d0, cam2_y_d1, cam2_y_d2;

always @(posedge CAM2_PCLK_bufg or negedge nRESET) begin
    if(!nRESET) begin
        cam2_y_d2 <= 8'h00;
        cam2_y_d1 <= 8'h00;
        cam2_y_d0 <= 8'h00;  
    end else begin
        cam2_y_d2 <= cam2_y_d1;
        cam2_y_d1 <= cam2_y_d0;
        cam2_y_d0 <= CAM2_YOUT;  
    end
end

// TRS prefix (FF 00 00) 
wire cam2_ff   = (cam2_y_d2 == 8'hFF);
wire cam2_00_1 = (cam2_y_d1 == 8'h00);
wire cam2_00_2 = (cam2_y_d0 == 8'h00);

wire cam2_mkr_fnd = cam2_ff && cam2_00_1 && cam2_00_2;

wire cam2_f_now = CAM2_YOUT[6];
wire cam2_v_now = CAM2_YOUT[5];
wire cam2_h_now = CAM2_YOUT[4];

reg cam2_f_bit, cam2_v_bit, cam2_h_bit;
reg cam2_hsync, cam2_vsync;
//reg cam2_de;
reg cam2_act_video;

wire cam2_sav = cam2_mkr_fnd && (cam2_h_now == 1'b0);
wire cam2_eav = cam2_mkr_fnd && (cam2_h_now == 1'b1);

// HCNT 
reg [11:0] HCNT;

always @(posedge CAM2_PCLK_bufg or negedge nRESET) begin
    if(!nRESET) begin
        cam2_f_bit     <= 1'b0;
        cam2_v_bit     <= 1'b0;
        cam2_h_bit     <= 1'b0;
        cam2_act_video <= 1'b0;
        //cam2_de        <= 1'b0;
        cam2_hsync     <= 1'b0;
        cam2_vsync     <= 1'b0;
        HCNT           <= 12'b0;
    end else begin
        if (cam2_mkr_fnd) begin
            cam2_f_bit <= cam2_f_now;
            cam2_v_bit <= cam2_v_now;
            cam2_h_bit <= cam2_h_now;
        end

        if (cam2_sav)
            cam2_act_video <= 1'b1;   
        else if (cam2_eav)
            cam2_act_video <= 1'b0;   

        if (cam2_eav)
            HCNT <= 12'b0;
        else if (cam2_act_video || cam2_sav)
            HCNT <= HCNT + 12'b1; 

        if (cam2_mkr_fnd) begin
            cam2_hsync <= cam2_h_now;   
            cam2_vsync <= cam2_v_now;
        end
    end
end

wire cam2_hsync1920 = (HCNT > 0 && HCNT < 1921);

assign IEG0_PCLK  = CAM2_PCLK_bufg;
assign IEG0_HSYNC = cam2_hsync1920 & !cam2_vsync;
assign IEG0_VSYNC = cam2_vsync;

// IEG0_DOUT[10]   FPGA_reset으로 jumper
// IEG0_DOUT[0]    SDA, IEG0_DOUT[1]    SCL
//assign IEG0_DOUT  = {
//                   //CAM2_YOUT_1d,        // [19:12] Y data
//                    HCNT[11:0],        // [19:12] Y data
//                    cam2_hsync,          // [7]
//                    cam2_vsync,          // [6]
//                    cam2_sav,            // [5]
//                    cam2_eav,            // [4]
//                    cam2_ff,             // [3]
//                    cam2_00_1,           // [2]
//                    cam2_00_2,           // [1]
//                    cam2_mkr_fnd         // [0]
//                    };
assign IEG0_DOUT  = {CAM2_YOUT_1d,2'b0,CAM2_COUT_1d,2'b0}; 
//assign IEG0_DOUT  = {CAM2_YOUT_1d,2'b0,CAM2_COUT_1d}; 

/////////////////////////////////////////////
// DEBUG 
/////////////////////////////////////////////
assign IEG1_PCLK  = CAM2_PCLK_bufg;
assign IEG1_HSYNC = cam2_hsync1920 & !cam2_vsync;
assign IEG1_VSYNC = cam2_vsync;
//assign IEG1_DOUT  = IEG0_DOUT;
assign IEG1_DOUT  = {CAM2_YOUT_1d,2'b0,CAM2_COUT_1d,2'b0}; 

/////////////////////////////////////////////
// EO camera trigger (cam2 only)
/////////////////////////////////////////////

endmodule
