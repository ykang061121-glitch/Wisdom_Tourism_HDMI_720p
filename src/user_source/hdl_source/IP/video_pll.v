// Independent experiment only. C0 is the external BUFG feedback, NOT pixel.
module video_pll_720p(input refclk,reset,output pixel_clk,serial_clk,locked);
 wire [4:0] clocks;
 wire feedback;
 EG_LOGIC_BUFG feedback_buf(.i(clocks[0]),.o(feedback));
 assign pixel_clk=clocks[1];
 assign serial_clk=clocks[2];
 EG_PHY_PLL #(.FIN("50.000000"),.FEEDBK_MODE("NORMAL"),.FEEDBK_PATH("CLKC0_EXT"),
  .PLLRST_ENA("ENABLE"),.REFCLK_DIV(20),.FBCLK_DIV(99),
  .CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(3),.CLKC0_CPHASE(2),.CLKC0_FPHASE(0),
  .CLKC1_ENABLE("ENABLE"),.CLKC1_DIV(10),.CLKC1_CPHASE(9),.CLKC1_FPHASE(0),
  .CLKC2_ENABLE("ENABLE"),.CLKC2_DIV(2),.CLKC2_CPHASE(1),.CLKC2_FPHASE(0),
  .CLKC3_ENABLE("DISABLE"),.CLKC4_ENABLE("DISABLE")) pll_inst(
  .refclk(refclk),.reset(reset),.fbclk(feedback),.clkc(clocks),.extlock(locked),
  .stdby(1'b0),.load_reg(5'b0),.psclk(1'b0),.psdown(1'b0),.psstep(1'b0),
  .psclksel(3'b0),.psdone(),.\do (),.dclk(1'b0),.dcs(1'b0),.dwe(1'b0),.di(8'b0),.daddr(6'b0));
endmodule

module video_pll(input refclk,reset,output clk0_out,clk1_out);
wire locked;
video_pll_720p candidate(refclk,reset,clk0_out,clk1_out,locked);
endmodule

