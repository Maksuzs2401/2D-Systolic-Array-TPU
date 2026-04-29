`timescale 1ns / 1ps
`include "config.vh"

module top_wrapper_tb; 
    localparam N = `numb;
    
    logic                      clk, rst_n;
    
    logic                      s_axis_tvalid;
    logic signed [15:0]        s_axis_tdata;
    logic                      s_axis_tlast;
    logic                      s_axis_tready;
    
    logic signed [31:0]        m_axis_tdata;
    logic                      m_axis_tvalid;
    logic                      m_axis_tlast;
    logic                      m_axis_tready;
    
    logic signed [31:0]        result_matrix [0:N-1][0:N-1];

    // Instantiate the AXI Wrapper
    axi_wrapp #(.N(N)) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tready (s_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tlast  (m_axis_tlast),
        .m_axis_tready (m_axis_tready)
    );

    initial clk = 0;
    always #2.5 clk = ~clk;  // Final modules tested at 200MHz

    integer pass_count, fail_count;
    integer cycle_counter;
    integer start_cycle;
    integer end_cycle=0;
    
    always_ff @(posedge clk)begin
        if (!rst_n) cycle_counter <= 0;
        else        cycle_counter <= cycle_counter + 1;
    end

    // Software reference model
    function automatic logic signed [31:0] ref_C(
        input logic signed [7:0] A [0:N-1][0:N-1],
        input logic signed [7:0] B [0:N-1][0:N-1],
        input int row, col
    );
        logic signed [31:0] sum;
        sum = 0;
        for (int k = 0; k < N; k++)
            sum += A[row][k] * B[k][col];
        return sum;
    endfunction

    // Task: reset
    task apply_reset();
        rst_n         = 0;
        s_axis_tvalid = 0;
        s_axis_tdata  = 0;
        s_axis_tlast  = 0;
        m_axis_tready = 0; 
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
    endtask

    // Task: feed both matrices over AXI-Stream
    task feed_matrices(
        input logic signed [7:0] A [0:N-1][0:N-1],
        input logic signed [7:0] B [0:N-1][0:N-1]
    );
        @(negedge clk);
        s_axis_tvalid = 1'b1;
        
        for (int i = 0; i < N*N; i++) begin
            // Packing B into the top 8 bits, A into the bottom 8 bits!
            s_axis_tdata = {B[i/N][i%N], A[i/N][i%N]};
            
            // Asserting TLAST on the very last element
            s_axis_tlast = (i == (N*N - 1)) ? 1'b1 : 1'b0;
            
            @(posedge clk);
            
            // Waiting if the wrapper's FIFO/Buffer is ever full (TREADY goes low)
            while (!s_axis_tready) @(posedge clk);
            
            @(negedge clk);
        end
        
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
    endtask

    // Task: COLLECT SERIAL RESULTS OVER AXI-STREAM
    task collect_results(output logic timed_out);
        integer elem;
        integer timeout_cnt;

        elem        = 0;
        timeout_cnt = 0;
        timed_out   = 0;

        // Tell the wrapper the Testbench DMA is ready to accept data
        m_axis_tready = 1'b1; 

        while (!m_axis_tvalid) begin
            @(posedge clk);
            timeout_cnt++;
            if (timeout_cnt > 2000) begin
                $display("  TIMEOUT - m_axis_tvalid never fired");
                timed_out = 1;
                return;
            end
        end

        while (elem < N*N) begin
            // Only sample data when BOTH Valid and Ready are high
            if (m_axis_tvalid && m_axis_tready) begin
                result_matrix[elem/N][elem%N] = m_axis_tdata;
                elem++;
                if (m_axis_tlast) break;
            end
            @(posedge clk);
        end
        
        // Turn off ready when done
        m_axis_tready = 1'b0; 
    endtask

    // Task: PRINT MATRIX
    task print_result_matrix(input string title);
        $display("  MATRIX OUTPUT: %s", title);
        for (int i = 0; i < N; i++) begin
            $write("  Row %2d: ", i);
            for (int j = 0; j < N; j++) begin
                $write("%6d ", result_matrix[i][j]);
            end
            $display(""); 
        end
        $display("==========================================================================================================\n");
    endtask

    // Task: verify result against reference
    task verify_result(
        input logic signed [7:0] A [0:N-1][0:N-1],
        input logic signed [7:0] B [0:N-1][0:N-1],
        input string             test_name
    );
        logic signed [31:0] expected;
        $display("  Checking all %0d×%0d = %0d results for %s:", N, N, N*N, test_name);
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                expected = ref_C(A, B, i, j);
                if (result_matrix[i][j] === expected) begin
                    $display("    PASS | C[%0d][%0d] = %0d", i, j, result_matrix[i][j]);
                    pass_count++;
                end else begin
                    $display("    FAIL | C[%0d][%0d] = %0d  expected = %0d",
                              i, j, result_matrix[i][j], expected);
                    fail_count++;
                end
            end
        end
    endtask

    // Main test
    logic timed_out;
    initial begin
        pass_count = 0;
        fail_count = 0;
        
        $display("  AXI-STREAM WRAPPER TESTBENCH  N=%0d", N);
        $display("  Simulating DMA Feed and Read");

        // TEST 1
        $display("--- TEST 1: Identity × Random ---");
        begin
            logic signed [7:0] A [0:N-1][0:N-1];
            logic signed [7:0] B [0:N-1][0:N-1];
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++) A[i][j] = (i == j) ? 8'sd1 : 8'sd0;
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++) B[i][j] = i*N + j + 1;
            
            apply_reset();
            feed_matrices(A, B);
            collect_results(timed_out);
            if (!timed_out) begin
                print_result_matrix("Identity × Random");
                verify_result(A, B, "Identity × Random");
            end
        end

        // TEST 3
        $display("\n--- TEST 3: Known matrices + Performance ---");
        begin
            logic signed [7:0] A [0:N-1][0:N-1];
            logic signed [7:0] B [0:N-1][0:N-1];
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++) A[i][j] = i*N + j + 1;
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++) B[i][j] = i*N + j + 1;
            
            apply_reset();
            start_cycle = cycle_counter; 
            feed_matrices(A, B);
            collect_results(timed_out);
            end_cycle = cycle_counter;
            
            if (!timed_out) begin
                print_result_matrix("Known Matrices (Sequential Data)");
                verify_result(A, B, "Known matrices");
                
                $display("\n========================================");
                $display("  PERFORMANCE REPORT  N=%0d", N);
                $display("========================================");
                $display("  Total MACs          : %0d", N*N*N);
                $display("  End-to-end cycles   : %0d", end_cycle - start_cycle);
                $display("========================================\n");
            end
        end

        // Final report
        $display("  RESULTS: %0d passed | %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL AXI TESTS PASSED - Ready for IP Packager \n");
        else
            $display("  FAILURES PRESENT \n");
            
        $finish;
    end

    initial begin
        $dumpfile("top_wrapper_tb.vcd");
        $dumpvars(0, top_wrapper_tb);
    end

    initial begin
        #5000000;
        $display("timeout - simulation hung");
        $finish;
    end
endmodule
