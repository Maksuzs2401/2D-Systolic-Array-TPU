`timescale 1ns / 1ps
`include "config.vh"
module output_stage #(parameter N=`numb)(
    input logic                        clk,
    input logic                        rst_n,
    input logic                        start,
    input logic signed [`out_width-1:0]pe_out[0:N-1][0:N-1],
    output logic signed [`out_width-1:0]result[0:N-1][0:N-1],
    output logic                       res_valid,
    output logic                       accu_clear
    );
    
    localparam done = N;
    logic [$clog2(done+1)-1:0] count;
    logic                      counting;
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            count        <= '0;
            counting     <= 1'b0;
            res_valid <= 1'b0;
            accu_clear <= 1'b0;
        end else begin
            accu_clear <= 1'b0;
            if (start && !counting) begin
                counting     <= 1'b1;
                count        <= '0;
                res_valid <= 1'b0;
            end
            if(counting)begin
                if(count==done)begin
                    counting     <= 1'b0;
                    res_valid <= 1'b1;
                    accu_clear <= 1'b1;
                    for(int i=0;i<N;i++)
                        for(int j=0;j<N;j++)
                            result[i][j]<= pe_out[i][j];
                end else count <= count+1;
            end
        end
      end
endmodule
