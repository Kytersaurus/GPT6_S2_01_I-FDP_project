// Owner: Role 1 - Kaushal. Sound priorities and real game-event wiring.
`timescale 1ns / 1ps
`include "game_defs.vh"
module game_audio_tb;
    reg clk=0, reset=1, mute=0, cancel=0;
    reg [5:0] events=0;
    wire start, busy, pwm;
    wire [2:0] id, active;
    integer starts=0, i, before_starts, waited;
    always #5 clk=~clk;
    sound_controller control (
        .clk(clk),.reset(reset),.mute(mute),.cancel(cancel),
        .launch_event(events[0]),.pop_event(events[1]),
        .collision_event(events[2]),.explosion_event(events[3]),
        .success_event(events[4]),.failure_event(events[5]),
        .busy(busy),.active_sound(active),.sound_start(start),.sound_id(id)
    );
    sound_generator #(.NOTE_CYCLES(1024),.FADE_CYCLES(8)) player (
        .master_volume(3'd4),
        .clk(clk),.reset(reset),.mute(mute),.cancel(cancel),.start(start),.sound_id(id),.bgm_sample(4'sd0),
        .busy(busy),.active_sound(active),.audio_pwm(pwm)
    );
    always @(posedge clk) if (!reset && start) starts=starts+1;

    reg btnD=1, btnC=0, btnU=0, btnR=0;
    reg [15:0] sw=0;
    reg [11:0] mx=0,my=0;
    reg ml=0,mr=0,me=0, tick=0, world=0, goal=0,hazard=0;
    reg response=0,ready=0,ground=0;
    reg signed [15:0] impact_vy=0;
    wire [15:0] led;
    wire [7:0] JA,JB;
    wire [3:0] JXADC;
    tri1 PS2Clk,PS2Data;
    integer top_starts=0;
    reg [2:0] last_top_sound=0;
    My_Top_Module #(.ENABLE_BGM(0),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2),
        .AUDIO_NOTE_CYCLES(1024),.AUDIO_FADE_CYCLES(8)) dut (
        .clk(clk),.btnC(btnC),.btnU(btnU),.btnR(btnR),.btnL(1'b0),.btnD(btnD),.sw(sw),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.led(led),.JA(JA),.JB(JB),.JXADC(JXADC)
    );
    initial begin
        force dut.mouse_x=mx; force dut.mouse_y=my;
        force dut.mouse_left=ml; force dut.mouse_right=mr; force dut.mouse_event=me;
        force dut.physics_tick=tick; force dut.world_valid=world;
        force dut.goal_hit=goal; force dut.hazard_hit=hazard; force dut.out_of_bounds=1'b0;
    end
    always @(posedge clk) if (!dut.reset && dut.sound_start) begin
        top_starts=top_starts+1; last_top_sound=dut.sound_id;
    end
    // Test-only gameplay fixture; the hardware builder starts empty.
    task build_test_vehicle;
        begin
            dut.u_builder.build_grid = {
                `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
                `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_EMPTY,
                `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY
            };
            dut.u_builder.build_frames = 9'b000111000;
            clocks(2);
        end
    endtask
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task packet;
        input [11:0] x,y;
        input l,r;
        begin mx=x; my=y; ml=l; mr=r; me=1; clocks(1); me=0; clocks(2); end
    endtask
    task click;
        input [11:0] x,y;
        begin packet(x,y,0,0); packet(x,y,1,0); packet(x,y,0,0); end
    endtask
    task wait_quiet;
        begin
            waited=0;
            while (dut.audio_busy && waited<8000) begin clocks(1); waited=waited+1; end
            if (dut.audio_busy) $fatal(1,"Connected sound did not finish");
            clocks(300);
        end
    endtask
    task launch;
        begin
            btnC=1; clocks(14); btnC=0; clocks(14);
            if (dut.game_state!=`LP_RUN || last_top_sound!=`LP_SOUND_LAUNCH)
                $fatal(1,"Accepted launch did not trigger launch audio");
            click(48,59);
        end
    endtask
    task result;
        input won,failed;
        begin
            tick=1; clocks(1); tick=0;
            waited=0;
            while (!dut.world_ready && waited<64) begin clocks(1); waited=waited+1; end
            if (!dut.world_ready) $fatal(1,"No movement update for result");
            clocks(64); goal=won; hazard=failed; world=1; clocks(3);
            world=0; goal=0; hazard=0; clocks(2);
        end
    endtask
    initial begin
        clocks(4); reset=0; clocks(2);
        events=6'b111111; clocks(1);
        if (active!=`LP_SOUND_FAILURE || starts!=1) $fatal(1,"Simultaneous priority wrong");
        clocks(6000);
        if (busy || starts!=1) $fatal(1,"Held event replayed");
        events=0; clocks(1);
        // Every adjacent priority preempts; the reverse request is discarded.
        for (i=1;i<=6;i=i+1) begin
            events=1<<(i-1); clocks(1);
            if (active!=i) $fatal(1,"Priority %0d did not start/preempt",i);
            events=0; clocks(1);
            before_starts=starts; events=1; clocks(1); events=0; clocks(1);
            if (i>1 && starts!=before_starts) $fatal(1,"Lower priority interrupted sound");
        end
        before_starts=starts; clocks(6000);
        if (busy || starts!=before_starts) $fatal(1,"Dropped requests were queued");
        mute=1; events=6'b100000; clocks(2); mute=0; clocks(2);
        if (busy || starts!=before_starts) $fatal(1,"Unmute replayed held event");
        events=0; clocks(1); events=1; clocks(1);
        if (active!=`LP_SOUND_LAUNCH) $fatal(1,"Fresh event after mute ignored");
        cancel=1; clocks(1); cancel=0; clocks(2);
        if (busy) $fatal(1,"Cancel resumed old sound");
        events=0; clocks(1);

        btnD=0; clocks(280); build_test_vehicle();
        if (JXADC[1]!==1 || JXADC[2]!==0 || JXADC[3]!==1 || dut.u_audio.pwm_level!=128)
            $fatal(1,"AMP2 pins/idle PWM incorrect");
        // Selection, placement, removal, edit and engine switch are deliberately silent.
        click(74,8); click(12,12); packet(12,12,0,1); packet(12,12,0,0);
        btnU=1; sw=1; clocks(20); btnU=0; sw=0; clocks(20);
        if (top_starts!=0 || dut.audio_busy || dut.u_audio.pwm_level!=128)
            $fatal(1,"Ordinary controls triggered an unintended click sound");
        // U now opens the diary; return through its real BACK button before editing.
        if (dut.game_state!=`LP_GUIDE) $fatal(1,"U did not open the diary");
        click(10,59);
        if (dut.game_state!=`LP_BUILD || top_starts!=0) $fatal(1,"Diary navigation made a sound");
        // Missing pig prevents launch, so pressing C must also remain silent.
        packet(28,28,0,1); packet(28,28,0,0);
        btnC=1; clocks(14); btnC=0; clocks(14);
        if (dut.game_state!=`LP_BUILD || top_starts!=0) $fatal(1,"Rejected launch made a sound");
        click(74,18); click(28,28);
        click(74,48); click(12,12); click(28,12);
        if (!dut.build_valid || dut.balloon_count!=2) $fatal(1,"Test construction failed");
        launch(); wait_quiet(); before_starts=top_starts;
        click(32,10); clocks(3);
        if (last_top_sound!=`LP_SOUND_POP || top_starts!=before_starts+1 || dut.balloon_count!=1)
            $fatal(1,"Balloon pop did not trigger pop audio");
        wait_quiet(); before_starts=top_starts;

        // Hard landing: audio_was_grounded is driven directly by top's response pipeline.
        force dut.response_valid=1; force dut.response_ready=1;
        force dut.grounded=1; force dut.proposed_vy=16'sd256; clocks(1);
        release dut.response_valid; release dut.response_ready;
        release dut.grounded; release dut.proposed_vy;
        clocks(3);
        if (last_top_sound!=`LP_SOUND_COLLISION || top_starts!=before_starts+1)
            $fatal(1,"Hard landing did not trigger landing audio");

        // Gentle contact / continuous rolling must remain quiet.
        before_starts=top_starts;
        force dut.response_valid=1; force dut.response_ready=1;
        force dut.grounded=1; force dut.proposed_vy=16'sd32; clocks(1);
        release dut.response_valid; release dut.response_ready;
        release dut.grounded; release dut.proposed_vy;
        clocks(3);
        if (top_starts!=before_starts) $fatal(1,"Gentle landing triggered landing audio");
        before_starts=top_starts;
        force dut.response_valid=1; force dut.response_ready=1;
        force dut.grounded=1; force dut.proposed_vy=16'sd256; clocks(1);
        release dut.response_valid; release dut.response_ready;
        release dut.grounded; release dut.proposed_vy;
        clocks(3);
        if (top_starts!=before_starts) $fatal(1,"Continuous ground contact re-triggered landing audio");
        wait_quiet(); before_starts=top_starts;

        // TNT explosion triggers explosion sound.
        force dut.explosion_sound_event=1; clocks(1); force dut.explosion_sound_event=0; clocks(3);
        release dut.explosion_sound_event;
        if (last_top_sound!=`LP_SOUND_EXPLOSION || top_starts!=before_starts+1)
            $fatal(1,"TNT explosion did not trigger explosion audio");
        wait_quiet(); before_starts=top_starts;

        // Success result jingle.
        result(1,0); clocks(3);
        if (last_top_sound!=`LP_SOUND_SUCCESS || top_starts!=before_starts+1)
            $fatal(1,"Success did not trigger success audio");
        wait_quiet(); before_starts=top_starts;

        // Retry and fail to test failure sound.
        btnC=1; clocks(14); btnC=0; clocks(14);
        if (dut.game_state!=`LP_RUN) $fatal(1,"Retry failed to return to RUN");
        wait_quiet(); before_starts=top_starts;
        result(0,1); clocks(3);
        if (last_top_sound!=`LP_SOUND_FAILURE || top_starts!=before_starts+1)
            $fatal(1,"Failure did not trigger failure audio");

        // Retry and edit clear audio immediately.
        btnC=1; clocks(1);
        if (dut.u_sound_control.sound_id!=`LP_SOUND_NONE && dut.audio_busy)
            $fatal(1,"Retry did not cancel audio");
        btnC=0; clocks(20);
        btnU=1; clocks(1);
        if (dut.u_sound_control.sound_id!=`LP_SOUND_NONE && dut.audio_busy)
            $fatal(1,"Edit did not cancel audio");
        btnU=0; clocks(20);

        // BTNR is reserved and must remain silent.
        before_starts=top_starts;
        btnR=1; clocks(14); btnR=0; clocks(14);
        if (top_starts!=before_starts) $fatal(1,"Reserved BTNR made a sound");

        $display("PASS game_audio_tb: priorities/preemption, held/muted suppression, no queue, silent controls, launch/pop/landing/results, retry/edit, BTNR, AMP2 mute/reset");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Audio top test timed out"); end
endmodule
