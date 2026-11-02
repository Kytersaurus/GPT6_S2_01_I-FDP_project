// Owner: Role 3 - Kyle/Yap Ting. Rotation origin shifts retain terrain contact.
`timescale 1ns / 1ps
`include "game_defs.vh"
module pivot_slope_contact_tb;
    reg clk=0,reset=1,start=0,ready=0;
    reg signed [19:0] px=0,py=0,nx=0,ny=0;
    reg signed [15:0] vx=0,vy=0;
    reg signed [4:0] old_tilt=0,new_tilt=0;
    reg stairs=0;
    integer direction=1;
    reg [2:0] query_class=`LP_MAP_SKY;
    wire signed [10:0] qx,qy;
    wire request_ready,valid,grounded;
    wire signed [19:0] cx,cy;
    wire signed [15:0] cvx,cvy;
    wire signed [4:0] tilt;
    integer cases=0,waited,angle,travel,start_x;
    reg [77:0] held;
    always #5 clk=~clk;
    function solid;
        input integer x,y;
        integer floor_y;
        begin
            floor_y=140;
            if(stairs && ((direction>0 && x>=102) || (direction<0 && x<90))) floor_y=138;
            solid=x>=0 && x<192 && y>=floor_y && y<192;
        end
    endfunction
    always @(posedge clk) query_class<=solid($signed(qx),$signed(qy)) ? `LP_MAP_ROCK : `LP_MAP_SKY;
    rotating_map_collision_engine dut(
        .clk(clk),.reset(reset),.move_valid(start),.move_ready(request_ready),
        .previous_x(px),.previous_y(py),.proposed_x(nx),.proposed_y(ny),
        .previous_tilt(old_tilt),.proposed_tilt(new_tilt),.collision_mask(9'h1ff),
        .proposed_vx(vx),.proposed_vy(vy),.world_width(10'd192),.world_height(10'd192),
        .query_x(qx),.query_y(qy),.query_class(query_class),
        .response_valid(valid),.response_ready(ready),.corrected_x(cx),.corrected_y(cy),
        .corrected_vx(cvx),.corrected_vy(cvy),.corrected_tilt(tilt),.grounded(grounded),
        .ground_slope(),.tip_dir(),.support_unstable());
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task move;
        input integer origin_x,delta_x,requested_vy,wanted_angle,expected_ground,require_x;
        begin
            px=origin_x*256;py=116*256;nx=px+delta_x;ny=py-64;
            vx=delta_x;vy=requested_vy;old_tilt=0;new_tilt=wanted_angle;
            if(!request_ready) $fatal(1,"Pivot collision request unavailable");
            start=1;clocks(1);start=0;waited=0;
            while(!valid && waited<200000) begin clocks(1);waited=waited+1;end
            if(!valid) $fatal(1,"Pivot collision response timeout");
            if(grounded!==expected_ground[0])
                $fatal(1,"Pivot case%0d stairs%0d angle%0d vy%0d expected ground%0d got%0d x%0d y%0d vx%0d",cases,stairs,wanted_angle,requested_vy,expected_ground,grounded,cx,cy,cvx);
            if(tilt!==wanted_angle[4:0]) $fatal(1,"Pivot case%0d rejected safe rotation",cases);
            if(require_x && (cx!==nx || cvx!==vx)) $fatal(1,"Pivot case%0d lost horizontal momentum",cases);
            if(expected_ground && cvy!==0) $fatal(1,"Pivot grounded response retained vertical velocity");
            if(!expected_ground && cvy!==requested_vy) $fatal(1,"Pivot upward motion was blocked");
            held={cx,cy,cvx,cvy,tilt,grounded};clocks(3);
            if(!valid || {cx,cy,cvx,cvy,tilt,grounded}!==held) $fatal(1,"Pivot response changed under backpressure");
            ready=1;clocks(1);ready=0;cases=cases+1;
        end
    endtask
    initial begin
        clocks(3);reset=0;clocks(1);
        // Origin y moves up 1/4 pixel while physical vertical velocity points
        // down. An actual COM-preserving rotation can produce this combination.
        for(travel=-1;travel<=1;travel=travel+2) begin
            direction=travel;
            for(angle=-1;angle<=1;angle=angle+2) begin
                stairs=0;move(64,travel*256,32,angle,1,1);
                // Genuine upward velocity always detaches, even while turning.
                move(64,travel*256,-32,angle,0,1);
            end
            // Position-only upward moves without a turn retain their contract.
            move(64,travel*256,0,0,0,1);
            stairs=1;start_x=travel>0 ? 74 : 94;
            for(angle=-1;angle<=1;angle=angle+2) begin
                move(start_x,travel*1024,32,angle,1,1);
                move(start_x,travel*1024,-32,angle,0,0);
            end
        end
        $display("PASS pivot_slope_contact_tb: %0d mirrored flat/stair origin shifts retain coasting contact; real jumps and unchanged-angle upward moves detach",cases);$finish;
    end
    initial begin #100000000;$fatal(1,"Pivot slope contact timeout");end
endmodule
