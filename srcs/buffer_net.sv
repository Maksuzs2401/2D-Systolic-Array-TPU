`timescale 1ns / 1ps
`include "config.vh"
module buffer_net #(parameter N =`numb)(

   input logic                          clk,
   input logic                          rst_n,
   input logic signed [`data_width-1:0] a_in[0:N-1],
   input logic                          a_valid,
   input logic signed [`data_width-1:0] b_in[0:N-1],
   input logic                          b_valid,
   
   output logic signed [`data_width-1:0]a_row [0:N-1],
   output logic signed [`data_width-1:0]b_col [0:N-1],
   output logic                         valid_out [0:N-1],
   output logic                         load,
   output logic                         ready
    );

    logic signed [`data_width-1:0] a_reg [0:N-1][0:N-1];
    logic [$clog2(N)-1:0]          a_cnt;
    logic                          a_loaded;
    
    logic signed [`data_width-1:0] b_reg [0:N-1][0:N-1];
    logic [$clog2(N)-1:0]          b_cnt;
    logic                          b_loaded;
    
    logic [$clog2(N)-1:0]      k          [0:N-1];
    logic                      row_active [0:N-1];
    logic [$clog2(N):0]        start_cnt;          
    logic                      compute_started;
    
    assign ready = !a_loaded;
    
    always_ff @(posedge clk)begin
        if(!rst_n)begin
            a_cnt <= 0;
            a_loaded <= 1'b0;
        end else if(load)begin
            a_loaded <= 1'b0;
            a_cnt    <= '0;
        end else if(a_valid && !a_loaded)begin
            for(int j=0; j<N;j++)
            a_reg[a_cnt][j] <= a_in[j];
            if(a_cnt == N-1)begin
                a_cnt <= 0;
                a_loaded <= 1'b1;
            end else 
                a_cnt <= a_cnt + 1;
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            b_cnt    <= '0;
            b_loaded <= 1'b0;
        end else if(load)begin
            b_loaded <= 1'b0;
            b_cnt    <= '0;
        end else if (b_valid && !b_loaded) begin
            for(int j=0;j<N;j++)
            b_reg[j][b_cnt] <= b_in[j];
            if (b_cnt == N-1) begin
                b_cnt    <= '0;
                b_loaded <= 1'b1;
            end else
                b_cnt <= b_cnt + 1;
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            start_cnt       <= '0;
            compute_started <= 1'b0;
            load            <= 1'b0;
            for(int i=0;i<N;i++)begin
                k[i]          <= 0;
                row_active[i] <= 1'b0;
            end 
            end else if(a_loaded && b_loaded && !compute_started && !load)begin
                compute_started <= 1'b1;
                start_cnt       <= '0;
            end else if(compute_started)begin
                
                for(int i=0; i<N; i++)begin
                    if(start_cnt==i[$clog2(N)-1:0]&&!row_active[i])begin
                        row_active[i] <= 1'b1;
                        k[i]          <= 0;
                    end else if(row_active[i])begin
                        if(k[i]==N-1)  row_active[i] <= 1'b0;
                        else k[i] <= k[i]+1;  
                end
            end
            
            if (start_cnt < N)
                start_cnt <= start_cnt + 1;

            // Done when last row finishes
            if (row_active[N-1] && k[N-1] == N-1)begin
                load <= 1'b1;   
                compute_started <= 1'b0;
            end
        end else load <= 1'b0;
    end
    
     always_ff @(posedge clk) begin
        for (int i = 0; i < N; i++) begin
            a_row[i]    <= row_active[i] ? a_reg[i][k[i]] : '0;
            b_col[i]    <= row_active[i] ? b_reg[i][k[i]] : '0;
            valid_out[i] <= row_active[i];
        end
    end
        
endmodule
