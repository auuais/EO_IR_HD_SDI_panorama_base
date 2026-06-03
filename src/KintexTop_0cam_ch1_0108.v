
module Kintex_top_0cam_1ch(
    // FPGA global reset
    input  wire        FPGA_RESET,

    // EO Camera 0
    input  wire        CAM0_PCLK,
    input  wire [7:0]  CAM0_YOUT,
    input  wire [7:0]  CAM0_COUT,

    // HD-SDI 
    //output wire         HD_DE,
    //output wire         HD_VSYNC,
    //output wire         HD_HSYNC,
    //output wire         HD_PCLK,
    //output wire [19:0]  HD_DOUT,


    // DEBUG output port (CAM0 기반)
    output wire        IEG0_PCLK,
    output wire        IEG0_HSYNC,
    output wire        IEG0_VSYNC,
    output wire [19:2] IEG0_DOUT,


    //IEG0_DOUT 0,1 & 10
    output wire        IEG1_PCLK,
    output wire        IEG1_HSYNC,
    output wire        IEG1_VSYNC,
    output wire [19:0] IEG1_DOUT
);

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
// CAM0 PCLK BUFG (현재는 IBUF만 사용)
/////////////////////////////////////////////

wire CAM0_PCLK_bufg = CAM0_PCLK;
/*
wire CAM0_PCLK_bufg;

IBUF U_cam0_pclk_ibuf (
    .I(CAM0_PCLK),
    .O(CAM0_PCLK_bufg)
);
*/

//BUFG U_cam0_pclk_bufg (
//    .I(CAM0_PCLK_ibufg),
//    .O(CAM0_PCLK_bufg)
//);

/////////////////////////////////////////////
// EO CAMERA data latch 
/////////////////////////////////////////////
reg [7:0] CAM0_YOUT_1d, CAM0_COUT_1d;

always @(posedge CAM0_PCLK_bufg or negedge nRESET) begin
    if (!nRESET) begin
        CAM0_YOUT_1d <= 8'h00;
        CAM0_COUT_1d <= 8'h00;
    end else begin
        CAM0_YOUT_1d <= CAM0_YOUT;
        CAM0_COUT_1d <= CAM0_COUT;
    end
end

/////////////////////////////////////////////
// BT.1120 TRS(FF 00 00 XY) 검출용 Y 시프트
/////////////////////////////////////////////
reg [7:0] cam0_y_d0, cam0_y_d1, cam0_y_d2;

always @(posedge CAM0_PCLK_bufg or negedge nRESET) begin
    if(!nRESET) begin
        cam0_y_d2 <= 8'h00;
        cam0_y_d1 <= 8'h00;
        cam0_y_d0 <= 8'h00;  
    end else begin
        cam0_y_d2 <= cam0_y_d1;
        cam0_y_d1 <= cam0_y_d0;
        cam0_y_d0 <= CAM0_YOUT;  
    end
end

