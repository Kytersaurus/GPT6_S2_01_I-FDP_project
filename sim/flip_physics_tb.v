// Owner: Role 4 - Marcus. Full-turn rotation, wheel sides and edge tipping.
`timescale 1ns / 1ps
`include "game_defs.vh"
// The real physics and rotated collision engines run against synthetic terrain:
// scene 1 is a flat floor at y=140; scene 2 is a ledge (x<100, y>=140) above a
// lower floor at y=190. Each case starts from a pose, runs whole updates and checks
// the result. No pose is edited once a case is running.
module flip_physics_tb;
    reg clk=0, reset=1, run_init=0, step_start=0, update_release=0;
    reg [2:0] game_state=`LP_BUILD, scene=1;
    reg signed [19:0] spawn_x=0, spawn_y=0;
    reg [3:0] wheel_count=4, wheels_down=2, wheels_up=2;
    reg engine_enabled=0, engine_reverse=0;
    reg [8:0] collision_mask=9'b101111101;
    always #5 clk=~clk;
    wire move_valid, move_ready, response_valid, response_ready, grounded, movement_committed, init_ready;
    wire signed [19:0] previous_x, previous_y, proposed_x, proposed_y, corrected_x, corrected_y, vehicle_x, vehicle_y;
    wire signed [15:0] proposed_vx, proposed_vy, corrected_vx, corrected_vy;
    wire signed [7:0] ground_slope;
    wire signed [`LP_TILT_BITS-1:0] previous_tilt, proposed_tilt, corrected_tilt, vehicle_tilt;
    wire signed [1:0] tip_dir;
    wire signed [10:0] qx, qy;
    reg [2:0] query_class=`LP_MAP_SKY;
    integer updates, start_x, max_tilt_change, min_y, landed_at, waited, t, len2;
    real angle, want_cos, want_sin;
    `include "rotation_geometry.vh"
    // Every one of the 32 angles is a near-unit vector at the right angle, and
    // -4..4 keep the values the 9-angle table had.
    task check_tables;
        begin
            for (t=-16; t<16; t=t+1) begin
                angle = t*11.25*3.14159265358979/180.0;
                want_cos = 256.0*$cos(angle); want_sin = 256.0*$sin(angle);
                if (rotation_cos(t)-want_cos > 1.0 || want_cos-rotation_cos(t) > 1.0 ||
                    rotation_sin(t)-want_sin > 1.0 || want_sin-rotation_sin(t) > 1.0)
                    $fatal(1,"Tilt %0d: cos/sin %0d/%0d, expected %f/%f",t,rotation_cos(t),rotation_sin(t),want_cos,want_sin);
                len2 = rotation_cos(t)*rotation_cos(t)+rotation_sin(t)*rotation_sin(t);
                if (len2 != rotation_norm_squared(t)) $fatal(1,"Tilt %0d: basis length %0d, table %0d",t,len2,rotation_norm_squared(t));
            end
            if (rotation_cos(-4)!=181 || rotation_sin(-4)!=-181 || rotation_cos(1)!=251 || rotation_sin(1)!=50 ||
                rotation_extent(3)!=4261 || rotation_extent(-1)!=3614 || rotation_extent(0)!=3072)
                $fatal(1,"The -4..4 rotation values changed");
            if (rotation_extent(-16)!=3072 || rotation_extent(12)!=4345 || rotation_extent(7)!=3614 ||
                !tilt_flipped(-16) || !tilt_flipped(9) || tilt_flipped(8) || tilt_flipped(-8))
                $fatal(1,"Full-turn extents or flip test wrong");
        end
    endtask

    function solid_pixel;
        input integer x, y;
        begin
            case (scene)
                1: solid_pixel = y>=140;
                2: solid_pixel = (y>=140 && x<100) || y>=190;
                default: solid_pixel = 0;
            endcase
        end
    endfunction
    // One clock of read latency, like the block-RAM query port.
    always @(posedge clk) query_class <= solid_pixel($signed(qx),$signed(qy)) ? `LP_MAP_ROCK : `LP_MAP_SKY;

    physics_engine u_physics (
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready),
        .spawn_x(spawn_x), .spawn_y(spawn_y), .step_start(step_start), .update_release(update_release),
        .wheel_count(wheel_count), .wheels_down(wheels_down), .wheels_up(wheels_up), .tip_dir(tip_dir),
        .engine_count(4'd1), .balloon_count(4'd0), .mass_units(8'd15),
        .engine_enabled(engine_enabled), .engine_reverse(engine_reverse), .jump_press(1'b0), .boost_req(1'b0),
        .boost_active(), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .response_valid(response_valid),
        .response_ready(response_ready), .corrected_x(corrected_x), .corrected_y(corrected_y),
        .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded), .ground_slope(ground_slope),
        .previous_tilt(previous_tilt), .proposed_tilt(proposed_tilt), .corrected_tilt(corrected_tilt),
        .vehicle_tilt(vehicle_tilt), .movement_committed(movement_committed),
        .vehicle_x(vehicle_x), .vehicle_y(vehicle_y)
    );
    collision_engine #(.ROTATION_ONLY(1)) u_collision (
        .clk(clk), .reset(reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .terrain_count(3'd0), .terrain_rects(128'd0),
        .map_level(1'b1), .rotation_enabled(1'b1), .previous_tilt(previous_tilt), .proposed_tilt(proposed_tilt),
        .collision_mask(collision_mask), .world_width(10'd400), .world_height(10'd240),
        .query_x(qx), .query_y(qy), .query_class(query_class),
        .response_valid(response_valid), .response_ready(response_ready), .corrected_x(corrected_x),
        .corrected_y(corrected_y), .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded),
        .ground_slope(ground_slope), .corrected_tilt(corrected_tilt), .tip_dir(tip_dir)
    );

    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    // Start a run at a pose: x, y in whole pixels and a tilt.
    task start_at;
        input integer x, y, tilt;
        begin
            game_state=`LP_INIT_RUN; spawn_x=x*256; spawn_y=y*256;
            run_init=1; clocks(3); run_init=0;
            force u_physics.vehicle_tilt=tilt; clocks(1); release u_physics.vehicle_tilt;
            game_state=`LP_RUN; clocks(2);
        end
    endtask
    // One update, exactly as game_controller sequences it.
    task update;
        begin
            step_start=1; clocks(1); step_start=0;
            waited=0;
            while (!movement_committed && waited<2000000) begin clocks(1); waited=waited+1; end
            if (!movement_committed) $fatal(1,"Update did not commit");
            clocks(1); update_release=1; clocks(1); update_release=0; clocks(1);
            updates=updates+1;
        end
    endtask
    task run_updates;
        input integer n;
        integer i;
        begin for (i=0; i<n; i=i+1) update(); end
    endtask
    function integer abs_tilt;
        input signed [`LP_TILT_BITS-1:0] t;
        begin abs_tilt = t<0 ? -t : t; end
    endfunction

    initial begin
        updates=0; check_tables();
        clocks(3); reset=0; clocks(2);

        // A: upright with wheels both sides drives along the floor and stays upright.
        scene=1; wheels_down=2; wheels_up=2; engine_enabled=1;
        start_at(40,116,0); start_x=vehicle_x; run_updates(120);
        if (!grounded || abs_tilt(vehicle_tilt)>1 || vehicle_x-start_x<20*256)
            $fatal(1,"A: upright drive failed x=%0d tilt=%0d grounded=%b",vehicle_x/256,vehicle_tilt,grounded);

        // B: upside down, the top wheels touch the floor and drive it the same way.
        start_at(40,114,-16); run_updates(10); start_x=vehicle_x; run_updates(120);
        if (!grounded || abs_tilt(vehicle_tilt)<15 || vehicle_x-start_x<20*256)
            $fatal(1,"B: flipped drive failed x=%0d->%0d tilt=%0d grounded=%b",start_x/256,vehicle_x/256,vehicle_tilt,grounded);

        // C: upside down with wheels only underneath, the frame scrapes and cannot drive.
        wheels_down=2; wheels_up=0;
        start_at(40,114,-16); run_updates(10); start_x=vehicle_x; run_updates(120);
        if (!grounded || abs_tilt(vehicle_tilt)<15 || vehicle_x-start_x>2*256)
            $fatal(1,"C: wheel-less side still drove x=%0d->%0d tilt=%0d",start_x/256,vehicle_x/256,vehicle_tilt);

        // D: upside down with wheels only underneath, a coasting body scrapes to a stop.
        wheels_down=2; wheels_up=0; engine_enabled=0;
        start_at(40,114,-16); run_updates(10);
        force u_physics.velocity_x=16'sd200; clocks(1); release u_physics.velocity_x;
        run_updates(40);
        if (u_physics.velocity_x!=0) $fatal(1,"D: scraping body still moving vx=%0d",u_physics.velocity_x);
        wheels_down=2; wheels_up=2;

        // E: a level body resting on flat ground does not rock or tip.
        engine_enabled=0;
        start_at(40,116,0); run_updates(60);
        if (vehicle_tilt!=0 || tip_dir!=0 || !grounded) $fatal(1,"E: level body rocked tilt=%0d tip=%0d",vehicle_tilt,tip_dir);

        // F: a slightly tilted body on flat ground settles level.
        start_at(40,112,3); run_updates(30);
        if (vehicle_tilt!=0 || !grounded) $fatal(1,"F: tilted body did not settle tilt=%0d",vehicle_tilt);

        // G: driving off the ledge, the body tips nose down over the edge, falls,
        // lands on the lower floor and keeps driving whichever side it lands on.
        scene=2; engine_enabled=1;
        start_at(60,116,0); max_tilt_change=0; min_y=0; landed_at=-1;
        while (updates<100000 && landed_at<0) begin
            update();
            if (abs_tilt(vehicle_tilt)>max_tilt_change) max_tilt_change=abs_tilt(vehicle_tilt);
            if (grounded && vehicle_y>150*256) landed_at=updates;
            if (vehicle_x>300*256) $fatal(1,"G: never landed");
        end
        if (max_tilt_change<2) $fatal(1,"G: body did not tip over the edge (max tilt %0d)",max_tilt_change);
        run_updates(40); start_x=vehicle_x; run_updates(120);
        if (!grounded || vehicle_x-start_x<15*256)
            $fatal(1,"G: did not keep driving after landing x=%0d tilt=%0d grounded=%b",vehicle_x/256,vehicle_tilt,grounded);

        $display("PASS flip_physics_tb: 32-angle tables, flipped drive, wheel-less scraping, level rest, settling and edge tipping (%0d updates)",updates);
        $finish;
    end
endmodule
