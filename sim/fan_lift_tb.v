`timescale 1ns / 1ps
`include "game_defs.vh"
// Future downward-blowing fans use world-up force. No builder or sprite is needed.
module fan_lift_tb;
    reg clk=0, reset=1, init=0, step=0, release_step=0;
    reg [2:0] state=`LP_BUILD;
    reg [7:0] mass=8;
    reg [3:0] lift_count=0, balloons=0;
    reg signed [4:0] horizontal_count=0;
    reg fan_on=0, use_moments=0, contact=0, keep_velocity=0;
    reg accept_move=0, response=0;
    reg [26:0] grid=0;
    reg [8:0] frames=0, alive=0, lift_mask=0, facing=0;
    reg signed [4:0] accepted_tilt=0;
    reg signed [7:0] terrain_slope=0;
    wire valid, ready, committed;
    wire signed [19:0] nx,ny;
    wire signed [15:0] vx,vy;
    wire signed [4:0] next_tilt;
    integer waited, tests=0, i; `include "rotation_geometry.vh"
    always #5 clk=~clk;
    physics_engine dut(.clk(clk),.reset(reset),.run_init(init),.game_state(state),
        .spawn_x(20'sd8192),.spawn_y(20'sd8192),.step_start(step),.update_release(release_step),
        .wheel_count(4'd0),.engine_count(4'd0),.balloon_count(balloons),.mass_units(mass),
        .engine_enabled(1'b0),.engine_reverse(1'b0),.jump_press(1'b0),.boost_req(1'b0),
        .moments_enabled(use_moments),.build_grid(grid),.build_frames(frames),
        .intact_mask(alive),.frame_intact_mask(frames),.build_facing_left(facing),
        .fan_lift_mask(lift_mask),.live_lift_fan_count(lift_count),
        .fan_balance(horizontal_count),.fan_enabled(fan_on),
        .move_valid(valid),.move_ready(accept_move),.proposed_x(nx),.proposed_y(ny),
        .proposed_vx(vx),.proposed_vy(vy),.proposed_tilt(next_tilt),
        .response_valid(response),.response_ready(ready),.corrected_x(nx),.corrected_y(ny),
        .corrected_vx(keep_velocity ? vx : 16'sd0),.corrected_vy(keep_velocity ? vy : 16'sd0),
        .grounded(contact),.ground_slope(terrain_slope),.corrected_tilt(accepted_tilt),
        .movement_committed(committed));

    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task restart;begin
        state=`LP_INIT_RUN;init=1;clocks(2);init=0;state=`LP_RUN;clocks(1);
    end endtask
    task begin_step;begin step=1;clocks(1);step=0;end endtask
    task request;begin
        waited=0;while(!valid && waited<2000) begin clocks(1);waited=waited+1;end
        if(!valid) $fatal(1,"Lift fan movement timeout");
    end endtask
    task finish_step;begin
        accept_move=1;clocks(1);accept_move=0;
        if(!ready) $fatal(1,"Lift fan collision handshake missing");
        response=1;clocks(1);response=0;
        if(!committed) $fatal(1,"Lift fan move not committed");
        release_step=1;clocks(1);release_step=0;
    end endtask
    task check_step;input integer ex;input integer ey;begin
        begin_step();request();tests=tests+1;
        if(vx!=ex || vy!=ey)
            $fatal(1,"Lift fan force mismatch: vx=%0d vy=%0d expected %0d %0d",vx,vy,ex,ey);
        finish_step();
    end endtask
    task put;input integer cell_id;input [2:0] kind;begin
        grid[cell_id*3 +: 3]=kind;alive[cell_id]=1;
    end endtask
    initial begin
        clocks(3);reset=0;fan_on=1;lift_count=1;restart();
        // Both translations use the same force/mass model; lift has no x force.
        check_step(0,0);
        horizontal_count=1;check_step(-8,0);
        horizontal_count=-1;check_step(8,0);
        lift_count=2;horizontal_count=0;check_step(0,-32);
        fan_on=0;check_step(0,32);
        fan_on=1;lift_count=0;check_step(0,32);
        mass=4;lift_count=1;restart();check_step(0,-32);
        mass=16;restart();check_step(0,16);
        // The largest legal 3x3 count must not wrap the signed force. The
        // velocity cap also clears a fraction which could otherwise persist.
        mass=8;lift_count=9;restart();check_step(0,-256);
        mass=4;restart();check_step(0,-512);
        if(dut.pending_remainder_y!=0) $fatal(1,"Clipped lift retained a vertical fraction");
        mass=255;restart();check_step(0,23);lift_count=1;
        // Non-integral force division retains its signed fraction over updates.
        mass=6;keep_velocity=1;restart();
        check_step(0,-10);check_step(0,-21);check_step(0,-32);
        keep_velocity=0;
        // Live menu/damage changes cannot alter an update already sampled.
        mass=8;lift_count=1;fan_on=1;restart();begin_step();
        lift_count=4;fan_on=0;request();
        if(vx!=0 || vy!=0) $fatal(1,"Lift fan count/enable was not sampled");
        clocks(5);if(!valid || vy!=0) $fatal(1,"Stalled lift fan output changed");
        finish_step();check_step(0,32);
        fan_on=1;lift_count=1;
        // A low-mass arithmetic fixture proves that upward force detaches from
        // remembered contact rather than being discarded by ground handling.
        mass=1;contact=1;restart();fan_on=0;check_step(0,32);
        fan_on=1;check_step(0,-224);contact=0;
        // Ramp gravity is projected from the remaining weight. Partial lift
        // halves it; neutral or upward net force cannot add downhill speed.
        mass=16;contact=1;
        for(i=-16;i<=16;i=i+32) begin
            terrain_slope=i;fan_on=0;lift_count=1;restart();check_step(0,32);
            check_step(i,32);fan_on=1;check_step(i >>> 1,16);
            lift_count=2;check_step(0,0);lift_count=3;check_step(0,-16);
        end
        terrain_slope=0;contact=0;
        // A possible future cart: pig/frame, two lift fans and one balloon.
        // g=8 and fan force=512/9, so it can rise with its actual part masses.
        use_moments=1;mass=9;balloons=1;lift_count=2;
        frames=9'b000010000;put(4,`LP_PART_PIG);put(3,`LP_PART_FAN);
        put(5,`LP_PART_FAN);put(1,`LP_PART_BALLOON);lift_mask=9'b000101000;
        contact=1;fan_on=0;restart();check_step(0,8);
        fan_on=1;check_step(0,-48);contact=0;
        // Translation is world-up at all 32 angles, independent of facing.
        balloons=0;mass=8;grid=0;alive=0;
        put(4,`LP_PART_PIG);put(3,`LP_PART_FAN);put(5,`LP_PART_FAN);
        for(i=-16;i<16;i=i+1) begin
            accepted_tilt=i;facing=i[0] ? 9'h1ff : 9'd0;
            fan_on=0;restart();check_step(0,32);
            fan_on=1;check_step((2*$signed(rotation_sin(i)))/8,32+(-2*$signed(rotation_cos(i)))/8);
            if(dut.u_moments.torque_q10!=0)
                $fatal(1,"Balanced lift fans spun at tilt %0d",i);
        end
        // The caller removes a broken fan from its live count and mask.
        accepted_tilt=0;alive[3]=0;lift_mask[3]=0;lift_count=1;mass=6;
        restart();check_step(0,-10);
        if(dut.u_moments.torque_q10>=0)
            $fatal(1,"Surviving right lift fan lost its negative moment");
        $display("PASS fan_lift_tb: %0d updates; world-up lift, mass/remainders, sampling, contact launch, both axes, facing and runtime damage",tests);
        $finish;
    end
    initial begin #3000000;$fatal(1,"Lift fan physics timeout");end
endmodule

// Per-cell torque tests are independent of the aggregate live fan count.
module fan_lift_moments_tb;
    reg clk=0,reset=1,start=0,accept=0,pivot_start=0,pivot_ready=0;
    reg fan_on=1,grounded=0,contact_valid=0;
    reg signed [9:0] contact_left=0,contact_right=0;
    reg [26:0] grid=0;
    reg [8:0] frames=0,alive=0,lift_mask=0,facing=0;
    reg signed [4:0] tilt=0;
    wire valid,pivot_valid;
    wire signed [23:0] torque;
    wire signed [15:0] accel;
    wire signed [15:0] gravity;
    wire [15:0] support_negative,support_positive;
    wire [7:0] mass;
    integer waited,tests=0,angle,reference_torque,reference_accel,expected_arm,expected_torque;
    integer reference_negative,reference_positive,reference_gravity;
    `include "rotation_geometry.vh"
    always #5 clk=~clk;
    vehicle_moments dut(.clk(clk),.reset(reset),.start(start),.build_grid(grid),
        .build_frames(frames),.intact_mask(alive),.frame_intact_mask(frames),
        .facing_left(facing),.rocket_vertical_mask(9'd0),.fan_lift_mask(lift_mask),
        .fan_on(fan_on),.rocket_on(1'b0),.grounded(grounded),.tilt(tilt),
        .contact_span_valid(contact_valid),.contact_left_q2(contact_left),.contact_right_q2(contact_right),
        .wheel_force_valid(1'b1),.wheel_force(16'sd0),.result_valid(valid),.result_ready(accept),
        .angular_accel_q8(accel),.body_mass(mass),.torque_q10(torque),
        .gravity_tilt_q8(gravity),.support_negative_q8(support_negative),.support_positive_q8(support_positive),
        .pivot_start(pivot_start),.next_tilt(tilt),.pivot_valid(pivot_valid),.pivot_ready(pivot_ready));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task put;input integer cell_id;input [2:0] kind;begin
        grid[cell_id*3 +: 3]=kind;alive[cell_id]=1;
    end endtask
    task centre;begin
        grid=0;frames=9'b000010000;alive=0;lift_mask=0;facing=0;fan_on=1;tilt=0;
        grounded=0;contact_valid=0;contact_left=0;contact_right=0;
        put(4,`LP_PART_PIG);
    end endtask
    task begin_calc;begin start=1;clocks(1);start=0;end endtask
    task wait_calc;begin
        waited=0;while(!valid && waited<1800) begin clocks(1);waited=waited+1;end
        if(!valid) $fatal(1,"Lift fan moment timeout");tests=tests+1;
    end endtask
    task finish;begin
        accept=1;clocks(1);accept=0;pivot_start=1;clocks(1);pivot_start=0;
        waited=0;while(!pivot_valid && waited<200) begin clocks(1);waited=waited+1;end
        if(!pivot_valid) $fatal(1,"Lift fan pivot timeout");
        pivot_ready=1;clocks(1);pivot_ready=0;
    end endtask
    task calculate;begin begin_calc();wait_calc();end endtask
    initial begin
        clocks(3);reset=0;
        centre();lift_mask=9'h1ff;calculate();
        if(torque!=0 || accel!=0 || mass!=4)
            $fatal(1,"Lift metadata turned a non-fan cell into an actuator");finish();
        centre();put(3,`LP_PART_FAN);lift_mask[3]=1;calculate();
        if(mass!=6 || torque!=5632 || accel!=117)
            $fatal(1,"Left lift fan COM/moment wrong: %0d %0d %0d",mass,torque,accel);finish();
        facing[3]=1;calculate();
        if(torque!=5632 || accel!=117) $fatal(1,"Facing reversed upward lift");finish();
        fan_on=0;calculate();if(torque!=0 || accel!=0) $fatal(1,"Disabled lift fan retained torque");finish();
        fan_on=1;alive[3]=0;calculate();
        if(mass!=4 || torque!=0 || accel!=0) $fatal(1,"Dead lift fan retained mass/torque");finish();
        centre();put(5,`LP_PART_FAN);lift_mask[5]=1;calculate();
        if(torque!=-5632 || accel!=-117) $fatal(1,"Right lift fan did not mirror torque");finish();
        // Snapshot includes vector metadata, enable and damage masks.
        centre();put(3,`LP_PART_FAN);lift_mask[3]=1;begin_calc();
        lift_mask=0;alive=0;fan_on=0;wait_calc();
        if(torque!=5632) $fatal(1,"Live changes corrupted lift vector snapshot");finish();
        for(angle=-16;angle<16;angle=angle+1) begin
            centre();put(0,`LP_PART_FAN);lift_mask[0]=1;tilt=angle;calculate();
            // COM=(-10,-10) and fan=(-32,-32), in quarter pixels.
            // Division here is a test oracle only, never synthesizable RTL.
            expected_arm=(-22*$signed(rotation_cos(tilt))+22*$signed(rotation_sin(tilt)))/256;
            expected_torque=-256*expected_arm;
            if(torque!=expected_torque)
                $fatal(1,"World-up moment formula wrong at %0d: %0d expected %0d",angle,torque,expected_torque);
            reference_torque=torque;reference_accel=accel;finish();
            centre();put(2,`LP_PART_FAN);lift_mask[2]=1;tilt=-angle;facing=9'h1ff;calculate();
            if(torque!=-reference_torque || accel!=-reference_accel)
                $fatal(1,"Mirrored upward fan moment unequal at %0d",angle);finish();
            centre();put(3,`LP_PART_FAN);put(5,`LP_PART_FAN);
            lift_mask=9'b000101000;tilt=angle;calculate();
            if(torque!=0 || accel!=0) $fatal(1,"Balanced upward fans spun at %0d",angle);finish();
        end
        // The unmarked horizontal fan retains its original 64-unit vector.
        centre();put(3,`LP_PART_FAN);lift_mask[3]=1;put(1,`LP_PART_FAN);calculate();
        if(torque!=4608 || accel!=72)
            $fatal(1,"Horizontal fan changed strength or lift vector was lost");finish();
        // Upward jets unload the ground. A body with upward net force cannot
        // retain a fictitious normal reaction or gravity tipping impulse.
        centre();put(3,`LP_PART_FAN);lift_mask[3]=1;grounded=1;contact_valid=1;
        contact_left=-16;contact_right=16;calculate();
        if(support_negative!=0 || support_positive!=0 || gravity!=0)
            $fatal(1,"Lift-off retained ground reaction");finish();
        // With heavier wood, partial lift reduces both support and overhang
        // weight without changing their signs or creating a sideways force.
        frames=9'b000111000;fan_on=0;calculate();
        reference_negative=support_negative;reference_positive=support_positive;finish();
        fan_on=1;calculate();
        if(support_negative<=0 || support_positive<=0 ||
           support_negative>=reference_negative || support_positive>=reference_positive)
            $fatal(1,"Partial lift did not reduce ground support");finish();
        contact_left=-48;contact_right=-32;fan_on=0;calculate();
        reference_gravity=gravity;finish();fan_on=1;calculate();
        if(gravity<=0 || gravity>=reference_gravity)
            $fatal(1,"Partial lift did not reduce overhang gravity");finish();
        // All nine cells can carry vector metadata without counter overflow.
        centre();frames=0;grid={9{`LP_PART_FAN}};alive=9'h1ff;lift_mask=9'h1ff;
        grounded=1;contact_valid=1;contact_left=-16;contact_right=16;calculate();
        if(mass!=18 || torque!=0 || accel!=0 || gravity!=0 ||
           support_negative!=0 || support_positive!=0)
            $fatal(1,"Nine lift fans overflowed force, moment or support counters");finish();
        $display("PASS fan_lift_moments_tb: %0d cases; per-cell vector, COM cross product, all rotations, mirrors, enable, death and snapshots",tests);
        $finish;
    end
    initial begin #3000000;$fatal(1,"Lift fan moment tests timeout");end
endmodule


