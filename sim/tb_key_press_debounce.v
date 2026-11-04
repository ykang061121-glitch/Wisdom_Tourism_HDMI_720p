`timescale 1ns/1ps

module tb_key_press_debounce;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg button_in = 1'b1;
    wire press_pulse;
    integer errors = 0;
    integer pulse_count = 0;
    integer previous_pulse = 0;

    always #5 clk = ~clk;

    // Accelerated parameters preserve the RTL algorithm while keeping regression fast:
    // DEBOUNCE_CYCLES = (10 kHz / 1000) * 2 ms = 20 clocks.
    key_press_debounce #(
        .CLK_FREQ_HZ(10000),
        .DEBOUNCE_MS(2)
    ) dut (
        .clk(clk), .rst(rst), .button_in(button_in), .press_pulse(press_pulse)
    );

    task fail;
        input [8*120-1:0] message;
        begin
            errors = errors + 1;
            $error("%0s", message);
        end
    endtask

    task clocks;
        input integer count;
        integer n;
        begin
            for (n = 0; n < count; n = n + 1)
                @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (!rst) begin
            if (press_pulse)
                pulse_count = pulse_count + 1;
            if (press_pulse && previous_pulse)
                fail("press_pulse remained high for more than one clock");
            previous_pulse = press_pulse;
        end
    end

    initial begin
        clocks(5);
        rst = 1'b0;
        clocks(4);

        // 1. Short active-low glitch: no event.
        button_in = 1'b0; clocks(5);
        button_in = 1'b1; clocks(25);
        if (pulse_count != 0)
            fail("short glitch generated a press event");

        // 2/3. Contact bounce followed by a legal stable press.
        button_in = 1'b0; clocks(4);
        button_in = 1'b1; clocks(3);
        button_in = 1'b0; clocks(5);
        button_in = 1'b1; clocks(2);
        button_in = 1'b0; clocks(25);
        if (pulse_count != 1)
            fail("bounced legal press did not generate exactly one event");

        // 4. Holding the key must not repeat.
        clocks(100);
        if (pulse_count != 1)
            fail("held key generated repeated events");

        // 5. Bounced release must not generate a press event.
        button_in = 1'b1; clocks(4);
        button_in = 1'b0; clocks(3);
        button_in = 1'b1; clocks(25);
        if (pulse_count != 1)
            fail("release generated a press event");

        // 6. Second press generates one additional event.
        button_in = 1'b0; clocks(3);
        button_in = 1'b1; clocks(2);
        button_in = 1'b0; clocks(25);
        clocks(40);
        if (pulse_count != 2)
            fail("second press did not generate exactly one new event");

        if (errors == 0) begin
            $display("KEY_DEBOUNCE_TEST_PASS");
            $finish;
        end else begin
            $fatal(1, "KEY_DEBOUNCE_TEST_FAIL errors=%0d", errors);
        end
    end

    initial begin
        #100000;
        $fatal(1, "KEY_DEBOUNCE_TEST_TIMEOUT");
    end
endmodule
