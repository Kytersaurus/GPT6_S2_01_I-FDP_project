// Owner: Role 2/3 integration. Rejected turns discard only geometric COM shifts.
`timescale 1ns / 1ps
`include "game_defs.vh"
module blocked_pivot_contact_tb;
    reg clk=0,reset=1,start=0,ready=0;
    reg roof=0,floor_present=0;
    reg signed [19:0] px=0,py=0,nx=0,ny=0;
    reg signed [15:0] vx=0,vy=0;
    reg signed [13:0] pivot_x=0,pivot_y=0;
    reg signed [4:0] old_tilt=0,wanted_tilt=0;
    reg [2:0] query_class=`LP_MAP_SKY;
    wire signed [10:0] qx,qy;
    wire request_ready,valid,grounded;
    wire signed [19:0] cx,cy;
    wire signed [15:0] cvx,cvy;
    wire signed [4:0] tilt;
    integer waited,cases=0,travel,angle;
    reg [77:0] held;
    always #5 clk=~clk;
    function solid;
        input integer x,y;
        begin
            solid=x>=0 && x<192 && y>=0 && y<192 &&
                  ((floor_present && y>=140) || (roof && y<116));
        end
    endfunction
    always @(posedge clk)
        query_class<=solid($signed(qx),$signed(qy)) ? `LP_MAP_ROCK : `LP_MAP_SKY;
    rotating_map_collision_engine dut(
        .clk(clk),.reset(reset),.move_valid(start),.move_ready(request_ready),
        .previous_x(px),.previous_y(py),.proposed_x(nx),.proposed_y(ny),
        .previous_tilt(old_tilt),.proposed_tilt(wanted_tilt),.collision_mask(9'h1ff),
        .proposed_vx(vx),.proposed_vy(vy),.pivot_dx_q8(pivot_x),.pivot_dy_q8(pivot_y),
        .world_width(10'd192),.world_height(10'd192),.query_x(qx),.query_y(qy),
        .query_class(query_class),.response_valid(valid),.response_ready(ready),
        .corrected_x(cx),.corrected_y(cy),.corrected_vx(cvx),.corrected_vy(cvy),
        .corrected_tilt(tilt),.grounded(grounded),.ground_slope(),.tip_dir(),
        .support_unstable(),.ground_slope_valid(),.support_span_valid(),
        .support_left_q2(),.support_right_q2());
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task move;
        input integer ceiling_on,ground_on,physical_vx,wanted_angle,shift_x,shift_y;
        integer expected_x,expected_y;
        begin
            roof=ceiling_on;floor_present=ground_on;
            px=64*256;py=116*256;vx=physical_vx;vy=0;
            pivot_x=shift_x;pivot_y=shift_y;
            nx=px+physical_vx+shift_x;ny=py+shift_y;
            old_tilt=0;wanted_tilt=wanted_angle;
            expected_x=ceiling_on ? px+physical_vx : nx;
            expected_y=ceiling_on ? py : ny;
            if(!request_ready) $fatal(1,"Blocked-pivot request unavailable");
            start=1;clocks(1);start=0;waited=0;
            while(!valid && waited<200000) begin clocks(1);waited=waited+1;end
            if(!valid) $fatal(1,"Blocked-pivot response timeout");
            if(cx!==expected_x || cvx!==physical_vx)
                $fatal(1,"Case%0d roof%0d floor%0d angle%0d discarded real motion or retained rejected pivot: x%0d expected%0d vx%0d expected%0d",
                    cases,ceiling_on,ground_on,wanted_angle,cx,expected_x,cvx,physical_vx);
            if(tilt!==(ceiling_on ? 5'sd0 : wanted_angle[4:0]))
                $fatal(1,"Case%0d accepted blocked turn or rejected safe turn",cases);
            if(grounded!==ground_on[0]) $fatal(1,"Case%0d wrong contact classification",cases);
            if(!ground_on && (cy!==expected_y || cvy!==0))
                $fatal(1,"Case%0d retained rejected vertical pivot: y%0d expected%0d",cases,cy,expected_y);
            if(ground_on && (cvy!==0 || (ceiling_on && cy!==py)))
                $fatal(1,"Case%0d rejected pivot displaced grounded body",cases);
            held={cx,cy,cvx,cvy,tilt,grounded};clocks(3);
            if(!valid || {cx,cy,cvx,cvy,tilt,grounded}!==held)
                $fatal(1,"Blocked-pivot response changed under backpressure");
            ready=1;clocks(1);ready=0;cases=cases+1;
        end
    endtask
    initial begin
        clocks(3);reset=0;clocks(1);
        for(travel=-1;travel<=1;travel=travel+2) begin
            for(angle=-1;angle<=1;angle=angle+2) begin
                // A narrow corridor blocks the turn. The Cartesian pivot may
                // oppose the real velocity but cannot cancel or reverse it.
                move(1,1,travel*128,angle,-travel*256,64);
                move(1,0,travel*128,angle,-travel*256,64);
                // With no linear force/velocity, blocked rotation cannot drift.
                move(1,1,0,angle,-travel*256,64);
                move(1,0,0,angle,-travel*256,64);
                // A safe accepted turn must keep its COM correction intact.
                move(0,1,travel*128,angle,-travel*256,64);
                move(0,0,travel*128,angle,-travel*256,64);
            end
        end
        $display("PASS blocked_pivot_contact_tb: %0d mirrored roof/floor cases preserve real motion, cancel rejected COM shifts, keep accepted shifts and hold responses",cases);$finish;
    end
    initial begin #100000000;$fatal(1,"Blocked-pivot collision timeout");end
endmodule
