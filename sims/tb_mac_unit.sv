`timescale 1ns / 1ps
`include "config.vh"

module tb_mac_unit;

    logic                              clk;
    logic                              rst_n;
    logic                              accu_clear;
    logic                              valid_in;
    logic signed [`data_width-1:0]     a_in;
    logic signed [`data_width-1:0]     b_in;
    logic signed [`data_width-1:0]     a_pass;
    logic signed [`data_width-1:0]     b_pass;
    logic                              valid_out;
    logic signed [`out_width-1:0]      out;

    mac_unit dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .accu_clear (accu_clear),
        .valid_in   (valid_in),
        .a_reg       (a_in),
        .b_reg       (b_in),
        .a_pass     (a_pass),
        .b_pass     (b_pass),
        .valid_out  (valid_out),
        .out        (out)
    );

    // Clock - 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count, fail_count;

    // ------------------------------------------------------------------
    // Task: apply_reset
    // ------------------------------------------------------------------
    task apply_reset();
        rst_n      = 0;
        accu_clear = 0;
        valid_in   = 0;
        a_in       = '0;
        b_in       = '0;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
    endtask

    // ------------------------------------------------------------------
    // Task: feed - drives inputs on negedge, returns after drive
    // ------------------------------------------------------------------
    task feed(
        input logic signed [`data_width-1:0] a,
        input logic signed [`data_width-1:0] b,
        input logic                          v
    );
        @(negedge clk);
        a_in     = a;
        b_in     = b;
        valid_in = v;
    endtask

    // ------------------------------------------------------------------
    // Task: stop_feed - deasserts valid, zeroes inputs
    //       MUST call this after every feed sequence before checking
    // ------------------------------------------------------------------
    task stop_feed();
        @(negedge clk);
        valid_in = 1'b0;
        a_in     = '0;
        b_in     = '0;
    endtask

    // ------------------------------------------------------------------
    // Task: check - samples CURRENT out, no extra clock advance
    //       Caller is responsible for being at the right clock position
    // ------------------------------------------------------------------
    task check(
        input logic signed [`out_width-1:0] expected,
        input string                        test_name
    );
        #1; // small settle after posedge
        if (out === expected) begin
            $display("  PASS | %-40s | got=%0d", test_name, out);
            pass_count++;
        end else begin
            $display("  FAIL | %-40s | got=%0d  expected=%0d",
                      test_name, out, expected);
            fail_count++;
        end
    endtask

    // ------------------------------------------------------------------
    // Task: clear_accum - fires accu_clear for one cycle cleanly
    // ------------------------------------------------------------------
    task clear_accum();
        @(negedge clk);
        accu_clear = 1'b1;
        valid_in   = 1'b0;
        @(posedge clk);        // clear fires on this edge
        @(negedge clk);
        accu_clear = 1'b0;
    endtask

    // ------------------------------------------------------------------
    // MAIN TEST SEQUENCE
    // ------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("\n============================================");
        $display("  MAC UNIT TESTBENCH");
        $display("  data_width=%0d | accum_width=%0d | out_width=%0d",
                  `data_width, `accu_width, `out_width);
        $display("============================================\n");

        // ==============================================================
        // TEST 1 - Reset
        // ==============================================================
        $display("--- TEST 1: Reset ---");
        apply_reset();
        @(posedge clk);
        check(0, "out=0 after reset");
        if (a_pass === '0 && b_pass === '0 && valid_out === 1'b0)
            $display("  PASS | passthrough signals zero after reset");
        else
            $display("  FAIL | passthrough not zero | a_pass=%0d b_pass=%0d valid_out=%0b",
                      a_pass, b_pass, valid_out);

        // ==============================================================
        // TEST 2 - Basic MAC: 3×4 for 4 cycles
        //   Each valid posedge: accum += 12
        //   After 4 cycles: accum = 48
        // ==============================================================
        $display("\n--- TEST 2: Basic accumulation (3x4, 4 cycles = 48) ---");

        feed(8'sd3, 8'sd4, 1'b1); @(posedge clk);   // accum=12
        feed(8'sd3, 8'sd4, 1'b1); @(posedge clk);   // accum=24
        feed(8'sd3, 8'sd4, 1'b1); @(posedge clk);   // accum=36
        feed(8'sd3, 8'sd4, 1'b1); @(posedge clk);   // accum=48
        stop_feed();               @(posedge clk);   // valid=0, accum holds
        check(48, "3x4 x4 = 48");

        // ==============================================================
        // TEST 3 - valid_in gating
        //   Accumulator at 48 coming in
        //   2 valid (2×5=10 each): +20 → 68
        //   2 invalid:               +0 → 68  (must freeze)
        //   1 valid:                +10 → 78
        //   Expected: 78
        // ==============================================================
        $display("\n--- TEST 3: valid_in gating ---");

        feed(8'sd2, 8'sd5, 1'b1); @(posedge clk);   // accum=58
        feed(8'sd2, 8'sd5, 1'b1); @(posedge clk);   // accum=68
        feed(8'sd2, 8'sd5, 1'b0); @(posedge clk);   // accum=68 (gated)
        feed(8'sd2, 8'sd5, 1'b0); @(posedge clk);   // accum=68 (gated)
        feed(8'sd2, 8'sd5, 1'b1); @(posedge clk);   // accum=78
        stop_feed();               @(posedge clk);   // accum holds
        check(78, "valid gating: 48 + 3x10 = 78");

        // ==============================================================
        // TEST 4 - accu_clear
        // ==============================================================
        $display("\n--- TEST 4: accu_clear ---");

        clear_accum();
        @(posedge clk);
        check(0, "accum zeroed by clear");

        feed(8'sd6, 8'sd7, 1'b1); @(posedge clk);   // accum=42
        feed(8'sd6, 8'sd7, 1'b1); @(posedge clk);   // accum=84
        stop_feed();               @(posedge clk);
        check(84, "after clear: 6x7 x2 = 84");

        // ==============================================================
        // TEST 5 - Passthrough timing: 1 cycle delay
        // ==============================================================
        $display("\n--- TEST 5: Passthrough 1-cycle delay ---");

        @(negedge clk);
        a_in     = 8'sd42;
        b_in     = 8'sd99;
        valid_in = 1'b1;
        @(posedge clk);      // passthrough correct here - sample immediately
        #1;                  // ← check RIGHT HERE before stop_feed touches anything
        
        if (a_pass === 8'sd42 && b_pass === 8'sd99 && valid_out === 1'b1)
            $display("  PASS | a_pass=%0d b_pass=%0d valid_out=%0b (1 cycle delay correct)",
                      a_pass, b_pass, valid_out);
        else
            $display("  FAIL | a_pass=%0d(exp 42) b_pass=%0d(exp 99) valid_out=%0b(exp 1)",
                      a_pass, b_pass, valid_out);
        stop_feed();         // NOW safe to zero inputs
        // ==============================================================
        // TEST 6 - Signed arithmetic
        //   (-3)×4 = -12 for 3 cycles = -36
        //   Then (-5)×(-5) = 25 for 2 cycles = +50
        //   Total: -36 + 50 = 14
        // ==============================================================
        $display("\n--- TEST 6: Signed arithmetic ---");

        clear_accum();

        feed(-8'sd3, 8'sd4, 1'b1); @(posedge clk);  // accum=-12
        feed(-8'sd3, 8'sd4, 1'b1); @(posedge clk);  // accum=-24
        feed(-8'sd3, 8'sd4, 1'b1); @(posedge clk);  // accum=-36
        stop_feed();                @(posedge clk);
        check(-36, "(-3)x4 x3 = -36");

        feed(-8'sd5, -8'sd5, 1'b1); @(posedge clk); // accum=-11
        feed(-8'sd5, -8'sd5, 1'b1); @(posedge clk); // accum=14
        stop_feed();                 @(posedge clk);
        check(14, "(-3x4x3) + ((-5)x(-5)x2) = 14");

        // ==============================================================
        // TEST 7 - Back to back: clear → accumulate × 3 times
        //   Each round: 10×10=100 for 2 cycles = 200
        // ==============================================================
        $display("\n--- TEST 7: Back-to-back operations ---");

        repeat(3) begin
            clear_accum();
            feed(8'sd10, 8'sd10, 1'b1); @(posedge clk);  // accum=100
            feed(8'sd10, 8'sd10, 1'b1); @(posedge clk);  // accum=200
            stop_feed();                 @(posedge clk);
            check(200, "clear then 10x10 x2 = 200");
        end

        // ==============================================================
        // Final report
        // ==============================================================
        $display("\n============================================");
        $display("  RESULTS: %0d passed | %0d failed", pass_count, fail_count);
        $display("============================================");
        if (fail_count == 0)
            $display("  ALL TESTS PASSED - MAC unit verified\n");
        else
            $display("  FAILURES PRESENT - do not proceed to array\n");

        $finish;
    end

    initial begin
        $dumpfile("tb_mac_unit.vcd");
        $dumpvars(0, tb_mac_unit);
    end

    initial begin
        #50000;
        $display("TIMEOUT");
        $finish;
    end

endmodule