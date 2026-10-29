// Connected top-level checks: real cave spawn, TNT/world sequencing and display.
`timescale 1ns / 1ps
`include "game_defs.vh"
module cave_map_integration_tb;
    reg clk=0, btnD=1, btnC=0;
    reg [1:0] selected_level=`LP_LEVEL_ARCH;
    tri1 PS2Clk, PS2Data;
    integer waited;
    always #5 clk=~clk;
    My_Top_Module #(
        .PHYSICS_CYCLES(128), .BUTTON_DEBOUNCE_CYCLES(2), .BUTTON_RELEASE_CYCLES(2)
    ) dut (
        .clk(clk), .btnC(btnC), .btnU(1'b0), .btnR(1'b0), .btnL(1'b0),
        .btnD(btnD), .sw(16'd0), .PS2Clk(PS2Clk), .PS2Data(PS2Data)
    );
    initial begin
        force dut.level_index=selected_level;
        force dut.left_frame=1'b1;
    end
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    task start_cave;
        input [1:0] level;
        begin
            btnD=1; btnC=0; selected_level=level;
            clocks(20); btnD=0; clocks(300);
            dut.u_builder.build_grid={
                `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
                `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_EMPTY,
                `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY
            };
            dut.u_builder.build_frames=9'b000111000;
            clocks(2); btnC=1; clocks(12); btnC=0;
            waited=0;
            while (dut.game_state!=`LP_RUN && waited<200000) begin clocks(1); waited=waited+1; end
            if (dut.game_state!=`LP_RUN || dut.vehicle_y !== (level==`LP_LEVEL_ARCH ? 20'sd19456 : 20'sd45568))
                $fatal(1,"Cave launch/spawn failed: state=%d y=%d",dut.game_state,dut.vehicle_y);
            clocks(200);
            if (dut.game_state!=`LP_RUN || dut.out_of_bounds)
                $fatal(1,"Cave failed at its valid spawn");
            waited=0;
            while (dut.u_physics.phase!=0 && waited<200000) begin clocks(1); waited=waited+1; end
            if (dut.u_physics.phase!=0) $fatal(1,"Movement did not return to idle");
        end
    endtask
    task check_result;
        input integer pose_x, pose_y;
        input [2:0] expected_state;
        begin
            // Place at the test pose between updates. The next real movement
            // still passes through collision, TNT completion and world outcomes.
            dut.u_physics.vehicle_x=pose_x;
            dut.u_physics.vehicle_y=pose_y;
            dut.u_physics.velocity_x=0;
            dut.u_physics.velocity_y=0;
            waited=0;
            while (dut.game_state==`LP_RUN && waited<200000) begin clocks(1); waited=waited+1; end
            if (dut.game_state!==expected_state)
                $fatal(1,"Cave result failed: state=%d goal=%b bounds=%b",dut.game_state,dut.goal_hit,dut.out_of_bounds);
            if (expected_state==`LP_FAIL && dut.fail_reason!==`LP_FAIL_BOUNDS)
                $fatal(1,"Wrong cave failure reason");
            clocks(1000);
            if (dut.draw_x!==dut.vehicle_x || dut.draw_y!==dut.vehicle_y || dut.draw_level!==selected_level)
                $fatal(1,"Wide cave pose was lost in the display snapshot");
        end
    endtask
    initial begin
        // This injected Arch pose is inside terrain: this is a goal-wiring
        // fixture, not a playable solution for the current 24x24 footprint.
        start_cave(`LP_LEVEL_ARCH); check_result(600*256,462*256,`LP_SUCCESS);
        // The Flight goal fixture uses a genuinely clear, supported ROM pose.
        start_cave(`LP_LEVEL_FLIGHT); check_result(757*256,32*256,`LP_SUCCESS);
        start_cave(`LP_LEVEL_ARCH); check_result(956*256,100*256,`LP_FAIL);
        start_cave(`LP_LEVEL_FLIGHT); check_result(890*256,100*256,`LP_FAIL);
        $display("PASS cave_map_integration_tb: real cave spawns, success/bounds results and wide display snapshots");
        $finish;
    end
    initial begin #30000000; $fatal(1,"Cave map integration test timed out"); end
endmodule
