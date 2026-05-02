`timescale 1ns / 1ps
`include "config.vh"
module top_wrapper #(parameter N=`numb)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic signed [`data_width-1:0]a_in[0:N-1],
    input  logic                         a_valid,
    input  logic signed [`data_width-1:0]b_in[0:N-1],
    input  logic                         b_valid,
    input  logic                         out_ready,
    output logic signed [`accu_width-1:0]result[0:N-1],
    output logic                         result_valid,
    output logic                         result_last,
    output logic                         in_ready
    );
    
    logic signed [7:0]  a_row     [0:N-1];
    logic signed [7:0]  b_col     [0:N-1];
    logic               valid_out [0:N-1];
    logic               load;
    logic signed [`accu_width-1:0] pe_out    [0:N-1][0:N-1];
    logic signed [`accu_width-1:0] result_buf[0:N-1][0:N-1];
    logic                          buf_valid;
    logic                          accu_clear_sig; 
    
    buffer_net #(.N(N))buffer_inst(
        .clk(clk),.rst_n(rst_n),
        .a_in(a_in),.b_in(b_in),.a_valid(a_valid),.b_valid(b_valid),
        .a_row(a_row),.b_col(b_col),.valid_out(valid_out),
        .load(load),.ready(in_ready)
    );
    
    array_PE #(.N(N)) array_inst(
        .clk(clk),.rst_n(rst_n),
        .accu_clear(accu_clear_sig),.a_in(a_row),.b_in(b_col),
        .valid_in(valid_out),.pe_out(pe_out)
    );
    
    output_stage #(.N(N)) output_inst (
        .clk(clk),.rst_n(rst_n),
        .start(load),.pe_out(pe_out),.result(result_buf),
        .accu_clear (accu_clear_sig),.res_valid(buf_valid)
    );
    
   array_piso #(.N(N)) serial_data (
        .clk(clk), .rst_n(rst_n),
        .in_data(result_buf),.in_valid(buf_valid),.out_data(result),
        .out_valid(result_valid),.out_last(result_last),
        .out_ready(out_ready)
   );
    
endmodule
