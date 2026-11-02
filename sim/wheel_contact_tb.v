// Owner: Role 3 - tyre traction follows occupied near-contact cells.
`timescale 1ns / 1ps
`include "game_defs.vh"
module wheel_contact_tb #(parameter CG_ENABLED=1);
    reg clk=0,reset=1,request=0,ready=0,air=0;
    reg [26:0] grid=0;
    reg [8:0] alive=0,frames=9'h1ff;
    reg signed [4:0] angle=0;
    reg [2:0] query_class=0;
    wire signed [10:0] qx,qy;
    wire move_ready,valid,grounded,span_valid,slope_valid,unstable;
    wire [3:0] wheels;
    wire signed [9:0] left_q2,right_q2,y_q2;
    wire signed [19:0] cx,cy;
    wire signed [15:0] vx,vy;
    wire signed [7:0] slope;
    wire signed [4:0] result_angle;
    wire signed [1:0] tip;
    integer waited,cases=0;
    reg [154:0] held;
    wire signed [9:0] left_y_q2,right_y_q2;
    always #5 clk=~clk;
    always @(posedge clk) query_class<=($signed(qy)>=(air ? 150 : 104)) ? `LP_MAP_ROCK : `LP_MAP_SKY;
    rotating_map_collision_engine dut(.clk(clk),.reset(reset),.move_valid(request),.move_ready(move_ready),
        .previous_x(20'sd20480),.previous_y(20'sd20480),.proposed_x(20'sd20480),.proposed_y(20'sd20512),
        .previous_tilt(angle),.proposed_tilt(angle),.collision_mask(frames|alive),
        .proposed_vx(16'sd0),.proposed_vy(16'sd32),.cg_enabled(CG_ENABLED!=0),
        .build_grid(grid),.part_intact_mask(alive),.frame_intact_mask(frames),
        .world_width(10'd192),.world_height(10'd192),.query_x(qx),.query_y(qy),.query_class(query_class),
        .response_valid(valid),.response_ready(ready),.corrected_x(cx),.corrected_y(cy),
        .corrected_vx(vx),.corrected_vy(vy),.corrected_tilt(result_angle),.grounded(grounded),.ground_slope(slope),
        .ground_slope_valid(slope_valid),.support_span_valid(span_valid),.support_wheel_count(wheels),
        .support_left_q2(left_q2),.support_right_q2(right_q2),.support_y_q2(y_q2),.support_left_y_q2(left_y_q2),.support_right_y_q2(right_y_q2),.tip_dir(tip),.support_unstable(unstable));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task put;input integer cell_index;begin grid[cell_index*3 +:3]=`LP_PART_WHEEL;alive[cell_index]=1;frames[cell_index]=0;end endtask
    task check;input integer expected;begin
        if(!move_ready) $fatal(1,"Wheel contact request unavailable");
        request=1;clocks(1);request=0;waited=0;
        while(!valid && waited<200000) begin clocks(1);waited=waited+1;end
        if(!valid || wheels!==expected || grounded!==!air || span_valid!==!air)
            $fatal(1,"Wheel contact case%0d angle%0d air%b count%0d expected%0d ground%b span%b",cases,angle,air,wheels,expected,grounded,span_valid);
        if(result_angle!==angle || vx!==0) $fatal(1,"Contact query changed pose or velocity");
        held={cx,cy,vx,vy,result_angle,grounded,slope,slope_valid,span_valid,wheels,left_q2,right_q2,y_q2,left_y_q2,right_y_q2,tip,unstable};clocks(3);
        if(!valid || {cx,cy,vx,vy,result_angle,grounded,slope,slope_valid,span_valid,wheels,left_q2,right_q2,y_q2,left_y_q2,right_y_q2,tip,unstable}!==held)
            $fatal(1,"Wheel contacts changed under backpressure");
        ready=1;clocks(1);ready=0;clocks(1);cases=cases+1;
    end endtask
    initial begin
        clocks(3);reset=0;clocks(1);
        put(6);put(8);check(2);angle=-16;check(0);angle=8;check(1);angle=-8;check(1);
        grid=0;alive=0;frames=9'h1ff;put(0);put(2);angle=0;check(0);angle=-16;check(2);
        grid=0;alive=0;frames=9'h1ff;put(3);angle=0;check(0);angle=-8;check(1);angle=8;check(0);
        alive=0;angle=-8;check(0);
        grid=0;alive=0;frames=9'h1ff;put(6);put(8);angle=0;air=1;check(0);
        reset=1;clocks(1);reset=0;clocks(1);
        if(valid || span_valid || wheels!=0) $fatal(1,"Reset retained wheel contacts");
        $display("PASS wheel_contact_tb: CG_ENABLED=%0d %0d upright, inverted, side-mounted, raised, destroyed and airborne tyre contact cases",CG_ENABLED,cases);$finish;
    end
    initial begin #20000000;$fatal(1,"Wheel contact timeout");end
endmodule
