// Owner: Role 1 - Kaushal. PWM tone, duration, mute/reset and connected AMP2 controls.
`timescale 1ns / 1ps
`include "game_defs.vh"
module audio_beep_tb;
    reg clk=0, reset=1, start=0, mute=0;
    wire busy, audio_pwm;
    reg btnD=1, btnR=0;
    reg [1:0] sw=0;
    tri1 PS2Clk, PS2Data;
    wire [15:0] led;
    wire [7:0] JA,JB;
    wire [3:0] JC;
    integer clock_count=0, started_clock, ones, waited;
    integer top_starts=0;
    reg previous_top_busy=0;
    always #5 clk=~clk;
    always @(posedge clk) clock_count=clock_count+1;

    // Shorter counts retain the real PWM period, making checks quick.
    audio_beep #(.TONE_HALF_CYCLES(512),.BEEP_CYCLES(4096)) unit (
        .clk(clk),.reset(reset),.start(start),.mute(mute),.busy(busy),.audio_pwm(audio_pwm)
    );
    My_Top_Module #(
        .BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2),
        .AUDIO_TONE_HALF_CYCLES(512),.AUDIO_BEEP_CYCLES(4096)
    ) dut (
        .clk(clk),.btnC(1'b0),.btnU(1'b0),.btnR(btnR),.btnD(btnD),.sw(sw),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.led(led),.JA(JA),.JB(JB),.JC(JC)
    );
    always @(negedge clk) begin
        if (dut.reset) previous_top_busy=0;
        else begin
            if (dut.audio_busy && !previous_top_busy) top_starts=top_starts+1;
            previous_top_busy=dut.audio_busy;
        end
    end
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task count_unit_pwm;
        output integer high_cycles;
        integer sample;
        begin
            high_cycles=0;
            for (sample=0;sample<256;sample=sample+1) begin
                if (audio_pwm===1'b1) high_cycles=high_cycles+1;
                else if (audio_pwm!==1'b0) $fatal(1,"Unknown audio PWM output");
                clocks(1);
            end
        end
    endtask
    task count_top_pwm;
        output integer high_cycles;
        integer sample;
        begin
            high_cycles=0;
            for (sample=0;sample<256;sample=sample+1) begin
                if (JC[0]===1'b1) high_cycles=high_cycles+1;
                else if (JC[0]!==1'b0) $fatal(1,"Unknown JC audio output");
                clocks(1);
            end
        end
    endtask
    task pulse_start;
        begin start=1; clocks(1); start=0; end
    endtask
    task wait_top_beep;
        begin
            waited=0;
            while (!dut.audio_busy && waited<30) begin clocks(1); waited=waited+1; end
            if (!dut.audio_busy) $fatal(1,"BTNR did not trigger the connected beep");
        end
    endtask

    initial begin
        clocks(4);
        if (busy || JC[3]!==1'b0) $fatal(1,"Reset did not stop audio/shut down AMP2");
        reset=0; clocks(2);
        count_unit_pwm(ones);
        if (ones!=128) $fatal(1,"Idle PWM is not centred at 50 percent");

        pulse_start(); started_clock=clock_count;
        if (!busy) $fatal(1,"Tone request was not accepted");
        count_unit_pwm(ones);
        if (ones!=120) $fatal(1,"Low audio half-cycle duty incorrect: %0d",ones);
        clocks(256);
        count_unit_pwm(ones);
        if (ones!=136) $fatal(1,"High audio half-cycle duty incorrect: %0d",ones);
        // A second request during playback must not extend or queue the beep.
        pulse_start();
        waited=0;
        while (busy && waited<5000) begin clocks(1); waited=waited+1; end
        if (busy || clock_count-started_clock!=4096)
            $fatal(1,"Beep duration changed or a busy request restarted playback");
        clocks(5);
        if (busy) $fatal(1,"Busy request was replayed later");
        count_unit_pwm(ones);
        if (ones!=128) $fatal(1,"Completed beep did not return to centred silence");

        pulse_start(); clocks(30); mute=1; clocks(1);
        if (busy) $fatal(1,"Mute did not cancel playback");
        count_unit_pwm(ones);
        if (ones!=128) $fatal(1,"Muted PWM retained the audio tone");
        pulse_start(); mute=0; clocks(5);
        if (busy) $fatal(1,"Muted request replayed after unmuting");
        pulse_start(); clocks(20); reset=1; clocks(1);
        if (busy) $fatal(1,"Reset did not cancel playback");
        reset=0; clocks(5);
        if (busy) $fatal(1,"Reset restarted an earlier beep");

        // Check real button debounce, switch synchronisation and physical mapping.
        btnD=0; clocks(20);
        if (JC[1]!==1'b1 || JC[2]!==1'b0 || JC[3]!==1'b1)
            $fatal(1,"AMP2 gain/NC/shutdown mapping incorrect");
        count_top_pwm(ones);
        if (ones!=128) $fatal(1,"JC1 does not carry centred idle PWM");
        btnR=1; wait_top_beep(); clocks(4400);
        if (dut.audio_busy || top_starts!=1) $fatal(1,"Held BTNR repeated the beep");
        if (dut.game_state!=`LP_BUILD || !dut.build_valid || dut.mass_units!=13)
            $fatal(1,"Audio test changed the construction/game state");
        btnR=0; clocks(12); btnR=1; wait_top_beep();
        sw=2'b11; clocks(6);
        if (JC[3]!==1'b0 || dut.audio_busy || !dut.engine_enabled)
            $fatal(1,"SW1 mute did not shut down AMP2 independently of SW0");
        sw=0; clocks(8);
        if (dut.audio_busy || JC[3]!==1'b1 || top_starts!=2)
            $fatal(1,"Unmute resumed cancelled audio or held BTNR");

        btnR=0; clocks(12); sw=2'b10; clocks(6); btnR=1; clocks(20);
        if (dut.audio_busy || JC[3]!==1'b0) $fatal(1,"Muted button press played audio");
        sw=0; clocks(8);
        if (dut.audio_busy || top_starts!=2) $fatal(1,"Muted press was queued");
        btnR=0; clocks(12); btnR=1; wait_top_beep(); btnR=0;
        btnD=1; clocks(8);
        if (dut.audio_busy || JC[3]!==1'b0) $fatal(1,"Board reset failed to stop AMP2");
        btnD=0; clocks(15);
        if (dut.audio_busy || JC[3]!==1'b1 || dut.game_state!=`LP_BUILD)
            $fatal(1,"Audio did not recover quietly after reset");
        $display("PASS audio_beep_tb: PWM duty/tone timing, duration, busy requests, mute/reset, held button, JC mapping and independent game controls");
        $finish;
    end
    initial begin #500000; $fatal(1,"Audio beep test timed out"); end
endmodule
