// Owner: Role 2 - Kyle. Slope-force arithmetic and accepted-contact checks.
`timescale 1ns / 1ps
`include "game_defs.vh"

module physics_slope_tb;
    reg clk=0, reset=1, run_init=0, step_start=0, update_release=0;
    reg [2:0] game_state=`LP_BUILD;
    reg [3:0] wheels=0, engines=1, balloons=0;
    reg [7:0] mass=11;
    reg engine_enabled=0, engine_reverse=0, jump=0;
    reg move_ready=0, response_valid=0, grounded=1;
    reg signed [7:0] slope=0;
    reg unstable=0;
    reg signed [1:0] tip=0;
    reg signed [`LP_COORD_BITS-1:0] cx=0, cy=0;
    reg signed [15:0] cvx=0, cvy=0;
    wire initialized, move_valid, response_ready, committed;
    wire signed [`LP_COORD_BITS-1:0] px, py, nx, ny, x, y;
    wire signed [15:0] nvx, nvy;
    reg [4*`LP_COORD_BITS+31:0] held_request;
    integer waited, cases=0, test_slope, test_sign, test_tip, reference_velocity;
    always #5 clk=~clk;

    physics_engine dut (
        .clk(clk), .reset(reset), .game_state(game_state),
        .run_init(run_init), .init_ready(initialized),
        .spawn_x(20'sd1024), .spawn_y(20'sd8192),
        .step_start(step_start), .update_release(update_release),
        .wheel_count(wheels), .engine_count(engines), .balloon_count(balloons),
        .mass_units(mass), .engine_enabled(engine_enabled), .engine_reverse(engine_reverse),
        .jump_press(jump), .boost_req(1'b0), .boost_active(),
        .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(nvx), .proposed_vy(nvy),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(cx), .corrected_y(cy), .corrected_vx(cvx), .corrected_vy(cvy),
        .grounded(grounded), .ground_slope(slope),
        .support_unstable(unstable), .tip_dir(tip),
        .movement_committed(committed), .vehicle_x(x), .vehicle_y(y)
    );

    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task begin_step;
        begin
            step_start=1; clocks(1); step_start=0;
            waited=0;
            while(!move_valid && waited<96) begin clocks(1); waited=waited+1; end
            if(!move_valid) $fatal(1,"Slope movement request missing");
        end
    endtask
    task finish_step;
        begin
            move_ready=1; clocks(1); move_ready=0;
            if(!response_ready) $fatal(1,"Slope response was not accepted");
            response_valid=1; clocks(1); response_valid=0;
            if(!committed || x!==cx || y!==cy) $fatal(1,"Slope response did not commit");
            clocks(1);
            if(committed) $fatal(1,"Slope response committed twice");
            update_release=1; clocks(1); update_release=0;
        end
    endtask
    // Establish contact/velocity solely through the public response handshake.
    task seed_state;
        input integer starting_velocity, contact, initial_slope;
        begin
            reset=1; game_state=`LP_BUILD; run_init=0; jump=0;
            step_start=0; update_release=0; move_ready=0; response_valid=0;
            grounded=contact; slope=initial_slope;
            clocks(2); reset=0;
            game_state=`LP_INIT_RUN; run_init=1; clocks(2);
            if(!initialized) $fatal(1,"Slope run initialization missing");
            run_init=0; game_state=`LP_RUN;
            begin_step;
            if(nvx!==0) $fatal(1,"Unconfirmed spawn contact applied slope or engine force");
            cx=1024; cy=8192; cvx=starting_velocity; cvy=0;
            finish_step;
        end
    endtask
    task check_velocity;
        input integer expected_velocity;
        begin
            if($signed(nvx)!==expected_velocity)
                $fatal(1,"Slope case %0d expected vx=%0d, got %0d",cases,expected_velocity,$signed(nvx));
            cases=cases+1;
        end
    endtask
    task expect_step;
        input integer expected_velocity;
        begin
            begin_step;
            check_velocity(expected_velocity);
            cx=nx; cy=8192; cvx=nvx; cvy=0;
            finish_step;
        end
    endtask

    initial begin
        // Positive dy/dx slopes descend to the right; acceleration is symmetric.
        seed_state(0,1,16); expect_step(16); expect_step(32);
        seed_state(0,1,-16); expect_step(-16); expect_step(-32);
        seed_state(0,1,8); expect_step(12);
        seed_state(0,1,-8); expect_step(-12);
        // Gravity brakes travel uphill and can turn it back downhill.
        seed_state(-40,1,16); expect_step(-24); expect_step(-8); expect_step(8);
        seed_state(40,1,-16); expect_step(24); expect_step(8); expect_step(-8);

        // Gravity acceleration is independent of mass before wheel resistance.
        mass=1; seed_state(0,1,16); expect_step(16);
        mass=255; seed_state(0,1,16); expect_step(16);
        mass=11; wheels=2; seed_state(0,1,16); expect_step(14);
        seed_state(0,1,-16); expect_step(-14);
        // Static wheel friction can hold a sufficiently heavy resistance.
        mass=1; wheels=3; seed_state(0,1,16); expect_step(0);
        wheels=0; mass=0; seed_state(0,1,16); expect_step(0);

        // Raster stair contacts can put the CoG outside a narrow contact span.
        // Its edge hint must not replace a measured downhill gravity force.
        // In particular, an uphill hint must not erase engine-gained momentum.
        mass=11; wheels=2; unstable=1; tip=-1;
        seed_state(200,1,16); expect_step(214); expect_step(229);
        tip=1; seed_state(-200,1,-16); expect_step(-214); expect_step(-229);
        wheels=0;
        // A shallow ramp keeps its own acceleration, even if the edge hint
        // agrees with it; substituting the stronger fallback would add energy.
        tip=1; seed_state(100,1,2); expect_step(104);
        tip=-1; seed_state(-100,1,-2); expect_step(-104);
        tip=-1; seed_state(100,1,2); expect_step(104);
        tip=1; seed_state(-100,1,-2); expect_step(-104);
        // Level/unknown ledges still receive the outward release impulse.
        tip=1; seed_state(0,1,0); expect_step(16); expect_step(32);
        tip=-1; seed_state(0,1,0); expect_step(-16); expect_step(-32);
        // Moving against the edge hint receives ordinary rolling drag only.
        // A resting/matching-direction cart still gets the release force.
        wheels=2;
        tip=-1; seed_state(80,1,0); expect_step(79); expect_step(78);
        tip=1; seed_state(-80,1,0); expect_step(-79); expect_step(-78);
        tip=1; seed_state(0,1,0); expect_step(14); expect_step(29);
        tip=-1; seed_state(0,1,0); expect_step(-14); expect_step(-29);
        tip=1; seed_state(80,1,0); expect_step(94);
        tip=-1; seed_state(-80,1,0); expect_step(-94);
        wheels=0;
        // Airborne state cannot receive any cached support force.
        tip=-1; seed_state(100,0,16); expect_step(100);
        tip=1; seed_state(-100,0,-16); expect_step(-100);
        // Build speed with the motor, then switch it off on a known ramp.
        mass=12; engine_enabled=1; tip=-1;
        seed_state(0,1,16); expect_step(24); expect_step(48);
        engine_enabled=0; expect_step(64); expect_step(80);
        engine_enabled=1; engine_reverse=1; tip=1;
        seed_state(0,1,-16); expect_step(-24); expect_step(-48);
        engine_enabled=0; expect_step(-64); expect_step(-80);
        engine_reverse=0; wheels=2; mass=11;
        // General property: any measured nonzero gradient has the same force
        // with or without a CoG edge hint, for either velocity and hint sign.
        for(test_slope=-16;test_slope<=16;test_slope=test_slope+1) begin
            if(test_slope!=0) begin
                for(test_sign=-1;test_sign<=1;test_sign=test_sign+2) begin
                    for(test_tip=-1;test_tip<=1;test_tip=test_tip+2) begin
                        unstable=0;tip=0;seed_state(test_sign*80,1,test_slope);
                        begin_step;reference_velocity=$signed(nvx);
                        unstable=1;tip=test_tip;seed_state(test_sign*80,1,test_slope);
                        expect_step(reference_velocity);
                    end
                end
            end
        end
        // The same no-CoG comparison applies to opposing flat ledge hints.
        for(test_sign=-1;test_sign<=1;test_sign=test_sign+2) begin
            unstable=0;tip=0;seed_state(test_sign*80,1,0);
            begin_step;reference_velocity=$signed(nvx);
            unstable=1;tip=-test_sign;seed_state(test_sign*80,1,0);
            expect_step(reference_velocity);
        end
        unstable=0; tip=0; wheels=0;

        // Engine direction combines with the downhill force before division.
        mass=12; engine_enabled=1;
        seed_state(0,1,16); expect_step(24);
        engine_reverse=1; seed_state(0,1,16); expect_step(8);
        engine_reverse=0; seed_state(0,1,-16); expect_step(-8);
        engine_enabled=0; mass=11;

        // Balloon lift reduces the gravity projected along the terrain.
        balloons=1; seed_state(0,1,16); expect_step(4);
        seed_state(0,1,-16); expect_step(-4);
        balloons=2; seed_state(0,1,16); expect_step(0);
        balloons=0;

        // Airborne and flat responses clear the previous slope influence.
        seed_state(40,0,16); expect_step(40);
        seed_state(-40,0,-16); expect_step(-40);
        seed_state(40,1,0); expect_step(40);
        seed_state(0,1,16); grounded=0; expect_step(16); expect_step(16);
        seed_state(0,1,16); slope=0; expect_step(16); expect_step(16);

        // A jump leaves the slope without receiving an extra downhill impulse.
        seed_state(0,1,16); jump=1; begin_step; jump=0;
        check_velocity(0);
        if(nvy!==-16'sd512) $fatal(1,"Grounded slope jump did not launch upward");
        grounded=0; cx=nx; cy=ny; cvx=nvx; cvy=nvy; finish_step;
        expect_step(0);

        // Slope is sampled on response acceptance, never from an idle bus.
        seed_state(0,1,16); slope=-16; begin_step; check_velocity(16);
        held_request={px,py,nx,ny,nvx,nvy};
        slope=8; mass=1; wheels=4; engine_enabled=1; balloons=2; clocks(6);
        if(!move_valid || {px,py,nx,ny,nvx,nvy}!==held_request || x!==20'sd1024)
            $fatal(1,"Stalled slope request changed or committed early");
        slope=-16; cx=nx; cy=8192; cvx=nvx; cvy=0; finish_step;
        mass=11; wheels=0; engine_enabled=0; balloons=0;
        expect_step(0);

        // Retry cancels cached terrain contact and any arithmetic in flight.
        begin_step;
        game_state=`LP_INIT_RUN; run_init=1; clocks(2);
        if(!initialized || move_valid || x!==20'sd1024 || y!==20'sd8192)
            $fatal(1,"Retry retained slope movement");
        run_init=0; game_state=`LP_RUN; expect_step(0);

        $display("PASS physics_slope_tb: %0d cases, downhill/uphill forces, mass, friction, engine direction, CoG coasting invariance, ledge release, balloons, jumps, contact sampling, backpressure and retry",cases);
        $finish;
    end
    initial begin #1000000; $fatal(1,"Slope arithmetic test timed out"); end
endmodule
