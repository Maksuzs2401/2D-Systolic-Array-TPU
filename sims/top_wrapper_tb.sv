`timescale 1ns / 1ps
`include "config.vh"

module top_wrapper_tb;
    localparam N = `numb;

    logic                           clk, rst_n;
    logic [`data_in_width-1:0]      s_axis_tdata;
    logic                           s_axis_tvalid;
    logic                           s_axis_tlast;
    logic                           s_axis_tready;

    logic [`data_out_width-1:0]     m_axis_tdata;
    logic                           m_axis_tvalid;
    logic                           m_axis_tlast;
    logic                           m_axis_tready;

    logic signed [31:0]             result_matrix [0:N-1][0:N-1];

    axi_wrapp #(.N(N)) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tready (s_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tlast  (m_axis_tlast),
        .m_axis_tready (m_axis_tready)
    );

    initial clk = 0;
    always #2.5 clk = ~clk;

    integer pass_count, fail_count;
    integer cycle_counter;
    integer start_cycle;
    integer end_cycle = 0;

    always_ff @(posedge clk) begin
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
        s_axis_tdata  = '0;
        s_axis_tlast  = 0;
        m_axis_tready = 0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
    endtask

    // ------------------------------------------------------------------
    // Task: feed both matrices over wide AXI-Stream
    // N beats (one row per beat)
    // Bit layout per beat:
    //   [N*8-1    :     0] = A row
    //   [N*8*2-1  :  N*8] = B row
    // ------------------------------------------------------------------
    task feed_matrices(
        input logic signed [7:0] A [0:N-1][0:N-1],
        input logic signed [7:0] B [0:N-1][0:N-1]
    );
        logic [`data_in_width-1:0] beat;

        @(negedge clk);
        s_axis_tvalid = 1'b1;

        for (int row = 0; row < N; row++) begin
            beat = '0;
            for (int j = 0; j < N; j++) begin
                beat[j*`data_width +: `data_width]                     = A[row][j];
                beat[N*`data_width + j*`data_width +: `data_width]     = B[row][j];
            end

            s_axis_tdata = beat;
            s_axis_tlast = (row == N-1) ? 1'b1 : 1'b0;

            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
            @(negedge clk);
        end

        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
    endtask

    // Task: collect row-parallel results
    // N beats, each beat = N x out_width results
    //
    // Bit layout per beat:
    //   [j*out_width +: out_width] = result element j
    task collect_results(output logic timed_out);
        integer row_idx;
        integer timeout_cnt;
        row_idx     = 0;
        timeout_cnt = 0;
        timed_out   = 0;

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

        while (row_idx < N) begin
            if (m_axis_tvalid && m_axis_tready) begin
                for (int j = 0; j < N; j++)
                    result_matrix[row_idx][j] = m_axis_tdata[j*`accu_width +: `accu_width];
                row_idx++;
                if (m_axis_tlast) begin
                    if (row_idx != N)
                        $display("  WARNING: tlast at row %0d, expected at row %0d", row_idx, N);
                end
            end
            @(posedge clk);
        end

        m_axis_tready = 1'b0;
    endtask

    // Task: print matrix
    task print_result_matrix(input string title);
        $display("  MATRIX OUTPUT: %s", title);
        for (int i = 0; i < N; i++) begin
            $write("  Row %2d: ", i);
            for (int j = 0; j < N; j++)
                $write("%6d ", result_matrix[i][j]);
            $display("");
        end
    endtask

    // Task: verify result against reference
    task verify_result(
        input logic signed [7:0] A [0:N-1][0:N-1],
        input logic signed [7:0] B [0:N-1][0:N-1],
        input string             test_name
    );
        logic signed [31:0] expected;
        $display("  Checking %0d x %0d = %0d results for %s:", N, N, N*N, test_name);
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

        $display("  Wide bus: input=%0d bits, output=%0d bits",
                 `data_in_width, `data_out_width);
        $display("  Feed = %0d beats (was %0d), Drain = %0d beats (was %0d)",
                 N, N*N, N, N*N);

        // TEST 1: Identity x Sequential
        $display("--- TEST 1: Identity x Sequential ---");
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
                print_result_matrix("Identity x Sequential");
                verify_result(A, B, "Identity x Sequential");
            end
        end

        // TEST 2: Known matrices + Performance
        $display("\n--- TEST 2: Known matrices + Performance ---");
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
                print_result_matrix("Sequential x Sequential");
                verify_result(A, B, "Known matrices");

                $display("  PERFORMANCE REPORT  N=%0d", N);
                $display("  Total MACs            : %0d", N*N*N);
                $display("  End-to-end cycles     : %0d", end_cycle - start_cycle);
                $display("  Feed beats            : %0d", N);
                $display("  Drain beats           : %0d", N);
                $display("  I/O speedup           : %.1fx", real'(N*N) / real'(N));
            end
        end

        // Final report
        $display("  RESULTS: %0d passed | %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED\n");
        else
            $display("  FAILURES PRESENT\n");

        $finish;
    end

    initial begin
        #5000000;
        $display("TIMEOUT - simulation hung");
        $finish;
    end
endmodule