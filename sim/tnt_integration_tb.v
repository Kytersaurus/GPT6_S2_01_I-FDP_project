// Owner: Shared integration - Role 1 damage/audio with Role 3 TNT and Role 4 outcomes.
`timescale 1ns / 1ps
`include "game_defs.vh"
module tnt_integration_tb;
    reg clk=0, btnD=1, btnC=0, tick=0, committed=0, pop=0;
    reg signed [`LP_COORD_BITS-1:0] x=1024, y=8192, old_x=1024, old_y=8192;
    wire [15:0] led;
    wire [7:0] JA,JB;
    tri1 PS2Clk,PS2Data;
    integer waited, explosions=0;
    reg [26:0] saved_grid;
    reg [8:0] saved_frames;
    My_Top_Module #(.ENABLE_BGM(0),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2),
        .AUDIO_BEEP_CYCLES(1024),.AUDIO_NOTE_CYCLES(1024),.AUDIO_FADE_CYCLES(8)) dut (
        .clk(clk),.btnD(btnD),.btnC(btnC),.btnU(1'b0),.btnL(1'b0),.btnR(1'b0),.sw(16'd1),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.led(led),.JA(JA),.JB(JB),.JXADC()
    );
    always #5 clk=~clk;
    always @(posedge clk) if (!dut.reset && dut.explosion_sound_event) explosions=explosions+1;
    initial begin
        // Only movement and map data are fixtures. Damage, outcomes, sound and
        // animation use their actual shared connections and handshakes.
        force dut.physics_tick=tick;
        force dut.movement_committed=committed;
        force dut.move_valid=1'b0;
        force dut.vehicle_x=x; force dut.vehicle_y=y;
        force dut.previous_x=old_x; force dut.previous_y=old_y;
        force dut.tnt_count=3'd2;
        force dut.tnt_positions={32'd0,8'd32,8'd88,8'd48,8'd60};
        force dut.pop_req=pop; force dut.pop_cell=4'd0;
    end
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    task press_c;
        begin btnC=1; clocks(12); btnC=0; clocks(12); end
    endtask
    task begin_step;
        begin
            tick=1; clocks(1); tick=0;
            if (!dut.world_ready) $fatal(1,"Game did not reserve a movement step");
        end
    endtask
    task commit_pose;
        input integer new_x;
        begin
            old_x=x; x=new_x;
            committed=1; clocks(1); committed=0;
        end
    endtask
    task finish_step;
        begin
            waited=0;
            while (dut.world_ready && waited<128) begin clocks(1); waited=waited+1; end
            if (dut.world_ready) $fatal(1,"TNT/world handshake stalled");
            clocks(3);
        end
    endtask
    initial begin
        clocks(20); btnD=0; clocks(280);
        dut.u_builder.build_grid={
            `LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
            `LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,
            `LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_BALLOON};
        dut.u_builder.build_frames=9'b000111000;
        clocks(3); saved_grid=dut.build_grid; saved_frames=dut.build_frames;
        if (!dut.build_valid) $fatal(1,"Fixture build invalid");
        press_c();
        if (dut.game_state!=`LP_RUN) $fatal(1,"Launch failed");

        // No TNT contact must still release physics for the next movement.
        begin_step(); commit_pose(4*256); finish_step();
        if (explosions!=0 || dut.game_state!=`LP_RUN) $fatal(1,"False explosion/result");

        // Queue a balloon click during a movement which destroys the front wheel.
        begin_step(); pop=1; clocks(1); pop=0;
        commit_pose(37*256); finish_step();
        if (explosions!=1 || dut.tnt_intact[0] || dut.intact_mask[8] ||
            dut.frame_intact_mask[5] || dut.intact_mask[0] || !dut.intact_mask[3] || !dut.pig_alive)
            $fatal(1,"TNT and queued pop did not both reach the builder");
        if (dut.blast_phase[1:0]==0) $fatal(1,"Explosion animation was not triggered");
        if (dut.build_grid!==saved_grid || dut.build_frames!==saved_frames ||
            dut.frames_left!=2 || dut.wheels_left!=0 || dut.balloons_left!=1)
            $fatal(1,"Runtime damage changed saved build or refunded inventory");

        // Pig reaches the goal and is destroyed on the same movement. Failure wins.
        begin_step(); commit_pose(80*256); finish_step();
        if (explosions!=2 || dut.game_state!=`LP_FAIL || dut.fail_reason!=`LP_FAIL_PIG ||
            dut.pig_alive || dut.frame_intact_mask[4])
            $fatal(1,"Goal was decided before TNT pig/frame damage");
        if (dut.active_sound!=`LP_SOUND_FAILURE) $fatal(1,"Pig death sound did not take priority");

        // Retry restores both layers and TNT without a new explosion.
        press_c();
        if (dut.game_state!=`LP_RUN || !dut.pig_alive || dut.frame_intact_mask!==saved_frames ||
            !dut.intact_mask[0] || !dut.intact_mask[8] || dut.tnt_intact!=4'b1111 || explosions!=2)
            $fatal(1,"Retry did not restore the saved vehicle and TNT");
        $display("PASS tnt_integration_tb: damage, queued pop, animation/audio, no-contact release, death before goal and retry");
        $finish;
    end
    initial begin #200000; $fatal(1,"TNT integration timed out"); end
endmodule
