`timescale 1ns / 1ps
`include "config.vh"

module axi_wrapp #(parameter N=`numb)(
    input logic                  clk,
    input logic                  rst_n,
    input logic                  s_axis_tvalid,
    input logic signed [15:0]    s_axis_tdata,
    input logic                  s_axis_tlast,
    output logic                 s_axis_tready,
    output logic signed [31:0]   m_axis_tdata,
    output logic                 m_axis_tvalid,
    output logic                 m_axis_tlast,
    input logic                  m_axis_tready
    );
    
    logic [7:0] a_in_array;
    logic [7:0] b_in_array;
    
    assign a_in_array = s_axis_tdata[7:0];
    assign b_in_array = s_axis_tdata[15:8];
    assign s_axis_tready = 1'b1; 
    
    top_wrapper #(.N(N)) top_layer (
        .clk          (clk),
        .rst_n        (rst_n),
        .a_in         (a_in_array),
        .a_valid      (s_axis_tvalid),
        .b_in         (b_in_array),
        .b_valid      (s_axis_tvalid),
        .result       (m_axis_tdata),
        .result_valid (m_axis_tvalid),
        .result_last  (m_axis_tlast)
    );
    
endmodule
