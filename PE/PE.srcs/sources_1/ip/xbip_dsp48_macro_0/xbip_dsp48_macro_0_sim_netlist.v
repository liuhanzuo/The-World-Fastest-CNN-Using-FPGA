// Copyright 1986-2017 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2017.4 (win64) Build 2086221 Fri Dec 15 20:55:39 MST 2017
// Date        : Mon Dec 15 15:45:06 2025
// Host        : Thinkbook_16p running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               d:/TH/2026au/FPGA/The-World-Fastest-CNN-Using-FPGA/PE/PE.srcs/sources_1/ip/xbip_dsp48_macro_0/xbip_dsp48_macro_0_sim_netlist.v
// Design      : xbip_dsp48_macro_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z035ffg676-2
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "xbip_dsp48_macro_0,xbip_dsp48_macro_v3_0_15,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "xbip_dsp48_macro_v3_0_15,Vivado 2017.4" *) 
(* NotValidForBitStream *)
module xbip_dsp48_macro_0
   (CLK,
    A,
    B,
    C,
    P);
  (* x_interface_info = "xilinx.com:signal:clock:1.0 clk_intf CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME clk_intf, ASSOCIATED_BUSIF p_intf:pcout_intf:carrycascout_intf:carryout_intf:bcout_intf:acout_intf:concat_intf:d_intf:c_intf:b_intf:a_intf:bcin_intf:acin_intf:pcin_intf:carryin_intf:carrycascin_intf:sel_intf, ASSOCIATED_RESET SCLR:SCLRD:SCLRA:SCLRB:SCLRCONCAT:SCLRC:SCLRM:SCLRP:SCLRSEL, ASSOCIATED_CLKEN CE:CED:CED1:CED2:CED3:CEA:CEA1:CEA2:CEA3:CEA4:CEB:CEB1:CEB2:CEB3:CEB4:CECONCAT:CECONCAT3:CECONCAT4:CECONCAT5:CEC:CEC1:CEC2:CEC3:CEC4:CEC5:CEM:CEP:CESEL:CESEL1:CESEL2:CESEL3:CESEL4:CESEL5, FREQ_HZ 100000000, PHASE 0.000" *) input CLK;
  (* x_interface_info = "xilinx.com:signal:data:1.0 a_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME a_intf, LAYERED_METADATA undef" *) input [7:0]A;
  (* x_interface_info = "xilinx.com:signal:data:1.0 b_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME b_intf, LAYERED_METADATA undef" *) input [7:0]B;
  (* x_interface_info = "xilinx.com:signal:data:1.0 c_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME c_intf, LAYERED_METADATA undef" *) input [31:0]C;
  (* x_interface_info = "xilinx.com:signal:data:1.0 p_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME p_intf, LAYERED_METADATA undef" *) output [31:0]P;

  wire [7:0]A;
  wire [7:0]B;
  wire [31:0]C;
  wire CLK;
  wire [31:0]P;
  wire NLW_U0_CARRYCASCOUT_UNCONNECTED;
  wire NLW_U0_CARRYOUT_UNCONNECTED;
  wire [29:0]NLW_U0_ACOUT_UNCONNECTED;
  wire [17:0]NLW_U0_BCOUT_UNCONNECTED;
  wire [47:0]NLW_U0_PCOUT_UNCONNECTED;

  (* C_A_WIDTH = "8" *) 
  (* C_B_WIDTH = "8" *) 
  (* C_CONCAT_WIDTH = "48" *) 
  (* C_CONSTANT_1 = "1" *) 
  (* C_C_WIDTH = "32" *) 
  (* C_D_WIDTH = "18" *) 
  (* C_HAS_A = "1" *) 
  (* C_HAS_ACIN = "0" *) 
  (* C_HAS_ACOUT = "0" *) 
  (* C_HAS_B = "1" *) 
  (* C_HAS_BCIN = "0" *) 
  (* C_HAS_BCOUT = "0" *) 
  (* C_HAS_C = "1" *) 
  (* C_HAS_CARRYCASCIN = "0" *) 
  (* C_HAS_CARRYCASCOUT = "0" *) 
  (* C_HAS_CARRYIN = "0" *) 
  (* C_HAS_CARRYOUT = "0" *) 
  (* C_HAS_CE = "0" *) 
  (* C_HAS_CEA = "0" *) 
  (* C_HAS_CEB = "0" *) 
  (* C_HAS_CEC = "0" *) 
  (* C_HAS_CECONCAT = "0" *) 
  (* C_HAS_CED = "0" *) 
  (* C_HAS_CEM = "0" *) 
  (* C_HAS_CEP = "0" *) 
  (* C_HAS_CESEL = "0" *) 
  (* C_HAS_CONCAT = "0" *) 
  (* C_HAS_D = "0" *) 
  (* C_HAS_INDEP_CE = "0" *) 
  (* C_HAS_INDEP_SCLR = "0" *) 
  (* C_HAS_PCIN = "0" *) 
  (* C_HAS_PCOUT = "0" *) 
  (* C_HAS_SCLR = "0" *) 
  (* C_HAS_SCLRA = "0" *) 
  (* C_HAS_SCLRB = "0" *) 
  (* C_HAS_SCLRC = "0" *) 
  (* C_HAS_SCLRCONCAT = "0" *) 
  (* C_HAS_SCLRD = "0" *) 
  (* C_HAS_SCLRM = "0" *) 
  (* C_HAS_SCLRP = "0" *) 
  (* C_HAS_SCLRSEL = "0" *) 
  (* C_LATENCY = "-1" *) 
  (* C_MODEL_TYPE = "0" *) 
  (* C_OPMODES = "000000000011010100000000" *) 
  (* C_P_LSB = "1" *) 
  (* C_P_MSB = "32" *) 
  (* C_REG_CONFIG = "00000000000011100011100011000100" *) 
  (* C_SEL_WIDTH = "0" *) 
  (* C_TEST_CORE = "0" *) 
  (* C_VERBOSITY = "0" *) 
  (* C_XDEVICEFAMILY = "zynq" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  xbip_dsp48_macro_0_xbip_dsp48_macro_v3_0_15 U0
       (.A(A),
        .ACIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .ACOUT(NLW_U0_ACOUT_UNCONNECTED[29:0]),
        .B(B),
        .BCIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .BCOUT(NLW_U0_BCOUT_UNCONNECTED[17:0]),
        .C(C),
        .CARRYCASCIN(1'b0),
        .CARRYCASCOUT(NLW_U0_CARRYCASCOUT_UNCONNECTED),
        .CARRYIN(1'b0),
        .CARRYOUT(NLW_U0_CARRYOUT_UNCONNECTED),
        .CE(1'b1),
        .CEA(1'b1),
        .CEA1(1'b1),
        .CEA2(1'b1),
        .CEA3(1'b1),
        .CEA4(1'b1),
        .CEB(1'b1),
        .CEB1(1'b1),
        .CEB2(1'b1),
        .CEB3(1'b1),
        .CEB4(1'b1),
        .CEC(1'b1),
        .CEC1(1'b1),
        .CEC2(1'b1),
        .CEC3(1'b1),
        .CEC4(1'b1),
        .CEC5(1'b1),
        .CECONCAT(1'b1),
        .CECONCAT3(1'b1),
        .CECONCAT4(1'b1),
        .CECONCAT5(1'b1),
        .CED(1'b1),
        .CED1(1'b1),
        .CED2(1'b1),
        .CED3(1'b1),
        .CEM(1'b1),
        .CEP(1'b1),
        .CESEL(1'b1),
        .CESEL1(1'b1),
        .CESEL2(1'b1),
        .CESEL3(1'b1),
        .CESEL4(1'b1),
        .CESEL5(1'b1),
        .CLK(CLK),
        .CONCAT({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .D({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .P(P),
        .PCIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .PCOUT(NLW_U0_PCOUT_UNCONNECTED[47:0]),
        .SCLR(1'b0),
        .SCLRA(1'b0),
        .SCLRB(1'b0),
        .SCLRC(1'b0),
        .SCLRCONCAT(1'b0),
        .SCLRD(1'b0),
        .SCLRM(1'b0),
        .SCLRP(1'b0),
        .SCLRSEL(1'b0),
        .SEL(1'b0));
endmodule

(* C_A_WIDTH = "8" *) (* C_B_WIDTH = "8" *) (* C_CONCAT_WIDTH = "48" *) 
(* C_CONSTANT_1 = "1" *) (* C_C_WIDTH = "32" *) (* C_D_WIDTH = "18" *) 
(* C_HAS_A = "1" *) (* C_HAS_ACIN = "0" *) (* C_HAS_ACOUT = "0" *) 
(* C_HAS_B = "1" *) (* C_HAS_BCIN = "0" *) (* C_HAS_BCOUT = "0" *) 
(* C_HAS_C = "1" *) (* C_HAS_CARRYCASCIN = "0" *) (* C_HAS_CARRYCASCOUT = "0" *) 
(* C_HAS_CARRYIN = "0" *) (* C_HAS_CARRYOUT = "0" *) (* C_HAS_CE = "0" *) 
(* C_HAS_CEA = "0" *) (* C_HAS_CEB = "0" *) (* C_HAS_CEC = "0" *) 
(* C_HAS_CECONCAT = "0" *) (* C_HAS_CED = "0" *) (* C_HAS_CEM = "0" *) 
(* C_HAS_CEP = "0" *) (* C_HAS_CESEL = "0" *) (* C_HAS_CONCAT = "0" *) 
(* C_HAS_D = "0" *) (* C_HAS_INDEP_CE = "0" *) (* C_HAS_INDEP_SCLR = "0" *) 
(* C_HAS_PCIN = "0" *) (* C_HAS_PCOUT = "0" *) (* C_HAS_SCLR = "0" *) 
(* C_HAS_SCLRA = "0" *) (* C_HAS_SCLRB = "0" *) (* C_HAS_SCLRC = "0" *) 
(* C_HAS_SCLRCONCAT = "0" *) (* C_HAS_SCLRD = "0" *) (* C_HAS_SCLRM = "0" *) 
(* C_HAS_SCLRP = "0" *) (* C_HAS_SCLRSEL = "0" *) (* C_LATENCY = "-1" *) 
(* C_MODEL_TYPE = "0" *) (* C_OPMODES = "000000000011010100000000" *) (* C_P_LSB = "1" *) 
(* C_P_MSB = "32" *) (* C_REG_CONFIG = "00000000000011100011100011000100" *) (* C_SEL_WIDTH = "0" *) 
(* C_TEST_CORE = "0" *) (* C_VERBOSITY = "0" *) (* C_XDEVICEFAMILY = "zynq" *) 
(* ORIG_REF_NAME = "xbip_dsp48_macro_v3_0_15" *) (* downgradeipidentifiedwarnings = "yes" *) 
module xbip_dsp48_macro_0_xbip_dsp48_macro_v3_0_15
   (CLK,
    CE,
    SCLR,
    SEL,
    CARRYCASCIN,
    CARRYIN,
    PCIN,
    ACIN,
    BCIN,
    A,
    B,
    C,
    D,
    CONCAT,
    ACOUT,
    BCOUT,
    CARRYOUT,
    CARRYCASCOUT,
    PCOUT,
    P,
    CED,
    CED1,
    CED2,
    CED3,
    CEA,
    CEA1,
    CEA2,
    CEA3,
    CEA4,
    CEB,
    CEB1,
    CEB2,
    CEB3,
    CEB4,
    CECONCAT,
    CECONCAT3,
    CECONCAT4,
    CECONCAT5,
    CEC,
    CEC1,
    CEC2,
    CEC3,
    CEC4,
    CEC5,
    CEM,
    CEP,
    CESEL,
    CESEL1,
    CESEL2,
    CESEL3,
    CESEL4,
    CESEL5,
    SCLRD,
    SCLRA,
    SCLRB,
    SCLRCONCAT,
    SCLRC,
    SCLRM,
    SCLRP,
    SCLRSEL);
  input CLK;
  input CE;
  input SCLR;
  input [0:0]SEL;
  input CARRYCASCIN;
  input CARRYIN;
  input [47:0]PCIN;
  input [29:0]ACIN;
  input [17:0]BCIN;
  input [7:0]A;
  input [7:0]B;
  input [31:0]C;
  input [17:0]D;
  input [47:0]CONCAT;
  output [29:0]ACOUT;
  output [17:0]BCOUT;
  output CARRYOUT;
  output CARRYCASCOUT;
  output [47:0]PCOUT;
  output [31:0]P;
  input CED;
  input CED1;
  input CED2;
  input CED3;
  input CEA;
  input CEA1;
  input CEA2;
  input CEA3;
  input CEA4;
  input CEB;
  input CEB1;
  input CEB2;
  input CEB3;
  input CEB4;
  input CECONCAT;
  input CECONCAT3;
  input CECONCAT4;
  input CECONCAT5;
  input CEC;
  input CEC1;
  input CEC2;
  input CEC3;
  input CEC4;
  input CEC5;
  input CEM;
  input CEP;
  input CESEL;
  input CESEL1;
  input CESEL2;
  input CESEL3;
  input CESEL4;
  input CESEL5;
  input SCLRD;
  input SCLRA;
  input SCLRB;
  input SCLRCONCAT;
  input SCLRC;
  input SCLRM;
  input SCLRP;
  input SCLRSEL;

  wire [7:0]A;
  wire [29:0]ACIN;
  wire [29:0]ACOUT;
  wire [7:0]B;
  wire [17:0]BCIN;
  wire [17:0]BCOUT;
  wire [31:0]C;
  wire CARRYCASCIN;
  wire CARRYCASCOUT;
  wire CARRYIN;
  wire CARRYOUT;
  wire CLK;
  wire [31:0]P;
  wire [47:0]PCIN;
  wire [47:0]PCOUT;

  (* C_A_WIDTH = "8" *) 
  (* C_B_WIDTH = "8" *) 
  (* C_CONCAT_WIDTH = "48" *) 
  (* C_CONSTANT_1 = "1" *) 
  (* C_C_WIDTH = "32" *) 
  (* C_D_WIDTH = "18" *) 
  (* C_HAS_A = "1" *) 
  (* C_HAS_ACIN = "0" *) 
  (* C_HAS_ACOUT = "0" *) 
  (* C_HAS_B = "1" *) 
  (* C_HAS_BCIN = "0" *) 
  (* C_HAS_BCOUT = "0" *) 
  (* C_HAS_C = "1" *) 
  (* C_HAS_CARRYCASCIN = "0" *) 
  (* C_HAS_CARRYCASCOUT = "0" *) 
  (* C_HAS_CARRYIN = "0" *) 
  (* C_HAS_CARRYOUT = "0" *) 
  (* C_HAS_CE = "0" *) 
  (* C_HAS_CEA = "0" *) 
  (* C_HAS_CEB = "0" *) 
  (* C_HAS_CEC = "0" *) 
  (* C_HAS_CECONCAT = "0" *) 
  (* C_HAS_CED = "0" *) 
  (* C_HAS_CEM = "0" *) 
  (* C_HAS_CEP = "0" *) 
  (* C_HAS_CESEL = "0" *) 
  (* C_HAS_CONCAT = "0" *) 
  (* C_HAS_D = "0" *) 
  (* C_HAS_INDEP_CE = "0" *) 
  (* C_HAS_INDEP_SCLR = "0" *) 
  (* C_HAS_PCIN = "0" *) 
  (* C_HAS_PCOUT = "0" *) 
  (* C_HAS_SCLR = "0" *) 
  (* C_HAS_SCLRA = "0" *) 
  (* C_HAS_SCLRB = "0" *) 
  (* C_HAS_SCLRC = "0" *) 
  (* C_HAS_SCLRCONCAT = "0" *) 
  (* C_HAS_SCLRD = "0" *) 
  (* C_HAS_SCLRM = "0" *) 
  (* C_HAS_SCLRP = "0" *) 
  (* C_HAS_SCLRSEL = "0" *) 
  (* C_LATENCY = "-1" *) 
  (* C_MODEL_TYPE = "0" *) 
  (* C_OPMODES = "000000000011010100000000" *) 
  (* C_P_LSB = "1" *) 
  (* C_P_MSB = "32" *) 
  (* C_REG_CONFIG = "00000000000011100011100011000100" *) 
  (* C_SEL_WIDTH = "0" *) 
  (* C_TEST_CORE = "0" *) 
  (* C_VERBOSITY = "0" *) 
  (* C_XDEVICEFAMILY = "zynq" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  xbip_dsp48_macro_0_xbip_dsp48_macro_v3_0_15_viv i_synth
       (.A(A),
        .ACIN(ACIN),
        .ACOUT(ACOUT),
        .B(B),
        .BCIN(BCIN),
        .BCOUT(BCOUT),
        .C(C),
        .CARRYCASCIN(CARRYCASCIN),
        .CARRYCASCOUT(CARRYCASCOUT),
        .CARRYIN(CARRYIN),
        .CARRYOUT(CARRYOUT),
        .CE(1'b0),
        .CEA(1'b0),
        .CEA1(1'b0),
        .CEA2(1'b0),
        .CEA3(1'b0),
        .CEA4(1'b0),
        .CEB(1'b0),
        .CEB1(1'b0),
        .CEB2(1'b0),
        .CEB3(1'b0),
        .CEB4(1'b0),
        .CEC(1'b0),
        .CEC1(1'b0),
        .CEC2(1'b0),
        .CEC3(1'b0),
        .CEC4(1'b0),
        .CEC5(1'b0),
        .CECONCAT(1'b0),
        .CECONCAT3(1'b0),
        .CECONCAT4(1'b0),
        .CECONCAT5(1'b0),
        .CED(1'b0),
        .CED1(1'b0),
        .CED2(1'b0),
        .CED3(1'b0),
        .CEM(1'b0),
        .CEP(1'b0),
        .CESEL(1'b0),
        .CESEL1(1'b0),
        .CESEL2(1'b0),
        .CESEL3(1'b0),
        .CESEL4(1'b0),
        .CESEL5(1'b0),
        .CLK(CLK),
        .CONCAT({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .D({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .P(P),
        .PCIN(PCIN),
        .PCOUT(PCOUT),
        .SCLR(1'b0),
        .SCLRA(1'b0),
        .SCLRB(1'b0),
        .SCLRC(1'b0),
        .SCLRCONCAT(1'b0),
        .SCLRD(1'b0),
        .SCLRM(1'b0),
        .SCLRP(1'b0),
        .SCLRSEL(1'b0),
        .SEL(1'b0));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2015"
`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="cds_rsa_key", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=64)
`pragma protect key_block
nBlnHi3Kp5ztG6vZNdMONLkWpVVpg2r7ZP2rdZEfioM4XUkRew1oDSrAozd60ivTx8PLiOPPRAJo
pOZd0llK5g==

`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
Kcs1MQe5BgqnN7tbrZMcEiZZSCl175bCFWu5jwqWj4RFDG/n9GjuiwAuZ9v2vQZcAxVE3h5w+TBc
Bk1lc9zc7T3tnbm4qpXepckPAqiTqMURQNO28XRRz5BSiTktDkY/dUGVSA0qxTdPGlkYZSpuFpl6
PjievZtLxEtp4cSEwJE=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
aG1w9h5Ae0N98iRQuCMUHQUwBA2KqP2Fbb/SCJOtosbKahOePVIWiIrkhbLMsr1/omYs/Q6fEj2G
uYHIEBLZLRANmjJt9kQu/jIzWAf0nK3OJkUCAMefyflw5y403PkpWIAHXqlArlaCVW2gWxzVxt9G
js0j3l7Y2dpahAMg2LgLgWyMj2rS0kjr+fbTwgci9As5Ndo6CDyXo7EcixOTvkWvqwxJaYFbtcFF
K1j0WC1jYCLSiEJ2ZB5/ODVnSmn3AWSksydgQ3iYMKpYPNlAwFN7t7HacZ95HxO8MGoNyjnDje35
EzrNZrAA4vUP8Y6En1JgkF6RLt8PJJfLc+wq+g==

`pragma protect key_keyowner="ATRENTA", key_keyname="ATR-SG-2015-RSA-3", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
BYWKn+AL7Gth8aEXuzL+rpOrNP6Ug8Hc9TpmOLZLrPZ4boPFPd89qpRHOY6mfox3M09mZK4TuSx+
5DykxgtH7Gu2DHCqtg3Tg7eFTAzurR/EqXoPhuHQIzs5Y1T/5WlIb0c4l9CNWdc5TBVfbmKR+x4N
A259tw/6q69OtmAqFiB+p9GY8lyjNDWu07DJlxI2l6wSRYy8YqD7K1OrLRXxY6gaTqDWDXlcO+ia
T5/harPHjTiNAFO8U6YTfRQtNJUrOnNfSAnAtjrlegYGNcEl6u4sqYE/X/Pajk2n+1+KvJ6PR8L9
bdrCByV81f1z88nc1Twl6LUe54VQdfe5W+EOpQ==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2017_05", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
iJnLIMkUEl7Btn7IVUeqK6xbyk9c7fsISctkfj2c6osS1GvgHXWHkJPpNPHTeIth7zUvkUlYB/Jd
M5kNK3leJJj5TaqOLOh+cyWqEGY64EruHImVJasbLaVn3LUh67wEEMFoKhP9/KjqLsL3oFrKnU4i
JzYtVgZoCfaHBaIyRC6wms7z/YKP2Khya0dzmYHMmbdm9k2rL27fVLJcCEMSO1Dsz2D/qXnCFI8T
NHnM3Fv/xF2jOhtDIDqWGakvXk7l+ddg95MJ+5A578jqVX81M0WJwbHlaIJIG5uwIzTI46+pYw0Z
4sgDMkrl/aXSFYB5PU2L4hhVeq7e6c0dqUOVSw==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
sdiBszQspScY+UIwuaohSbs1PAZL6bemuOZlFLGklUXNsz7r1265PlclnSy9m0ilIWxY0HJkGEtl
Rs/zfRlF9Ag/CEiBQ4lStxiXa4cbOvNwkp9j1BXCYCAbMsw83x+ZvpyoQTXRfcBBvSAbtpFDJ7ar
qlJbO6erRjpDP373GIY=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
eUV1ae8Aw6l0UtyVDuKmrMQwdVI8vrJTYSKwNJ+/x3fs7qy5B2fVzNE8tFRcie7NykwBpJV9lQNN
iNNcReVBjS/oh7txKer0RVLuw2jQCeQBSixWXwdIra9CsrIF5V2GUuY3dDh9ofaqsgbKSlDNLzzm
0lHhjAw4Nbk9kwoo5NP9xZYaLPCNo4Qqi0A9Px++Zu3V7DcbPDDDQnNEzgQhcN8ilscDyGVOeiHu
/xJbo1lLkpyrDciztvHYqwj9O/kSyF1PikDg8xEaOx1QQVvaz7r51DlXlPCpqCUyFGEeiIrPCMHf
8rf7t9DpvBEVPF3eaofCDfiW9vWmbfgffwtMYg==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
iKHTgmUeg4yonqdxEGY0srQ4jdr6Nv1U7QS83GI1K40lc8zd1YbXajES4WZGd96ILkHrPFeUOP0g
q3tJAAdXoW9EZprqW+3sZdYw09paDiSSRtiJ3TYvFTGM2CGFxyp2HbOYNQh42j7u3VbVbVo7YXUG
cxaqmdZ0Mcjd0ZPTfaHvPITfMuXAZuN1k+08p4KFqeq2OiaBZqH7GZYNlOSV9dU7fOrlQtvTevIi
CMwgnltTJfYKf7LleRhErCb9rngTwvrhLpqIo2b/S7/Fq6o4FOyovRejBjcIfR0etw7D+8ijDe9p
yGml360QtZoN9FUE4SIIGOENmeOZ0Sev14BBBQ==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
OJjDLrbtmTicZbA82g9VzUHcgJHdsvSIHB0AFK2PDKoeMcdtxi4o0DNNuOa6JwebXsCkhS+0zUZY
S5XFsHgV84Cs9srWTxhOE+qOkPLSrECKrgjJgpK8Agr1uQhnJAP24RW1J4o0ex9hGvJLX7YI40Se
rDEe8Zjx9wyNXn3egPRqsT5m9OJRbByE+pFCL7R9jWjGfsULkr85x2douFtCXxdNKBStqP3wgrje
t/IzLzS5rL2IavRf1Hxb430G/UsaAAh3x1ISvpRcW2olLpgmDp8gHiWY5Kbq+v+ZrvENUBZoAbr9
zilUhhL2BbqIlpxno0jvqV3DlKI2aBFu5hQlMg==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 55968)
`pragma protect data_block
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
`pragma protect end_protected
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

endmodule
`endif
