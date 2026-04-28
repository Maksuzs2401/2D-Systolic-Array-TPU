`timescale 1ns / 1ps
`include "config.vh"
module array_PE #(parameter N=`numb)(
    input logic                           clk,
    input logic                           rst_n,
    input logic                           accu_clear,
    
    input  logic signed [`data_width-1:0] a_in    [0:N-1],
    input  logic signed [`data_width-1:0] b_in    [0:N-1],
    input  logic                          valid_in [0:N-1],
    
    output logic signed [`out_width-1:0]  pe_out  [0:N-1][0:N-1]
    );
    
    logic signed [`data_width-1:0]        a_wire [0:N-1][0:N];
    logic signed [`data_width-1:0]        b_wire [0:N][0:N-1];
    logic                                 v_wire [0:N-1][0:N];
    
    genvar i,j;
    generate
        for(i=0;i<N;i++)begin : edge_connect
            assign a_wire[i][0] = a_in[i];  
            assign b_wire[0][i] = b_in[i];    
            assign v_wire[i][0] = valid_in[i];
        end
    endgenerate
    
    generate 
        for(i=0;i<N;i++)begin : row
            for(j=0;j<N;j++) begin : col
                mac_unit pe_inst(
                    .clk(clk),
                    .rst_n(rst_n),
                    .accu_clear(accu_clear),
                    .a_reg(a_wire[i][j]),
                    .a_pass(a_wire[i][j+1]),
                    .b_reg(b_wire[i][j]),
                    .b_pass(b_wire[i+1][j]),
                    .valid_in(v_wire[i][j]),
                    .valid_out(v_wire[i][j+1]),
                    .out(pe_out[i][j])
                );
            end
        end
     endgenerate     
        
endmodule
