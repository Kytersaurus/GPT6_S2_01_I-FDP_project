// Owner: Role 4 - Marcus. Levels, game control, level button and both renderers.
`timescale 1ns / 1ps
`include "game_defs.vh"
module role4_game_display_tb;
    reg clk=0, reset=1;
    always #5 clk=~clk;

    // Level table, checked through one instance.
    reg [`LP_LEVEL_BITS-1:0] level=0;
    wire signed [19:0] spawn_x, spawn_y;
    wire [2:0] terrain_count, tnt_count;
    wire [127:0] terrain_rects;
    wire [31:0] goal_rect;
    wire [`LP_TNT_BITS-1:0] tnt_positions;
    wire [1:0] hazard_count;
    wire [`LP_HAZARD_BITS-1:0] hazard_rects;
    wire map_level, map_id;
    wire [9:0] world_width, world_height, flag_x, flag_y;
    level_data levels (
        .level_index(level),.spawn_x(spawn_x),.spawn_y(spawn_y),.terrain_count(terrain_count),
        .terrain_rects(terrain_rects),.goal_rect(goal_rect),.tnt_count(tnt_count),
        .tnt_positions(tnt_positions),.hazard_count(hazard_count),.hazard_rects(hazard_rects),
        .map_level(map_level),.map_id(map_id),.world_width(world_width),.world_height(world_height),
        .flag_x(flag_x),.flag_y(flag_y)
    );

    // Game controller with scripted neighbours.
    reg launch=0, retry=0, edit=0, level_next=0, live=1, tick=0, world_valid=0;
    reg goal=0, hazard=0, bounds=0;
    wire world_ready, run_init, step, release_step;
    wire [2:0] state;
    wire [`LP_LEVEL_BITS-1:0] level_index;
    wire [1:0] fail_reason;
    wire [7:0] run_seconds;
    game_controller #(.TICKS_PER_SECOND(4)) control (
        .clk(clk),.reset(reset),.launch_req(launch),.retry_req(retry),.edit_req(edit),
        .guide_open_req(1'b0),.guide_close_req(1'b0),.level_next_req(level_next),
        .build_valid(1'b1),.pig_alive(live),.init_ready(3'b111),.physics_tick(tick),
        .world_valid(world_valid),.world_ready(world_ready),.gameplay_pending(1'b0),.gameplay_ready(),
        .goal_hit(goal),.hazard_hit(hazard),.out_of_bounds(bounds),.game_state(state),
        .level_index(level_index),.fail_reason(fail_reason),.run_seconds(run_seconds),
        .run_init(run_init),.step_start(step),
        .update_release(release_step),.launch_event(),.success_event(),.failure_event()
    );

    // Level button with a scripted mouse.
    reg [2:0] button_state=`LP_BUILD;
    reg [11:0] mouse_x=0, mouse_y=0;
    reg mouse_left=0, mouse_right=0, mouse_event=0, button_enabled=1;
    wire button_req;
    integer button_pulses=0;
    level_button button (
        .input_enabled(button_enabled),
        .clk(clk),.reset(reset),.game_state(button_state),.mouse_x(mouse_x),.mouse_y(mouse_y),
        .mouse_left(mouse_left),.mouse_right(mouse_right),.mouse_event(mouse_event),.level_open_req(button_req)
    );
    always @(posedge clk) if (button_req) button_pulses = button_pulses + 1;

    // Explosion animation, two physics ticks per phase.
    reg fx_init=0, fx_tick=0;
    reg [`LP_MAX_TNT-1:0] fx_intact={`LP_MAX_TNT{1'b1}};
    wire [2*`LP_MAX_TNT-1:0] fx_phase;
    explosion_fx #(.PHASE_TICKS(2)) blasts (
        .clk(clk),.reset(reset),.run_init(fx_init),.physics_tick(fx_tick),
        .tnt_intact(fx_intact),.blast_phase(fx_phase)
    );

    // Renderers with the preset build: frames in cells 3-5, pig in cell 4.
    reg [12:0] pixel=0;
    reg [2:0] view_state=`LP_BUILD;
    reg [1:0] view_reason=`LP_FAIL_NONE;
    reg [`LP_MAX_TNT-1:0] tnt_intact={`LP_MAX_TNT{1'b1}};
    reg signed [19:0] vehicle_x=20'sd1024, vehicle_y=20'sd8192;
    reg zoomed_out=1, free_look=0;
    reg [6:0] look_x=0, look_y=0;
    reg [8:0] view_intact=9'b101110000;
    reg [7:0] view_seconds=0;
    reg [2*`LP_MAX_TNT-1:0] view_blast=0;
    reg view_phase=0;
    wire [26:0] grid = {`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
                        `LP_PART_ENGINE,`LP_PART_PIG,`LP_PART_EMPTY,
                        `LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_EMPTY};
    wire [15:0] left_colour, right_colour;
    left_renderer left_view (
        .build_facing_left(9'd0), .selected_left(1'b0), .inventory_page(1'b0), .rockets_left(4'd1), .fans_left(4'd1),
        .pixel_index(pixel),.game_state(view_state),.build_grid(grid),.build_frames(9'b000111000),
        .intact_mask(view_intact),.frame_intact_mask(9'b000111000),.build_valid(1'b1),.build_error(4'd0),.engine_enabled(1'b1),
        .feedback_code(`LP_FEEDBACK_NONE),.feedback_cell(4'd0),
        .frames_left(4'd2),.pigs_left(4'd0),.wheels_left(4'd0),.engines_left(4'd0),.balloons_left(4'd2),
        .selected_part(`LP_PART_FRAME),.drag_active(1'b0),.drag_from_grid(1'b0),.drag_source(4'd9),.drag_contents(3'd0),.cursor_x(7'd0),.cursor_y(7'd0),.cursor_visible(1'b0),
        .level_index(level),.fail_reason(view_reason),.run_seconds(view_seconds),.anim_phase(view_phase),.pixel_data(left_colour)
    );
    wire signed [10:0] map_x, map_y;
    wire [2:0] map_class;
    level_map map_rom (
        .query_map_id(1'b0),
        .map_id(map_id),.draw_clk(clk),.draw_x(map_x),.draw_y(map_y),.draw_class(map_class),
        .query_clk(clk),.query_x(11'sd0),.query_y(11'sd0),.query_class()
    );
    right_renderer right_view (
        .build_facing_left(9'd0),
        .clk(clk),.zoomed_out(zoomed_out),.overview(1'b0),.free_look(free_look),.cursor_x(look_x),.cursor_y(look_y),
        .map_level(map_level),.map_id(map_id),.world_width(world_width),
        .world_height(world_height),.flag_x(flag_x),.flag_y(flag_y),
        .map_x(map_x),.map_y(map_y),.map_class(map_class),
        .pixel_index(pixel),.game_state(view_state),.build_grid(grid),.intact_mask(9'b101110000),
        .frame_intact_mask(9'b000111000),.vehicle_x(vehicle_x),.vehicle_y(vehicle_y),
        .spawn_x(spawn_x),.spawn_y(spawn_y),.terrain_count(terrain_count),.terrain_rects(terrain_rects),
        .goal_rect(goal_rect),.tnt_count(tnt_count),.tnt_positions(tnt_positions),.tnt_intact(tnt_intact),
        .hazard_count(hazard_count),.hazard_rects(hazard_rects),.blast_phase(view_blast),.anim_phase(view_phase),.pixel_data(right_colour)
    );

    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    // Task arguments are copied out only at the end, so pulse the named request directly.
    localparam LAUNCH=0, RETRY=1, EDIT=2, LEVEL=3, TICK=4;
    task pulse;
        input integer which;
        begin
            case (which)
                LAUNCH: launch=1; RETRY: retry=1; EDIT: edit=1; LEVEL: level_next=1; TICK: tick=1;
            endcase
            clocks(1);
            launch=0; retry=0; edit=0; level_next=0; tick=0;
            clocks(1);
        end
    endtask
    task expect_left;
        input integer x, y;
        input [15:0] colour;
        input [8*24-1:0] what;
        begin
            pixel=y*96+x; #1;
            if (left_colour !== colour) $fatal(1,"Left %0s: (%0d,%0d)=%h, expected %h",what,x,y,left_colour,colour);
        end
    endtask
    task expect_right;
        input integer x, y;
        input [15:0] colour;
        input [8*24-1:0] what;
        begin
            // The right renderer registers each pixel beside its map read.
            pixel=y*96+x; @(posedge clk); #1;
            if (right_colour !== colour) $fatal(1,"Right %0s: (%0d,%0d)=%h, expected %h",what,x,y,right_colour,colour);
        end
    endtask
    task button_packet;
        input integer x,y;
        input left_button,right_button;
        begin
            mouse_x=x; mouse_y=y; mouse_left=left_button; mouse_right=right_button;
            mouse_event=1; clocks(1); mouse_event=0; clocks(2);
        end
    endtask
    task check_button_click;
        input integer x,y;
        input accepted;
        integer before_pulses;
        begin
            before_pulses=button_pulses;
            button_packet(x,y,0,0); button_packet(x,y,1,0); button_packet(x,y,0,0);
            if(button_pulses!=before_pulses+accepted)
                $fatal(1,"Button boundary (%0d,%0d) state%0d enabled%b: pulses%0d expected%0d",
                    x,y,button_state,button_enabled,button_pulses-before_pulses,accepted);
        end
    endtask
    // Launch, then answer one movement step with the given outcome flags.
    task run_one_step;
        input g, h, b, alive;
        begin
            pulse(LAUNCH); clocks(2);
            if (state !== `LP_RUN) $fatal(1,"Launch did not reach RUN");
            pulse(TICK);
            if (!world_ready) $fatal(1,"No outstanding step after a physics tick");
            goal=g; hazard=h; bounds=b; live=alive; world_valid=1; clocks(1);
            world_valid=0; goal=0; hazard=0; bounds=0; live=1; clocks(1);
        end
    endtask
    integer index;
    initial begin
        // Level data: the spawn rests on ground; both levels keep within the packing limits.
        level=0; #1;
        if (spawn_x !== 16'sd1024 || spawn_y !== 16'sd8192) $fatal(1,"Level 1 spawn moved");
        if (terrain_count != 2 || tnt_count != 1 || hazard_count != 0) $fatal(1,"Level 1 counts wrong");
        if (terrain_rects[31:0] !== {8'd8,8'd96,8'd56,8'd0}) $fatal(1,"Level 1 ground is not the flat baseline");
        if (goal_rect !== {8'd24,8'd16,8'd32,8'd80}) $fatal(1,"Level 1 goal moved");
        if (tnt_positions[63:16] !== 0 || hazard_rects !== 0 || terrain_rects[127:64] !== 0)
            $fatal(1,"Level 1 unused entries are not zero");
        level=1; #1;
        if (terrain_count != 4 || tnt_count != 2 || hazard_count != 1) $fatal(1,"Level 2 counts wrong");
        if (tnt_positions[15:0] !== {8'd48,8'd60}) $fatal(1,"Level 2 path TNT not on the ground");
        if (hazard_rects[31:0] !== {8'd4,8'd16,8'd58,8'd36}) $fatal(1,"Level 2 spikes moved");
        // The pit must stay narrower than the 24 pixel vehicle so it can be crossed.
        if (hazard_rects[23:16] >= 24) $fatal(1,"Level 2 pit wider than the vehicle");
        if (map_level) $fatal(1,"Level 2 drawn from the map ROM");
        // Level 3, Cave Arch: map-drawn, spawn on the flat start plateau, flag on the cave road.
        level=2; #1;
        if (!map_level || world_width != `LP_MAP_WORLD_WIDTH || world_height != `LP_MAP_WORLD_HEIGHT)
            $fatal(1,"Level 3 is not the Cave Arch map");
        if (spawn_x !== 20'sd53248 || spawn_y !== 20'sd19456 || flag_x != 600 || flag_y != 472)
            $fatal(1,"Level 3 spawn or flag moved");
        if (tnt_count != 0 || hazard_count != 0 || map_id) $fatal(1,"Level 3 has unexpected objects or map");
        // Level 4, Cave Flight: the second map, start at the bottom left, flag on the top-right ledge.
        level=3; #1;
        if (!map_level || !map_id || world_width != `LP_FLIGHT_WIDTH || world_height != `LP_FLIGHT_HEIGHT)
            $fatal(1,"Level 4 is not the Cave Flight map");
        if (spawn_x !== 20'sd17408 || spawn_y !== 20'sd45568 || flag_x != 769 || flag_y != 50)
            $fatal(1,"Level 4 spawn or flag moved");

        clocks(3); reset=0; clocks(2);
        // Level select: only in BUILD, and launch on the same clock wins.
        if (state !== `LP_BUILD || level_index !== 0) $fatal(1,"Reset state wrong");
        pulse(LEVEL);
        if (level_index !== 1) $fatal(1,"Level request ignored in BUILD");
        launch=1; level_next=1; clocks(1); launch=0; level_next=0; clocks(1);
        if (level_index !== 1 || state === `LP_BUILD) $fatal(1,"Level changed while launching");
        clocks(2); pulse(LEVEL);
        if (level_index !== 1) $fatal(1,"Level changed outside BUILD");

        // Fail reasons in priority order: pig, hazard, then bounds.
        pulse(TICK); live=0; hazard=1; bounds=1; world_valid=1; clocks(1);
        world_valid=0; live=1; hazard=0; bounds=0; clocks(1);
        if (state !== `LP_FAIL || fail_reason !== `LP_FAIL_PIG) $fatal(1,"Pig loss not reported first");
        pulse(RETRY); clocks(2);
        if (fail_reason !== `LP_FAIL_NONE || level_index !== 1) $fatal(1,"Retry kept old reason or changed level");
        pulse(TICK); hazard=1; bounds=1; goal=1; world_valid=1; clocks(1);
        world_valid=0; hazard=0; bounds=0; goal=0; clocks(1);
        if (state !== `LP_FAIL || fail_reason !== `LP_FAIL_HAZARD) $fatal(1,"Hazard not reported before bounds/goal");
        pulse(EDIT);
        if (state !== `LP_BUILD || fail_reason !== `LP_FAIL_NONE) $fatal(1,"Edit did not clear the result");
        if (level_index !== 1) $fatal(1,"Edit after FAIL changed the level");
        run_one_step(1'b0, 1'b0, 1'b1, 1'b1);
        if (state !== `LP_FAIL || fail_reason !== `LP_FAIL_BOUNDS) $fatal(1,"Out of bounds not reported");
        pulse(EDIT); run_one_step(1'b1, 1'b0, 1'b0, 1'b1);
        if (state !== `LP_SUCCESS || fail_reason !== `LP_FAIL_NONE) $fatal(1,"Goal did not succeed cleanly");
        pulse(EDIT);
        if (state !== `LP_BUILD || level_index !== 2) $fatal(1,"Edit after SUCCESS did not move to the next level");
        pulse(LEVEL);
        if (level_index !== 3) $fatal(1,"Level select did not reach level 4");
        pulse(LEVEL);
        if (level_index !== 0) $fatal(1,"Level select did not wrap from level 4 to level 1");
        // Timer: four ticks per second here; counts during RUN, freezes on a result, clears on retry.
        pulse(LAUNCH); clocks(2);
        for (index = 0; index < 9; index = index + 1) pulse(TICK);
        if (run_seconds !== 2) $fatal(1,"Run timer wrong: %0d",run_seconds);
        live=0; world_valid=1; clocks(1); world_valid=0; live=1; clocks(1);
        pulse(TICK); pulse(TICK); pulse(TICK); pulse(TICK);
        if (state !== `LP_FAIL || run_seconds !== 2) $fatal(1,"Timer did not freeze on the result");
        pulse(RETRY); clocks(2);
        if (run_seconds !== 0) $fatal(1,"Retry did not clear the timer");

        // Explosion phases: start on a falling intact bit, step every two ticks, then stop.
        fx_intact=4'b1101; clocks(2);
        if (fx_phase !== 8'b00000100) $fatal(1,"Explosion did not start for TNT 1");
        fx_tick=1; clocks(2); fx_tick=0; clocks(1);
        if (fx_phase[3:2] !== 2'd2) $fatal(1,"Explosion did not advance");
        fx_tick=1; clocks(4); fx_tick=0; clocks(1);
        if (fx_phase !== 0) $fatal(1,"Explosion did not finish");
        fx_init=1; fx_intact=4'b1111; clocks(1); fx_init=0; clocks(2);
        if (fx_phase !== 0) $fatal(1,"Restored TNT started an explosion");

        // The shared map/gear hitbox is x=[78,96), y=[55,64). The old
        // outside sample x=81 became an inside point when this button widened.
        check_button_click(`LP_LEVEL_BUTTON_X,`LP_LEVEL_BUTTON_Y,1);
        check_button_click(`LP_LEVEL_BUTTON_X+`LP_LEVEL_BUTTON_W-1,`LP_LEVEL_BUTTON_Y,1);
        check_button_click(`LP_LEVEL_BUTTON_X,`LP_LEVEL_BUTTON_Y+`LP_LEVEL_BUTTON_H-1,1);
        check_button_click(`LP_LEVEL_BUTTON_X+`LP_LEVEL_BUTTON_W-1,`LP_LEVEL_BUTTON_Y+`LP_LEVEL_BUTTON_H-1,1);
        check_button_click(`LP_LEVEL_BUTTON_X-1,59,0);
        check_button_click(`LP_LEVEL_BUTTON_X+`LP_LEVEL_BUTTON_W,59,0);
        check_button_click(88,`LP_LEVEL_BUTTON_Y-1,0);
        check_button_click(88,`LP_LEVEL_BUTTON_Y+`LP_LEVEL_BUTTON_H,0);
        index=button_pulses;
        button_packet(88,59,1,0);
        if(button_pulses!=index+1) $fatal(1,"Fresh button press was lost");
        button_packet(88,59,1,0); button_packet(77,59,1,0); button_packet(88,59,1,0);
        if(button_pulses!=index+1) $fatal(1,"Held/dragged button press repeated");
        button_packet(88,59,0,0); index=button_pulses;
        button_packet(88,59,1,1); button_packet(88,59,1,0);
        if(button_pulses!=index) $fatal(1,"Right-click or its held-left release selected a level");
        button_packet(88,59,0,0);
        button_state=`LP_RUN; check_button_click(88,59,0);
        button_state=`LP_BUILD; button_enabled=0; check_button_click(88,59,0);
        button_packet(88,59,1,0); index=button_pulses; button_enabled=1;
        button_packet(88,59,1,0);
        if(button_pulses!=index) $fatal(1,"Hidden held press became a fresh button press");
        button_packet(88,59,0,0); check_button_click(88,59,1);
        // Settings has a separate map-row hitbox; the BUILD icon is inactive.
        button_state=`LP_SETTINGS;
        check_button_click(8,30,1); check_button_click(87,43,1);
        check_button_click(7,35,0); check_button_click(88,35,0);
        check_button_click(30,29,0); check_button_click(30,44,0);
        check_button_click(88,59,0);
        button_state=`LP_BUILD;

        // Left view: level button text, then result messages.
        level=0; view_state=`LP_BUILD;
        expect_left(`LP_LEVEL_BUTTON_X, `LP_LEVEL_BUTTON_Y, 16'h7bef, "button border");
        expect_left(`LP_LEVEL_BUTTON_X+1, `LP_LEVEL_BUTTON_Y+1, 16'hffff, "button L");
        expect_left(`LP_LEVEL_BUTTON_X+9, `LP_LEVEL_BUTTON_Y+1, 16'hffff, "button 1");
        expect_left(`LP_LEVEL_BUTTON_X+8, `LP_LEVEL_BUTTON_Y+1, 16'h0010, "button 1 gap");
        level=1;
        expect_left(`LP_LEVEL_BUTTON_X+8, `LP_LEVEL_BUTTON_Y+1, 16'hffff, "button 2");
        view_state=`LP_FAIL; view_reason=`LP_FAIL_PIG;
        expect_left(0, 56, 16'hf800, "PIG LOST text");
        expect_left(83, 56, 16'h0841, "no button after run");
        view_state=`LP_SUCCESS; view_reason=`LP_FAIL_NONE;
        expect_left(0, 56, 16'h07e0, "LEVEL CLEAR text");
        expect_left(55, 32, 16'hffff, "C RETRY guidance");
        expect_left(54, 42, 16'hffe0, "U NEXT guidance");
        view_state=`LP_RUN;
        expect_left(5, 58, 16'h07e0, "runtime valid indicator");
        // Timer 12: tens digit 1 on the right segments, ones digit 2 starts with the top bar.
        view_seconds=12;
        expect_left(64, 8, 16'h07ff, "timer tens");
        expect_left(70, 6, 16'h07ff, "timer ones");
        expect_left(83, 19, 16'h07ff, "seconds label");
        // RUN uses the compact12-pixel grid at(4,12); BUILD/results retain16-pixel cells.
        expect_left(21, 27, 16'h07e0, "left pig sprite");
        expect_left(17, 34, 16'ha285, "left frame sprite");
        // Damage diagram: a destroyed wheel leaves a dim cross; survivors stay drawn.
        view_intact=9'b100110000;
        expect_left(7, 39, 16'h8000, "damage cross");
        expect_left(21, 27, 16'h07e0, "surviving pig");
        view_state=`LP_BUILD;
        expect_left(7, 39, 16'h0841, "no cross in BUILD");
        view_intact=9'b101110000;

        // Right view, level 1: TNT parts, then hiding an exploded block.
        level=0; view_state=`LP_BUILD;
        expect_right(46, 12, 16'hf1c5, "TNT red top");
        expect_right(44, 13, 16'hf1c5, "TNT body");
        expect_right(45, 14, 16'hffff, "TNT white middle");
        expect_right(45, 15, 16'h18c3, "TNT black letter");
        expect_right(47, 15, 16'hffff, "TNT letter gap");
        expect_right(40, 22, 16'h8320, "ledge");
        tnt_intact=0;
        expect_right(44, 13, 16'h0010, "exploded TNT");
        tnt_intact={`LP_MAX_TNT{1'b1}};
        // Before launch the vehicle sits at spawn even if physics holds an old position.
        vehicle_x=40*256;
        expect_right(14, 42, 16'h07e0, "pig at spawn in BUILD");
        expect_right(12, 42, 16'ha285, "frame at spawn in BUILD");
        expect_right(16, 44, 16'hfd18, "pig snout");
        // Engine cell at spawn (20,40): the pulley spoke turns on the second phase.
        expect_right(22, 41, 16'h5ae9, "engine casing");
        expect_right(22, 44, 16'hc618, "pulley rim");
        view_phase=1;
        expect_right(22, 44, 16'h4208, "pulley spoke turned");
        view_phase=0;
        // Left grid draws the 16 by 16 engine: the big pulley glint moves with the phase.
        expect_left(42, 28, 16'hffff, "16px pulley glint");
        view_phase=1;
        expect_left(42, 28, 16'hc618, "16px glint moved");
        expect_left(43, 30, 16'hffff, "16px glint new place");
        view_phase=0;
        view_state=`LP_RUN;
        expect_right(50, 42, 16'h07e0, "pig at vehicle in RUN");
        expect_right(14, 42, 16'h0010, "no pig left at spawn");
        // Explosion over TNT 0 (centre 48,16): yellow flash, orange edge, then grey smoke.
        view_blast=8'b01;
        expect_right(48, 16, 16'hffe0, "blast flash");
        expect_right(48, 10, 16'h0010, "flash radius");
        view_blast=8'b10;
        expect_right(48, 10, 16'hfd20, "fireball edge");
        view_blast=8'b11;
        expect_right(48, 16, 16'h8410, "smoke");
        view_blast=0;
        // Level 2: spikes, pit gap and path TNT.
        level=1; view_state=`LP_BUILD;
        expect_right(37, 58, 16'hc618, "spike tip");
        expect_right(36, 58, 16'h0010, "gap between spikes");
        expect_right(36, 60, 16'hc618, "spike base");
        expect_right(40, 63, 16'h8320, "pit floor");
        expect_right(60, 49, 16'hf1c5, "path TNT");
        view_state=`LP_FAIL;
        expect_right(0, 0, 16'hf800, "fail border");

        // Map view, level 1: the camera (0,20) frames the spawn at 1.5x with 12 by 12 sprites.
        level=0; view_state=`LP_BUILD; zoomed_out=0;
        expect_right(22, 33, 16'h07e0, "1.5x pig");
        expect_right(7, 34, 16'ha285, "1.5x frame");
        expect_right(50, 60, 16'h8320, "1.5x ground");
        // Level 3: night sky above the start plateau and grass along its top edge (map ROM).
        // At 2x the spawn view starts lower, in the sky's second band.
        level=2;
        expect_right(0, 0, 16'h4af1, "map sky");
        expect_right(39, 51, 16'h2bc3, "plateau grass");
        // The camera follows the vehicle across the map, here to the finish flag.
        view_state=`LP_RUN; vehicle_x=570*256; vehicle_y=457*256;
        expect_right(76, 38, 16'hec05, "flag pole");
        expect_right(78, 38, 16'hffff, "flag white square");
        expect_right(81, 38, 16'h0000, "flag black square");
        // Free look: the cursor, not the vehicle, picks the camera; the corners reach the map edges.
        free_look=1; look_x=0; look_y=0;
        expect_right(0, 0, 16'h322d, "free look top-left sky");
        look_x=95; look_y=63;
        expect_right(0, 63, 16'h1082, "free look bottom underground");
        free_look=0;
        zoomed_out=1; vehicle_x=1024; vehicle_y=8192; level=0;

        $display("PASS role4_game_display_tb: levels, level select, next level, fail reasons, timer, explosions, level button, guidance, damage diagram, sprites, TNT, hazards, spawn preview");
        $finish;
    end
    initial begin #200000; $fatal(1,"Role 4 test timed out"); end
endmodule
