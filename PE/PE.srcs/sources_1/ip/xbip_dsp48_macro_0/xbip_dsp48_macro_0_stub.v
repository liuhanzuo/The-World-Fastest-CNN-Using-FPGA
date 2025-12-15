// Copyright 1986-2017 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2017.4 (win64) Build 2086221 Fri Dec 15 20:55:39 MST 2017
// Date        : Mon Dec 15 15:45:06 2025
// Host        : Thinkbook_16p running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/TH/2026au/FPGA/The-World-Fastest-CNN-Using-FPGA/PE/PE.srcs/sources_1/ip/xbip_dsp48_macro_0/xbip_dsp48_macro_0_stub.v
// Design      : xbip_dsp48_macro_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z035ffg676-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "xbip_dsp48_macro_v3_0_15,Vivado 2017.4" *)
module xbip_dsp48_macro_0(CLK, A, B, C, P)
/* synthesis syn_black_box black_box_pad_pin="CLK,A[7:0],B[7:0],C[31:0],P[31:0]" */;
  input CLK;
  input [7:0]A;
  input [7:0]B;
  input [31:0]C;
  output [31:0]P;
endmodule
