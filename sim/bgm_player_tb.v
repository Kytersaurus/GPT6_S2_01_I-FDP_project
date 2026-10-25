// Owner: Role 1 - Kaushal. Melody sequencing and shared-output sound priority.
`timescale 1ns / 1ps
`include "game_defs.vh"
module bgm_player_tb;
    reg clk=0,reset=1,enabled=1,mute=0,fast=0,start=0;
    reg [2:0] sound_id=0;
    wire busy,pwm;
    wire [2:0] active;
    wire signed [3:0] sample;
    integer saved_note,saved_count,waited;
    reg looped;
    always #5 clk=~clk;
    bgm_player #(.UNIT_CYCLES(2048),.FADE_CYCLES(8)) music (
        .clk(clk),.reset(reset),.enabled(enabled&&!mute),.pause(busy||start),.fast(fast),.audio_sample(sample)
    );
    sound_generator #(.TONE_HALF_CYCLES(512),.BEEP_CYCLES(2048),.NOTE_CYCLES(2048),.FADE_CYCLES(8)) effects (
        .clk(clk),.reset(reset),.mute(mute),.cancel(1'b0),.start(start),.sound_id(sound_id),
        .bgm_sample(sample),.busy(busy),.active_sound(active),.audio_pwm(pwm)
    );
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk);end
    endtask
    initial begin
        clocks(4);reset=0;clocks(300);
        if(music.half_cycles!=170262 || music.volume!=4 || sample!=-4 || effects.pwm_level!=124)
            $fatal(1,"First melody pitch/quiet amplitude/PWM routing incorrect");
        saved_note=music.note_index;saved_count=music.note_count;
        sound_id=`LP_SOUND_TEST;start=1;clocks(1);start=0;
        clocks(200);
        if(!busy || sample!=0 || music.note_index!=saved_note || music.note_count!=saved_count)
            $fatal(1,"Sound effect failed to pause music without losing its position");
        waited=0;while(busy && waited<3000) begin clocks(1);waited=waited+1;end
        clocks(300);
        if(busy || music.note_count<=saved_count || music.volume!=4 || effects.pwm_level!=124)
            $fatal(1,"Music failed to resume after an effect");
        mute=1;clocks(300);
        if(sample!=0 || busy || music.note_index!=0 || effects.pwm_level!=128)
            $fatal(1,"Mute did not silence/reset background and effects");
        mute=0;clocks(2);fast=1;#1;
        if(music.unit_cycles!=2048) $fatal(1,"Gameplay tempo incorrect");
        fast=0;enabled=0;clocks(2);enabled=1;
        // Check the two pickup notes and the familiar E-C opening, then a complete loop.
        clocks(2048);
        if(music.note_index!=1 || music.half_cycles!=160706) $fatal(1,"Pickup timing/pitch incorrect");
        clocks(2048);
        if(music.note_index!=2 || music.half_cycles!=151686) $fatal(1,"Melody opening incorrect");
        waited=0;looped=0;
        while(!looped && waited<350000) begin
            saved_note=music.note_index;clocks(1);waited=waited+1;
            if(sample>4 || sample< -4 || $isunknown(pwm)) $fatal(1,"Unsafe/unknown background output");
            if(saved_note==74 && music.note_index==2) looped=1;
        end
        if(!looped)
            $fatal(1,"Melody loop duration incorrect: %0d clocks",waited);

        // Test fast/RUN mode with original melody and softer volume (volume <= 2)
        fast = 1; clocks(2);
        if(music.note_index!=0) $fatal(1,"RUN mode transition did not reset note_index");
        clocks(300);
        if(music.volume > 2) $fatal(1,"RUN mode melody volume too loud (not soft)");

        if(music.half_cycles!=191113) $fatal(1,"Original RUN opening pitch incorrect");
        clocks(2*2048*7);
        if(music.note_index!=7 || sample!=0) $fatal(1,"RUN melody rest missing");
        reset=1;clocks(1);
        if(sample!=0 || music.note_index!=0 || music.note_count!=0) $fatal(1,"Reset retained melody state");
        $display("PASS bgm_player_tb: Entertainer pitches/durations/loop, quiet PWM, effect pause/resume, gameplay tempo, mute and reset");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Background music test timed out");end
endmodule
