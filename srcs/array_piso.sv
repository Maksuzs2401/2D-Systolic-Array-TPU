`timescale 1ns / 1ps
`include "config.vh"
module array_piso #(parameter N=`numb)(
    
    input logic                   clk,
    input logic                   rst_n,
    input logic signed [31:0]     in_data[0:N-1][0:N-1],
    input logic                   in_valid,
    output logic       [31:0]     out_data,
    output logic                  out_last,
    output logic                  out_valid
    

    );
    
    logic [$clog2(N)-1:0] row_cnt;
    logic [$clog2(N)-1:0] col_cnt;
    logic signed [31:0] buff_reg[0:N-1][0:N-1];
    logic is_sending;
    logic valid_d;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_data   <= 0;
            out_valid  <= 1'b0;
            is_sending <= 1'b0;
            row_cnt    <= 0;
            col_cnt    <= 0;
            valid_d <= 1'b0;
        end else begin
            valid_d <= in_valid;
            out_valid <= 1'b0;
            out_last <= 1'b0; 

            if (valid_d && !is_sending) begin
                buff_reg   <= in_data;
                is_sending <= 1'b1;
                row_cnt    <= 0;
                col_cnt    <= 0;
            end

            if (is_sending) begin
                out_data  <= buff_reg[row_cnt][col_cnt]; 
                out_valid <= 1'b1;
                
                if (row_cnt == N-1 && col_cnt == N-1) begin
                    out_last <= 1'b1;
                end
                
                if (col_cnt == N-1) begin
                    col_cnt <= 0;
                    
                    if (row_cnt == N-1) begin
                        is_sending <= 1'b0; 
                    end else begin
                        row_cnt <= row_cnt + 1;
                    end
                    
                end else begin
                    col_cnt <= col_cnt + 1;
                end
            end
            
        end
    end
    
endmodule
