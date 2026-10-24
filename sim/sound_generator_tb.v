// Owner: Role 1 - Kaushal. Tone profiles, note timing, fades and PWM frames.
`timescale 1ns / 1ps
`include "game_defs.vh"
module sound_generator_tb;
    reg clk=0, reset=1, mute=0, cancel=0, start=0;
    reg [2:0] id=0;
    wire busy, pwm;
    wire [2:0] active;
    integer i, n, high_cycles, expected_level;
    always #5 clk=~clk;
    sound_generator #(.TONE_HALF_CYCLES(512), .BEEP_CYCLES(4096),
                      .NOTE_CYCLES(2048), .FADE_CYCLES(16)) unit (
        .clk(clk),.reset(reset),.mute(mute),.cancel(cancel),.start(start),.sound_id(id),.bgm_sample(4'sd0),
        .busy(busy),.active_sound(active),.audio_pwm(pwm)
    );
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task request;
        input [2:0] sound;
        begin id=sound; start=1; clocks(1); start=0; end
    endtask
    task pwm_frame;
        begin
            while (unit.pwm_count != 0) clocks(1);
            expected_level=unit.pwm_level; high_cycles=0;
            for (n=0;n<256;n=n+1) begin
                if (unit.pwm_level != expected_level) $fatal(1,"Duty changed inside a PWM frame");
                if (pwm === 1'b1) high_cycles=high_cycles+1;
                else if (pwm !== 1'b0) $fatal(1,"Unknown PWM output");
                clocks(1);
            end
            if (high_cycles != expected_level) $fatal(1,"PWM duty count mismatch");
        end
    endtask
    task profile;
        input [2:0] sound;
        input integer length, notes, hz0, hz1, hz2;
        integer cycle, expected_note, expected_half;
        begin
            request(sound);
            for (cycle=0;cycle<length*notes;cycle=cycle+1) begin
                expected_note=cycle/length;
                expected_half=(expected_note==0) ? hz0 : ((expected_note==1) ? hz1 : hz2);
                if (!busy || active!=sound || unit.note_index!=expected_note ||
                    unit.duration_count!=cycle%length || unit.half_cycles!=expected_half)
                    $fatal(1,"Sound %0d profile/timing mismatch at cycle %0d",sound,cycle);
                if (cycle%length==0 && unit.volume!=0) $fatal(1,"Note did not start at zero volume");
                if (cycle%length==176 && unit.volume!=11) $fatal(1,"Fade-in did not reach volume eleven");
                if (cycle%length==length-16 && unit.volume!=0) $fatal(1,"Fade-out did not reach silence");
                if (unit.volume>11) $fatal(1,"Audio amplitude exceeded its quiet limit");
                clocks(1);
            end
            if (busy || active!=`LP_SOUND_NONE) $fatal(1,"Sound %0d ended at the wrong time",sound);
        end
    endtask
    initial begin
        clocks(4); reset=0; clocks(2); pwm_frame();
        if (expected_level!=128) $fatal(1,"Idle PWM is not centred");
        profile(`LP_SOUND_TEST,4096,1,512,0,0);
        profile(`LP_SOUND_LAUNCH,2048,2,75758,50505,0);
        profile(`LP_SOUND_POP,1024,1,31250,0,0);
        profile(`LP_SOUND_COLLISION,1536,1,227273,0,0);
        profile(`LP_SOUND_EXPLOSION,2048,3,312500,454545,714286);
        profile(`LP_SOUND_SUCCESS,2560,3,75758,56818,37879);
        profile(`LP_SOUND_FAILURE,3584,3,113636,151515,227273);

        // The test tone has real half-periods within this shortened simulation.
        request(`LP_SOUND_TEST); clocks(256);
        if (unit.tone_high || unit.tone_count!=256 || unit.volume!=11) $fatal(1,"Tone counter/fade wrong");
        clocks(255);
        if (unit.tone_high || unit.tone_count!=511) $fatal(1,"Tone toggled too early");
        clocks(1);
        if (!unit.tone_high || unit.tone_count!=0) $fatal(1,"Tone did not toggle at its exact half-period");
        while (unit.pwm_count!=0 || unit.pwm_level!=117) clocks(1);
        pwm_frame();
        if (expected_level!=117) $fatal(1,"Low half-cycle duty wrong");
        while (unit.pwm_count!=0 || unit.pwm_level!=139) clocks(1);
        pwm_frame();
        if (expected_level!=139) $fatal(1,"High half-cycle duty wrong");
        request(`LP_SOUND_FAILURE);
        if (active!=`LP_SOUND_FAILURE || unit.note_index!=0 || unit.duration_count!=0)
            $fatal(1,"Preemption did not restart the chosen sound");
        mute=1; clocks(1);
        if (busy) $fatal(1,"Mute did not cancel sound");
        request(`LP_SOUND_SUCCESS); mute=0; clocks(300); pwm_frame();
        if (busy || expected_level!=128) $fatal(1,"Muted request replayed or retained audio duty");
        request(`LP_SOUND_LAUNCH); clocks(200); cancel=1; clocks(1); cancel=0; clocks(300);
        if (busy || active!=0) $fatal(1,"Cancel retained an earlier sound");
        request(`LP_SOUND_POP); reset=1; clocks(1); reset=0; clocks(300);
        if (busy || unit.pwm_level!=128) $fatal(1,"Reset failed to return to silence");
        request(`LP_SOUND_NONE);
        if (busy) $fatal(1,"NONE started playback");
        $display("PASS sound_generator_tb: seven profiles, exact note durations/pitches, fades, PWM frames, preemption, mute/cancel/reset");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Sound generator test timed out"); end
endmodule
