module PanoramaBase_DdrBringupStub(
    input  wire        clk_for_por,
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
    reg [23:0] por_cnt = 24'd0;
    reg        ready = 1'b0;

    always @(posedge clk_for_por) begin
        if (!ready) begin
            por_cnt <= por_cnt + 24'd1;
            if (&por_cnt[23:22])
                ready <= 1'b1;
        end
    end

    always @(posedge clk_for_por) begin
        if (!ready)
            status_code_o <= 2'd1;
        else
            status_code_o <= 2'd2;
    end

    assign init_calib_complete_o = ready;

    // Hold the external DDR devices inactive for startup-isolation testing.
    assign c0_ddr4_adr      = 17'd0;
    assign c0_ddr4_ba       = 2'd0;
    assign c0_ddr4_cke      = 1'b0;
    assign c0_ddr4_cs_n     = 1'b1;
    assign c0_ddr4_odt      = 1'b0;
    assign c0_ddr4_bg       = 1'b0;
    assign c0_ddr4_reset_n  = 1'b0;
    assign c0_ddr4_act_n    = 1'b1;
    assign c0_ddr4_ck_c     = 1'b0;
    assign c0_ddr4_ck_t     = 1'b0;
    assign c0_ddr4_dm_dbi_n = {8{1'bz}};
    assign c0_ddr4_dq       = {64{1'bz}};
    assign c0_ddr4_dqs_c    = {8{1'bz}};
    assign c0_ddr4_dqs_t    = {8{1'bz}};
endmodule
