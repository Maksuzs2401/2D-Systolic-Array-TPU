`timescale 1ns / 1ps
`include "config.vh"

module axi_wrapp #(parameter N=`numb)(
    input logic                              clk,
    input logic                              rst_n,
    input logic                              s_axis_tvalid,
    input logic signed [`data_in_width-1:0]  s_axis_tdata,
    input logic                              s_axis_tlast,
    output logic                             s_axis_tready,
    output logic signed [`data_out_width-1:0]m_axis_tdata,
    output logic                             m_axis_tvalid,
    output logic                             m_axis_tlast,
    input logic                              m_axis_tready
    );
    
    logic signed [`data_width-1:0] a_in_array[0:N-1];
    logic signed [`data_width-1:0] b_in_array[0:N-1];
    
    genvar i;
    generate 
        for(i=0;i<N;i++)begin : unpacking
            assign a_in_array[i]=s_axis_tdata[i*`data_width +:`data_width];
            assign b_in_array[i] = s_axis_tdata[N*`data_width + i*`data_width +: `data_width];
        end
    endgenerate
        
    logic signed [`accu_width-1:0]result_out[0:N-1];
    
    generate
        for (i = 0; i < N; i++) begin : pack
            assign m_axis_tdata[i*`accu_width +: `accu_width] = result_out[i];
        end
    endgenerate
    
    assign s_axis_tready = 1'b1;
    
    top_wrapper #(.N(N)) top_layer (
        .clk          (clk),
        .rst_n        (rst_n),
        .a_in         (a_in_array),
        .a_valid      (s_axis_tvalid),
        .b_in         (b_in_array),
        .b_valid      (s_axis_tvalid),
        .out_ready    (m_axis_tready),
        .result       (result_out),
        .result_valid (m_axis_tvalid),
        .result_last  (m_axis_tlast),
        .in_ready     (s_axis_tready)
    );
    
endmodule
