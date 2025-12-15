// Copyright 1986-2017 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2017.4 (win64) Build 2086221 Fri Dec 15 20:55:39 MST 2017
// Date        : Mon Dec 15 16:40:58 2025
// Host        : Thinkbook_16p running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               D:/TH/2026au/FPGA/The-World-Fastest-CNN-Using-FPGA/PE/PE.srcs/sources_1/ip/blk_mem_gen_wgt/blk_mem_gen_wgt_stub.v
// Design      : blk_mem_gen_wgt
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z035ffg676-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_4_1,Vivado 2017.4" *)
module blk_mem_gen_wgt(clka, ena, addra, douta)
/* synthesis syn_black_box black_box_pad_pin="clka,ena,addra[12:0],douta[63:0]" */;
  input clka;
  input ena;
  input [12:0]addra;
  output [63:0]douta;
endmodule
