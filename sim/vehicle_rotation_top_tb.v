// The hardware top must publish the committed collision angle with its pose.
`timescale 1ns / 1ps
`include "game_defs.vh"
module vehicle_rotation_top_tb;
    reg clk=0, btnD=1, btnC=0;
    tri1 PS2Clk, PS2Data;
    integer waited, saw_nonzero=0;
    reg [511:0] held_snapshot;
    reg signed [19:0] final_x, final_y;
    always #5 clk=~clk;
    My_Top_Module #(
        .PHYSICS_CYCLES(128), .BUTTON_DEBOUNCE_CYCLES(2), .BUTTON_RELEASE_CYCLES(2)
    ) dut (
        .clk(clk),.btnC(btnC),.btnU(1'b0),.btnR(1'b0),.btnL(1'b0),.btnD(btnD),
        .sw(16'd0),.PS2Clk(PS2Clk),.PS2Data(PS2Data)
    );
    initial begin
        force dut.level_index=2'd2;
        force dut.left_frame=1'b1;
    end
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    initial begin
        clocks(20); btnD=0; clocks(300);
        dut.u_builder.build_grid={
            `LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
            `LP_PART_ENGINE,`LP_PART_PIG,`LP_PART_EMPTY,
            `LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_EMPTY
        };
        dut.u_builder.build_frames=9'b000111000;
        clocks(2); btnC=1; clocks(12); btnC=0;
        waited=0;
        while(dut.game_state!=`LP_RUN && waited<30000) begin clocks(1); waited=waited+1; end
        if(dut.game_state!=`LP_RUN || dut.vehicle_tilt!==4'sd0)
            $fatal(1,"Rotation top did not launch level with zero orientation");
        // Finish the spawn update, then provide a pose fixture on the actual
        // 1:1 Arch road. Orientation is never written or forced by this bench.
        clocks(200);
        waited=0;
        while(dut.u_physics.phase!=0 && waited<30000) begin clocks(1); waited=waited+1; end
        if(dut.u_physics.phase!=0) $fatal(1,"Rotation top never became idle");
        force dut.left_frame=1'b0;
        clocks(32); held_snapshot=dut.snapshot_out;
        dut.u_physics.vehicle_x=150*256;
        dut.u_physics.vehicle_y=44*256;
        dut.u_physics.velocity_x=0;
        dut.u_physics.velocity_y=0;
        waited=0;
        while(dut.vehicle_tilt!==4'sd4 && waited<500000 && dut.game_state==`LP_RUN) begin
            clocks(1); waited=waited+1;
            if(dut.vehicle_tilt!=0) saw_nonzero=1;
            if(dut.snapshot_out!==held_snapshot)
                $fatal(1,"Top snapshot changed away from a display frame boundary");
        end
        if(dut.game_state!=`LP_RUN || dut.vehicle_tilt!==4'sd4 || !saw_nonzero)
            $fatal(1,"Actual map failed to settle vehicle at 45 degrees: state=%0d tilt=%0d slope=%0d cycles=%0d",
                dut.game_state,dut.vehicle_tilt,dut.ground_slope,waited);
        // Freeze a result pose so the two clocks can publish one exact pair.
        // This force controls lifecycle only, never vehicle pose or angle.
        force dut.game_state=`LP_SUCCESS;
        final_x=dut.vehicle_x; final_y=dut.vehicle_y;
        clocks(40);
        if(dut.snapshot_out!==held_snapshot)
            $fatal(1,"A result bypassed the frame-boundary snapshot");
        force dut.left_frame=1'b1;
        clocks(1200);
        if(dut.draw_tilt!==4'sd4 || dut.draw_x!==final_x || dut.draw_y!==final_y ||
           dut.draw_state!==`LP_SUCCESS || dut.u_right_renderer.vehicle_tilt!==4'sd4)
            $fatal(1,"Committed rotation/pose was lost or mixed in the display transfer");
        btnD=1; release dut.game_state; clocks(24);
        if(dut.vehicle_tilt!==0 || dut.draw_tilt!==0 || dut.snapshot_out!==0)
            $fatal(1,"System reset retained vehicle or display orientation");
        btnD=0; clocks(400);
        if(dut.game_state!==`LP_BUILD || dut.vehicle_tilt!==0 || dut.draw_tilt!==0 ||
           dut.u_right_renderer.vehicle_tilt!==0)
            $fatal(1,"BUILD retained stale rotation after reset");
        release dut.left_frame; release dut.level_index;
        $display("PASS vehicle_rotation_top_tb: real map settles tilt, pose/angle frame transfer, renderer wiring and reset/BUILD clearing");
        $finish;
    end
    initial begin #20000000; $fatal(1,"Vehicle rotation top test timed out"); end
endmodule
