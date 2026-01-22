`timescale 1ns / 1ps

module top_wrapper (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output wire        done,
    
    // BRAM Interface for Activation Buffer (Slave)
    // Maps to Act Buffer (Bank A and Bank B)
    // Address Map: 0x0000 - 0x0FFF: Bank 0 (4KB)
    //              0x1000 - 0x1FFF: Bank 1 (4KB)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_SIZE 8192, MEM_WIDTH 64, MEM_ECC NONE, READ_WRITE_MODE READ_WRITE" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_ACT CLK" *) input  wire        bram_act_clk,  // Unused, assume synchronous with clk
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_ACT RST" *) input  wire        bram_act_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_ACT EN" *) input  wire        bram_act_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_ACT WE" *) input  wire [7:0]  bram_act_we,   // Byte-write enable
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_ACT ADDR" *) input  wire [12:0] bram_act_addr, // 13 bits for 8KB space (bit12=bank_sel)
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_ACT DIN" *) input  wire [63:0] bram_act_wrdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_ACT DOUT" *) output wire [63:0] bram_act_rddata,
    
    // BRAM Interface for Weight Buffer (Slave)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_SIZE 8192, MEM_WIDTH 64, MEM_ECC NONE, READ_WRITE_MODE READ_WRITE" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_WGT CLK" *) input  wire        bram_wgt_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_WGT RST" *) input  wire        bram_wgt_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_WGT EN" *) input  wire        bram_wgt_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_WGT WE" *) input  wire [7:0]  bram_wgt_we,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_WGT ADDR" *) input  wire [12:0] bram_wgt_addr, // 13 bits for 8KB space
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_WGT DIN" *) input  wire [63:0] bram_wgt_wrdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_WGT DOUT" *) output wire [63:0] bram_wgt_rddata
);

    wire [7:0] ext_act_we = {8{bram_act_en}} & bram_act_we;
    wire [7:0] ext_wgt_we = {8{bram_wgt_en}} & bram_wgt_we;
    
    // Address bit 12 is used for Bank Selection in Activation Buffer
    wire act_bank_sel = bram_act_addr[12];
    
    wire [15:0] ext_act_addr = {4'b0, bram_act_addr[11:0]};

    wire [15:0] ext_wgt_addr = {3'b0, bram_wgt_addr[12:0]} >> 3;

    // DPU Instantiation
    dpu_top u_dpu_top (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        
        // Act Buffer Interface
        .ext_act_bank_sel(act_bank_sel),
        .ext_act_we(ext_act_we),
        .ext_act_addr(ext_act_addr),
        .ext_act_data(bram_act_wrdata),
        .ext_act_rdata(bram_act_rddata),
        
        // Wgt Buffer Interface
        .ext_wgt_we(ext_wgt_we),
        .ext_wgt_addr(ext_wgt_addr),
        .ext_wgt_data(bram_wgt_wrdata),
        .ext_wgt_rdata(bram_wgt_rddata)
    );

endmodule