// TRS prefix (FF 00 00) 검출
wire cam0_ff   = (cam0_y_d2 == 8'hFF);
wire cam0_00_1 = (cam0_y_d1 == 8'h00);
wire cam0_00_2 = (cam0_y_d0 == 8'h00);

// 현재 클럭에서 TRS 전체(FF 00 00 XY) 완성
// 이 시점의 CAM0_YOUT 값이 XYZ (FVH + parity) 바이트
wire cam0_mkr_fnd = cam0_ff && cam0_00_1 && cam0_00_2;

// 현재 바이트에서 FVH 비트 추출
wire cam0_f_now = CAM0_YOUT[6];
wire cam0_v_now = CAM0_YOUT[5];
wire cam0_h_now = CAM0_YOUT[4];

// 레지스터로 보관할 FVH / sync / DE
reg cam0_f_bit, cam0_v_bit, cam0_h_bit;
reg cam0_hsync, cam0_vsync;
reg cam0_act_video;

// SAV / EAV 신호 (BT.1120: H=0이면 SAV, H=1이면 EAV)
wire cam0_sav = cam0_mkr_fnd && (cam0_h_now == 1'b0);
wire cam0_eav = cam0_mkr_fnd && (cam0_h_now == 1'b1);

// HCNT 
reg [11:0] HCNT;


always @(posedge CAM0_PCLK_bufg or negedge nRESET) begin
    if(!nRESET) begin
        cam0_f_bit     <= 1'b0;
        cam0_v_bit     <= 1'b0;
        cam0_h_bit     <= 1'b0;
        cam0_act_video <= 1'b0;
        cam0_hsync     <= 1'b0;
        cam0_vsync     <= 1'b0;
        HCNT           <= 12'b0;
    end else begin
        // TRS 바이트에서 FVH 레지스터에 저장
        if (cam0_mkr_fnd) begin
            cam0_f_bit <= cam0_f_now;
            cam0_v_bit <= cam0_v_now;
            cam0_h_bit <= cam0_h_now;
        end

        // SAV/EAV에 따라 active video 구간 토글
        if (cam0_sav)
            cam0_act_video <= 1'b1;   // active 시작
        else if (cam0_eav)
            cam0_act_video <= 1'b0;   // active 종료

        if (cam0_eav)
            HCNT <= 12'b0;
        else if (cam0_act_video || cam0_sav)
            HCNT <= HCNT + 12'b1; 

        // HSYNC / VSYNC : TRS 위치에서만 업데이트
        if (cam0_mkr_fnd) begin
            cam0_hsync <= cam0_h_now;   
            cam0_vsync <= cam0_v_now;
        end
    end
end

wire cam0_hsync1920 = (HCNT > 0 && HCNT < 12'd1921);

/////////////////////////////////////////////
// DEBUG 포트 (CAM0 기준)
/////////////////////////////////////////////
assign IEG0_PCLK  = CAM0_PCLK_bufg;
assign IEG0_HSYNC = cam0_hsync1920 & !cam0_vsync;
assign IEG0_VSYNC = cam0_vsync;

//assign IEG0_DOUT  = {CAM0_YOUT_1d, 2'b00, CAM0_COUT_1d, 2'b00}; 
assign IEG0_DOUT  = {CAM0_YOUT_1d, 2'b00, CAM0_COUT_1d}; 

/////////////////////////////////////////////
// DEBUG 포트 (복사본)
/////////////////////////////////////////////
assign IEG1_PCLK  = CAM0_PCLK_bufg;
assign IEG1_HSYNC = cam0_hsync1920 & !cam0_vsync;
assign IEG1_VSYNC = cam0_vsync;
assign IEG1_DOUT  = {CAM0_YOUT_1d, 2'b00, CAM0_COUT_1d, 2'b00}; 
/////////////////////////////////////////////
// 8bit -> 10bit + TRS(3FF/000/000/XYZ) 생성
// HD_DOUT 상위 10bit : Y, 하위 10bit : C
/////////////////////////////////////////////

// 최근 4개 Y/C 샘플 버퍼 (q3: 가장 오래된 값, q0: 가장 최근)
reg [7:0] y_q3, y_q2, y_q1, y_q0;
reg [7:0] c_q3, c_q2, c_q1, c_q0;

// TRS 생성용 상태
reg       trs_active;       // 1이면 현재 3FF/000/000/XYZ 출력 중
reg [1:0] trs_cnt;          // 0~3 : TRS 내에서 워드 위치
reg [7:0] xy_8bit_reg;      // XY(8bit) 저장

reg       trs_active_next;
reg [1:0] trs_cnt_next;
reg [7:0] xy_8bit_next;

reg [9:0] y_10bit_reg, y_10bit_next;
reg [9:0] c_10bit_reg, c_10bit_next;

// TRS 시작 조건 : (q3,q2,q1) = FF,00,00 일 때
wire trs_start = (!trs_active) &&
                 (y_q3 == 8'hFF) &&
                 (y_q2 == 8'h00) &&
                 (y_q1 == 8'h00);

// 다음 상태 및 출력 계산
always @* begin
    // 기본값은 현재 상태 유지 + 8bit->10bit 단순 확장
    trs_active_next = trs_active;
    trs_cnt_next    = trs_cnt;
    xy_8bit_next    = xy_8bit_reg;

    y_10bit_next    = {y_q3, 2'b00};
    c_10bit_next    = {c_q3, 2'b00};

    // TRS 시작
    if (trs_start) begin
        trs_active_next = 1'b1;
        trs_cnt_next    = 2'd0;
        xy_8bit_next    = y_q0;    // q0가 XY 바이트
    end
    else if (trs_active) begin
        if (trs_cnt == 2'd3) begin
            trs_active_next = 1'b0;
            trs_cnt_next    = 2'd0;
        end else begin
            trs_cnt_next    = trs_cnt + 2'd1;
        end
    end

    // TRS 구간이면 3FF / 000 / 000 / (XY<<2) 출력
    if (trs_active_next) begin
        case (trs_cnt_next)
            2'd0: begin
                y_10bit_next = 10'h3FF;
                c_10bit_next = 10'h3FF;
            end
            2'd1: begin
                y_10bit_next = 10'h000;
                c_10bit_next = 10'h000;
            end
            2'd2: begin
                y_10bit_next = 10'h000;
                c_10bit_next = 10'h000;
            end
            2'd3: begin
                // XY 8bit -> 10bit (<<2)
                y_10bit_next = {xy_8bit_next, 2'b00};
                c_10bit_next = {xy_8bit_next, 2'b00};
            end
        endcase
    end
end

// 시퀀셜 파트 : 버퍼, 상태, 출력 레지스터 업데이트
always @(posedge CAM0_PCLK_bufg or negedge nRESET) begin
    if (!nRESET) begin
        y_q3 <= 8'h00; y_q2 <= 8'h00; y_q1 <= 8'h00; y_q0 <= 8'h00;
        c_q3 <= 8'h00; c_q2 <= 8'h00; c_q1 <= 8'h00; c_q0 <= 8'h00;

        trs_active    <= 1'b0;
        trs_cnt       <= 2'd0;
        xy_8bit_reg   <= 8'h00;

        y_10bit_reg   <= 10'h000;
        c_10bit_reg   <= 10'h000;
    end else begin
        // 입력 샘플 버퍼링 (한 클럭마다 1샘플씩 밀어 넣음)
        y_q3 <= y_q2;
        y_q2 <= y_q1;
        y_q1 <= y_q0;
        y_q0 <= CAM0_YOUT_1d;

        c_q3 <= c_q2;
        c_q2 <= c_q1;
        c_q1 <= c_q0;
        c_q0 <= CAM0_COUT_1d;

        // 상태 / 출력 업데이트
        trs_active  <= trs_active_next;
        trs_cnt     <= trs_cnt_next;
        xy_8bit_reg <= xy_8bit_next;

        y_10bit_reg <= y_10bit_next;
        c_10bit_reg <= c_10bit_next;
    end
end

/////////////////////////////////////////////
// HD-SDI 동기 신호 / 데이터 매핑
/////////////////////////////////////////////
//assign HD_DE    = cam0_hsync1920; 
//assign HD_VSYNC = cam0_vsync;
//assign HD_HSYNC = cam0_hsync1920 & !cam0_vsync;
//assign HD_PCLK  = CAM0_PCLK_bufg; 
//assign HD_DOUT  = {y_10bit_reg, c_10bit_reg};

endmodule
