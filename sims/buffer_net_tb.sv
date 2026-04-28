`timescale 1ns / 1ps
`include "config.vh"

module buffer_net_tb;

    localparam N = 4;

    logic                    clk, rst_n;
    logic signed [7:0]       a_in, b_in;
    logic                    a_valid, b_valid;
    logic signed [7:0]       a_row [0:N-1];
    logic signed [7:0]       b_col [0:N-1];
    logic                    valid_out [0:N-1];
    logic                    load;

    buffer_net #(.N(N)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .a_in      (a_in),
        .a_valid   (a_valid),
        .b_in      (b_in),
        .b_valid   (b_valid),
        .a_row     (a_row),
        .b_col     (b_col),
        .valid_out (valid_out),
        .load      (load)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count, fail_count;

    // Matrices used
    //
    // A (row major serial order):
    //   1  2  3  4    row 0
    //   5  6  7  8    row 1
    //   9 10 11 12    row 2
    //  13 14 15 16    row 3
    //
    // B (row major serial order):
    //   1  2  3  4    row 0
    //   5  6  7  8    row 1
    //   9 10 11 12    row 2
    //  13 14 15 16    row 3
    //
    // After data separator, b_reg should be:
    //   b_reg[0] = [1, 5,  9, 13]  col 0 of B
    //   b_reg[1] = [2, 6, 10, 14]  col 1 of B
    //   b_reg[2] = [3, 7, 11, 15]  col 2 of B
    //   b_reg[3] = [4, 8, 12, 16]  col 3 of B
    //
    // Expected staggered output at a_row:
    //   cycle 1: a_row=[1, 0, 0, 0]   row 0 starts
    //   cycle 2: a_row=[2, 5, 0, 0]   row 1 starts
    //   cycle 3: a_row=[3, 6, 9, 0]   row 2 starts
    //   cycle 4: a_row=[4, 7,10,13]   row 3 starts
    //   cycle 5: a_row=[0, 8,11,14]   row 0 done
    //   cycle 6: a_row=[0, 0,12,15]   row 1 done
    //   cycle 7: a_row=[0, 0, 0,16]   row 2 done

    // Packed arrays 
    logic signed [7:0] A_flat [0:N*N-1];
    logic signed [7:0] B_flat [0:N*N-1];

    task apply_reset();
        rst_n   = 0;
        a_valid = 0;
        b_valid = 0;
        a_in    = 0;
        b_in    = 0;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
    endtask

    task check_a_row(
        input logic signed [7:0] exp [0:N-1],
        input string             test_name
    );
        #1;
        for (int i = 0; i < N; i++) begin
            if (a_row[i] === exp[i]) begin
                $display("  PASS | %-35s | a_row[%0d]=%0d",
                          test_name, i, a_row[i]);
                pass_count++;
            end else begin
                $display("  FAIL | %-35s | a_row[%0d]=%0d exp=%0d",
                          test_name, i, a_row[i], exp[i]);
                fail_count++;
            end
        end
    endtask

    task check_b_col(
        input logic signed [7:0] exp [0:N-1],
        input string             test_name
    );
        #1;
        for (int i = 0; i < N; i++) begin
            if (b_col[i] === exp[i]) begin
                $display("  PASS | %-35s | b_col[%0d]=%0d",
                          test_name, i, b_col[i]);
                pass_count++;
            end else begin
                $display("  FAIL | %-35s | b_col[%0d]=%0d exp=%0d",
                          test_name, i, b_col[i], exp[i]);
                fail_count++;
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        // A row major: 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
        for (int i = 0; i < N*N; i++)
            A_flat[i] = i + 1;

        // B same values
        for (int i = 0; i < N*N; i++)
            B_flat[i] = i + 1;

        $display("  BUFFER_NET TESTBENCH  N=%0d", N);

        apply_reset();

        // TEST 1 - Feed matrix A serially
        $display("--- TEST 1: Load matrix A ---");

        @(negedge clk);
        a_valid = 1'b1;

        for (int i = 0; i < N*N; i++) begin
            a_in = A_flat[i];
            @(posedge clk);
            @(negedge clk);
        end

        a_valid = 1'b0;
        @(posedge clk); #1;

        // Checking a_loaded fired
        if (dut.a_loaded === 1'b1)
            $display("  PASS | a_loaded high after %0d bytes", N*N);
        else
            $display("  FAIL | a_loaded not high");

        // Peeking inside a_reg and verifying
        $display("  Checking a_reg contents:");
        for (int row = 0; row < N; row++) begin
            for (int col = 0; col < N; col++) begin
                logic signed [7:0] expected;
                expected = row * N + col + 1;
                if (dut.a_reg[row][col] === expected)
                    $display("  PASS | a_reg[%0d][%0d]=%0d",
                              row, col, dut.a_reg[row][col]);
                else
                    $display("  FAIL | a_reg[%0d][%0d]=%0d exp=%0d",
                              row, col, dut.a_reg[row][col], expected);
            end
        end

        // TEST 2 - Feed matrix B serially, check data separator
        $display("\n--- TEST 2: Load matrix B (data separator) ---");

        @(negedge clk);
        b_valid = 1'b1;

        for (int i = 0; i < N*N; i++) begin
            b_in = B_flat[i];
            @(posedge clk);
            @(negedge clk);
        end

        b_valid = 1'b0;
        @(posedge clk); #1;

        if (dut.b_loaded === 1'b1)
            $display("  PASS | b_loaded high after %0d bytes", N*N);
        else
            $display("  FAIL | b_loaded not high");

        $display("  Checking b_reg (should be column organised):");
        for (int col = 0; col < N; col++) begin
            $display("  b_reg[%0d] (col %0d of B):", col, col);
            for (int row = 0; row < N; row++) begin
                logic signed [7:0] expected;
                expected = row * N + col + 1;
                if (dut.b_reg[col][row] === expected)
                    $display("    PASS | b_reg[%0d][%0d]=%0d (B[%0d][%0d])",
                              col, row, dut.b_reg[col][row], row, col);
                else
                    $display("    FAIL | b_reg[%0d][%0d]=%0d exp=%0d",
                              col, row, dut.b_reg[col][row], expected);
            end
        end

        // TEST 3 - Staggered output
        // Both loaded - compute_started should fire
        // Watch a_row and b_col for 7 cycles
        //
        // Expected a_row pattern (registered output - 1 cycle lag):
        // After posedge 1: [1,  0,  0,  0]
        // After posedge 2: [2,  5,  0,  0]
        // After posedge 3: [3,  6,  9,  0]
        // After posedge 4: [4,  7, 10, 13]
        // After posedge 5: [0,  8, 11, 14]
        // After posedge 6: [0,  0, 12, 15]
        // After posedge 7: [0,  0,  0, 16]
        //
        // Expected b_col pattern (same stagger):
        // After posedge 1: [1,  0,  0,  0]  col0[0]=B[0][0]=1
        // After posedge 2: [2,  5,  0,  0]  
        // etc.
        $display("\n--- TEST 3: Staggered output pattern ---");

        repeat(3) @(posedge clk);

        $display("  Watching output for %0d cycles:", 2*N-1);
        $display("");

        // Expected values for each cycle
        // a_row[i] at output cycle c:
        //   row i active when c >= i+1 and c <= i+N
        //   value = a_reg[i][c - i - 1] = (i*N) + (c-i-1) + 1
        //         = i*N + c - i

        for (int cycle = 1; cycle <= 2*N-1; cycle++) begin
            @(posedge clk); @(negedge clk); #1;

            $write("  Cycle %0d: a_row=[", cycle);
            for (int i = 0; i < N; i++)
                $write("%3d", a_row[i]);
            $display("]");

            $write("           b_col=[");
            for (int i = 0; i < N; i++)
                $write("%3d", b_col[i]);
            $display("]");

            $write("           valid=[");
            for (int i = 0; i < N; i++)
                $write("%1d", valid_out[i]);
            $display("]");
            $display("");
        end

        // TEST 4 - Verify specific values
        $display("--- TEST 4: Specific value checks ---");

        apply_reset();

        @(negedge clk); a_valid = 1;
        for (int i = 0; i < N*N; i++) begin
            a_in = i + 1;
            @(posedge clk); @(negedge clk);
        end
        a_valid = 0;

       @(negedge clk); b_valid = 1;
        apply_reset();

        // Load A and B simultaneously
        @(negedge clk);
        a_valid = 1'b1;
        b_valid = 1'b1;

        for (int i = 0; i < N*N; i++) begin
            a_in = i + 1;
            b_in = i + 1;
            @(posedge clk);
            @(negedge clk);
        end

        a_valid = 1'b0;
        b_valid = 1'b0;

        repeat(2) @(posedge clk);

        $display("  Verifying cycle by cycle:");

        // Cycle 1: only row 0 active → a_row=[1,0,0,0]
        @(posedge clk); @(negedge clk);
        begin
            logic signed [7:0] exp [0:N-1];
            exp = '{8'sd1, 8'sd0, 8'sd0, 8'sd0};
            check_a_row(exp, "cycle1 a_row=[1,0,0,0]");
            check_b_col(exp, "cycle1 b_col=[1,0,0,0]");
        end

        // Cycle 2: rows 0,1 active → a_row=[5,2,0,0]
        @(posedge clk); @(negedge clk);
        begin
            logic signed [7:0] exp_a [0:N-1];
            logic signed [7:0] exp_b [0:N-1];
            exp_a = '{8'sd2, 8'sd5, 8'sd0, 8'sd0};
            exp_b = '{8'sd5, 8'sd2, 8'sd0, 8'sd0};
            check_a_row(exp_a, "cycle2 a_row=[2,5,0,0]");
            check_b_col(exp_b, "cycle2 b_col=[5,2,0,0]");
        end

        // Cycle 3: rows 0,1,2 active → a_row=[3,6,9,0]
        @(posedge clk); @(negedge clk);
        begin
            logic signed [7:0] exp [0:N-1];
            exp = '{8'sd3, 8'sd6, 8'sd9, 8'sd0};
            check_a_row(exp, "cycle3 a_row=[3,6,9,0]");
        end

        // Cycle 4: all rows active → a_row=[4,7,10,13]
        @(posedge clk); @(negedge clk);
        begin
            logic signed [7:0] exp [0:N-1];
            exp = '{8'sd4, 8'sd7, 8'sd10, 8'sd13};
            check_a_row(exp, "cycle4 a_row=[4,7,10,13]");
        end

        // Cycle 5: row 0 done → a_row=[0,8,11,14]
        @(posedge clk); @(negedge clk);
        begin
            logic signed [7:0] exp [0:N-1];
            exp = '{8'sd0, 8'sd8, 8'sd11, 8'sd14};
            check_a_row(exp, "cycle5 a_row=[0,8,11,14]");
        end

        // Cycle 6: rows 0,1 done → a_row=[0,0,12,15]
        @(posedge clk); @(negedge clk);
        begin
            logic signed [7:0] exp [0:N-1];
            exp = '{8'sd0, 8'sd0, 8'sd12, 8'sd15};
            check_a_row(exp, "cycle6 a_row=[0,0,12,15]");
        end

        // Cycle 7: only row 3 left → a_row=[0,0,0,16]
        @(posedge clk); @(negedge clk);
        begin
            logic signed [7:0] exp [0:N-1];
            exp = '{8'sd0, 8'sd0, 8'sd0, 8'sd16};
            check_a_row(exp, "cycle7 a_row=[0,0,0,16]");
        end

        // TEST 5 - load signal fires at end
        $display("\n--- TEST 5: load signal ---");
        @(posedge clk); #1;
        if (load === 1'b1)
            $display("  PASS | load fired when last row finished");
        else
            $display("  FAIL | load did not fire");

        // Final report
        $display("\n============================================");
        $display("  RESULTS: %0d passed | %0d failed",
                  pass_count, fail_count);
        $display("============================================");
        if (fail_count == 0)
            $display("  BUFFER_NET VERIFIED");
        else
            $display("  FAILURES - fix before connecting to array\n");

        $finish;
    end

    initial begin
        $dumpfile("buffer_net_tb.vcd");
        $dumpvars(0, buffer_net_tb);
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
