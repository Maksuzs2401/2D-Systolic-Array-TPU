`timescale 1ns / 1ps
`include "config.vh"

module mac_unit (
    input logic                           clk,
    input logic                           rst_n,
    input logic signed [`data_width-1:0]  a_reg,
    input logic signed [`data_width-1:0]  b_reg,
    input logic                           accu_clear,
    input logic                           valid_in,
    output logic signed [`out_width-1:0]  out,
    output logic signed [`data_width-1:0] a_pass,   
    output logic signed [`data_width-1:0] b_pass,
    output logic                          valid_out
);
    
    (* use_dsp = "yes" *) logic signed [`prod_width-1:0]    prod_res;
    logic signed [`accu_width-1:0]    accu_reg;
    
    always_comb begin
        prod_res = a_reg * b_reg;
    end
    
    always_ff @(posedge clk)begin
        if(!rst_n || accu_clear)begin 
            accu_reg <= 0;
        end
        else if(valid_in) begin
            accu_reg <= accu_reg + prod_res;
        end
    end
    
    always_ff @(posedge clk) begin
    if (!rst_n) begin
        a_pass <= 0;
        b_pass <= 0;
    end else begin
        a_pass <= a_reg;   
        b_pass <= b_reg;  
        valid_out <= valid_in;
        end
    end
    
    assign out = accu_reg;
endmodule
