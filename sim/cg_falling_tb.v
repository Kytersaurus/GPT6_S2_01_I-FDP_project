`timescale 1ns / 1ps
`include "game_defs.vh"
module cg_falling_tb;
    reg clk=0,reset=1,init=0,step=0,release_step=0;
    reg [2:0] state=`LP_BUILD,scene=0;
    reg signed [19:0] spawn_x=80*256;
    wire move_valid,move_ready,response_valid,response_ready,committed,grounded,unstable;
    wire signed [19:0] px,py,nx,ny,cx,cy,x,y;
    wire signed [15:0] vx,vy,cvx,cvy;
    wire signed [4:0] pt,nt,ct,tilt;
    wire signed [1:0] tip;
    wire signed [7:0] slope;
    wire signed [10:0] qx,qy;
    reg [2:0] map_class=0;
    integer waited,updates,saw_tip;
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(($signed(qy)>=160) || ($signed(qy)>=104 &&
            ((scene==0 && $signed(qx)<90) || (scene==1 && $signed(qx)>=114) ||
             (scene==2 && ($signed(qx)<84 || $signed(qx)>=100))))) map_class<=`LP_MAP_ROCK;
        else map_class<=`LP_MAP_CAVE;
    end
    physics_engine physics(.clk(clk),.reset(reset),.run_init(init),.game_state(state),
        .spawn_x(spawn_x),.spawn_y(20'sd20480),.step_start(step),.update_release(release_step),
        .wheel_count(4'd0),.engine_count(4'd0),.balloon_count(4'd0),.mass_units(8'd20),
        .engine_enabled(1'b0),.engine_reverse(1'b0),.jump_press(1'b0),.boost_req(1'b0),
        .fan_balance(5'sd0),.rocket_balance(5'sd0),.rocket_count(4'd0),.fan_enabled(1'b0),.rocket_req(1'b0),
        .tip_dir(tip),.support_unstable(unstable),.move_valid(move_valid),.move_ready(move_ready),
        .previous_x(px),.previous_y(py),.proposed_x(nx),.proposed_y(ny),.proposed_vx(vx),.proposed_vy(vy),
        .previous_tilt(pt),.proposed_tilt(nt),.response_valid(response_valid),.response_ready(response_ready),
        .corrected_x(cx),.corrected_y(cy),.corrected_vx(cvx),.corrected_vy(cvy),.corrected_tilt(ct),
        .grounded(grounded),.ground_slope(slope),.movement_committed(committed),.vehicle_x(x),.vehicle_y(y),.vehicle_tilt(tilt));
    collision_engine #(.ROTATION_ONLY(1)) collision(.clk(clk),.reset(reset),.move_valid(move_valid),.move_ready(move_ready),
        .previous_x(px),.previous_y(py),.proposed_x(nx),.proposed_y(ny),.proposed_vx(vx),.proposed_vy(vy),
        .terrain_count(3'd0),.terrain_rects(128'd0),.map_level(1'b1),.rotation_enabled(1'b1),
        .previous_tilt(pt),.proposed_tilt(nt),.collision_mask(9'h1ff),.cg_enabled(1'b1),
        .build_grid({12'd0,`LP_PART_PIG,12'd0}),.part_intact_mask(9'b000010000),.frame_intact_mask(9'h1ff),
        .world_width(10'd192),.world_height(10'd192),.query_x(qx),.query_y(qy),.query_class(map_class),
        .response_valid(response_valid),.response_ready(response_ready),.corrected_x(cx),.corrected_y(cy),
        .corrected_vx(cvx),.corrected_vy(cvy),.corrected_tilt(ct),.grounded(grounded),.ground_slope(slope),
        .tip_dir(tip),.support_unstable(unstable));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task restart;begin init=1;state=`LP_INIT_RUN;clocks(2);init=0;state=`LP_RUN;saw_tip=0;end endtask
    task update;begin
        step=1;clocks(1);step=0;waited=0;
        while(!committed && waited<150000) begin clocks(1);waited=waited+1;end
        if(!committed) $fatal(1,"CG movement timeout");
        if(unstable && tip!=0) saw_tip=1;
        release_step=1;clocks(1);release_step=0;clocks(1);
    end endtask
    initial begin
        clocks(3);reset=0;restart();updates=0;
        while(y<130*256 && updates<100) begin update();updates=updates+1;end
        if(!saw_tip || y<130*256 || x<=80*256) $fatal(1,"Right overhang did not slide/fall: x%0d y%0d tilt%0d",x,y,tilt);
        scene=1;spawn_x=100*256;restart();updates=0;
        while(y<130*256 && updates<100) begin update();updates=updates+1;end
        if(!saw_tip || y<130*256 || x>=100*256) $fatal(1,"Left overhang did not slide/fall: x%0d y%0d tilt%0d",x,y,tilt);
        scene=2;spawn_x=80*256;restart();repeat(20) update();
        if(saw_tip || x!=80*256 || y!=80*256 || tilt!=0) $fatal(1,"Bridging a gap caused false falling");
        $display("PASS cg_falling_tb: unpowered left/right overhangs tip, slide and fall; two-contact bridge stays stable");$finish;
    end
    initial begin #100000000;$fatal(1,"CG falling timeout");end
endmodule
