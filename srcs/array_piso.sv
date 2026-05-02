`timescale 1ns / 1ps
`include "config.vh"
module array_piso #(parameter N=`numb)(  
    
    input logic                              clk,
    input logic                              rst_n,
    input logic signed [`accu_width-1:0]     in_data[0:N-1][0:N-1],
    input logic                              in_valid,
    input logic                              out_ready,
    output logic signed    [`accu_width-1:0] out_data[0:N-1],
    output logic                             out_last,
    output logic                             out_valid
    

    );
    
    logic [$clog2(N)-1:0] row_cnt;
    
    logic signed [`accu_width-1:0] buff_reg[0:N-1][0:N-1];
    logic is_sending;
    logic valid_d;
        
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < N; i++)
                out_data[i] <= '0;
            out_valid  <= 1'b0;
            is_sending <= 1'b0;
            row_cnt    <= 0;
            valid_d <= 1'b0;
        end else begin
            valid_d <= in_valid;
            out_valid <= 1'b0;
            out_last <= 1'b0; 

            // Trigger the start
            if (valid_d && !is_sending) begin
                buff_reg   <= in_data;
                is_sending <= 1'b1;
                row_cnt    <= 0;
            end

            // The Sending Logic
            if (is_sending) begin
                if(!out_valid)begin
                    for (int j = 0; j < N; j++)
                        out_data[j] <= buff_reg[row_cnt][j]; 
                        out_valid <= 1'b1;
                end else if(out_valid && out_ready)begin
                    if (row_cnt == N-1) begin
                        out_last   <= 1'b1;
                        is_sending <= 1'b0;
                        out_valid <=  1'b0;
                end else begin
                      for (int j = 0; j < N; j++)
                            out_data[j] <= buff_reg[row_cnt + 1][j];
                     row_cnt <= row_cnt + 1;
                    end
                 end
            end else begin
                out_valid <= 1'b0;
                out_last  <= 1'b0;
            end
        end
    end
endmodule
