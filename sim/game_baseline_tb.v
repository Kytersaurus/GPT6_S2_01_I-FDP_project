// Owner: Shared integration - all roles.
`timescale 1ns / 1ps
`include "game_defs.vh"
module game_baseline_tb;
    reg clk=0, btnC=0, btnU=0, btnD=1;
    reg [2:0] sw=1;
    wire [15:0] led;
    wire [7:0] JA, JB;
    tri1 PS2Clk, PS2Data;
    integer cycles, launches=0, active_update=0;
    reg signed [15:0] stopped_x;
    always #5 clk=~clk;
    My_Top_Module #(
        .PHYSICS_CYCLES(24), .BUTTON_DEBOUNCE_CYCLES(2), .BUTTON_RELEASE_CYCLES(2)
    ) dut (
        .clk(clk), .btnC(btnC), .btnU(btnU), .btnR(1'b0), .btnL(1'b0),.btnD(btnD), .sw(sw),
        .PS2Clk(PS2Clk), .PS2Data(PS2Data), .led(led), .JA(JA), .JB(JB)
    );
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task wait_success;
        begin
            cycles=0;
            while (dut.game_state != `LP_SUCCESS && cycles < 12000) begin clocks(1); cycles=cycles+1; end
            if (dut.game_state != `LP_SUCCESS) $fatal(1,"No success: state=%0d x=%0d y=%0d",dut.game_state,dut.vehicle_x,dut.vehicle_y);
            if (dut.vehicle_y !== 16'sd8192) $fatal(1,"Vehicle penetrated ground");
        end
    endtask
    always @(negedge clk) begin
        if (dut.reset) active_update=0;
        else begin
            if (dut.move_valid && $isunknown({dut.proposed_x,dut.proposed_y,dut.proposed_vx,dut.proposed_vy}))
                $fatal(1,"Unknown movement: reverse=%b jump=%b mass=%d force=%d vx=%d rem=%d",dut.engine_reverse,dut.jump_press,dut.mass_units,dut.u_physics.step_thrust,dut.u_physics.step_vx,dut.u_physics.remainder_x);
            if (dut.launch_event) launches=launches+1;
            if (dut.step_start) begin
                if (active_update) $fatal(1,"Overlapping physics updates");
                active_update=1;
            end
            if (dut.movement_committed && !active_update) $fatal(1,"Unrequested movement commit");
            if (dut.update_release) active_update=0;
        end
    end
    initial begin
        clocks(20); btnD=0; clocks(280);
        if (dut.game_state !== `LP_BUILD || !dut.build_valid || dut.mass_units != 13) $fatal(1,"Invalid startup build");
        btnC=1;
        wait_success();
        stopped_x=dut.vehicle_x;
        clocks(100);
        if (launches != 1 || dut.game_state != `LP_SUCCESS || dut.vehicle_x != stopped_x)
            $fatal(1,"Held launch repeated or result movement did not freeze");
        btnC=0; clocks(12); btnC=1; clocks(12); btnC=0;
        wait_success();
        if (launches != 2) $fatal(1,"Retry did not initialise a fresh run");
        btnU=1; clocks(12); btnU=0; clocks(12);
        if (dut.game_state != `LP_BUILD) $fatal(1,"EDIT did not return to BUILD");
        sw=0; clocks(8); btnC=1; clocks(12); btnC=0; clocks(500);
        if (dut.game_state != `LP_RUN || dut.vehicle_x != 16'sd1024) $fatal(1,"Disabled engine still propelled vehicle");
        btnD=1; clocks(10); btnD=0; clocks(20);
        if (dut.game_state != `LP_BUILD || dut.vehicle_x != 16'sd1024) $fatal(1,"Reset did not restore startup");
        $display("PASS game_baseline_tb: launch, landing, goal, held input, retry, edit, engine off, reset, update sequencing");
        $finish;
    end
    initial begin #500000; $fatal(1,"Integration test timed out"); end
endmodule
