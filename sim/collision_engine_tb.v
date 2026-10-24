// Owner: Role 3 - Yap Ting; shared timing/integration checks for starter platform landing.
`timescale 1ns / 1ps
module collision_engine_tb;
    reg clk=0,reset=1,move_valid=0,response_ready=0;
    reg signed [15:0] px=0,py=0,nx=0,ny=0,vx=0,vy=0;
    reg [2:0] count=0;
    reg [127:0] terrain=0;
    wire move_ready,response_valid,grounded;
    wire signed [15:0] cx,cy,cvx,cvy;
    integer waited;
    reg [64:0] held;
    always #5 clk=~clk;
    collision_engine dut(.clk(clk),.reset(reset),.move_valid(move_valid),.move_ready(move_ready),
        .previous_x(px),.previous_y(py),.proposed_x(nx),.proposed_y(ny),.proposed_vx(vx),.proposed_vy(vy),
        .terrain_count(count),.terrain_rects(terrain),.response_valid(response_valid),.response_ready(response_ready),
        .corrected_x(cx),.corrected_y(cy),.corrected_vx(cvx),.corrected_vy(cvy),.grounded(grounded));
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk);end
    endtask
    task check;
        input integer left,old_y,new_y,speed_y,expected_y;
        input landed;
        begin
            nx=left;px=left;py=old_y;ny=new_y;vx=19;vy=speed_y;
            if(!move_ready) $fatal(1,"Collision request unavailable while idle");
            move_valid=1;clocks(1);move_valid=0;
            // Captured payload must survive changes after the request handshake.
            nx=0;ny=0;vy=-1;count=0;terrain=0;
            waited=0;while(!response_valid && waited<6) begin clocks(1);waited=waited+1;end
            if(!response_valid || grounded!==landed || cx!=left || cy!=expected_y || cvx!=19 || cvy!=(landed?0:speed_y))
                $fatal(1,"Collision response mismatch: x=%0d y=%0d vy=%0d grounded=%b",cx,cy,cvy,grounded);
            held={cx,cy,cvx,cvy,grounded};move_valid=1;clocks(4);
            if(move_ready || !response_valid || {cx,cy,cvx,cvy,grounded}!==held)
                $fatal(1,"Backpressure changed or overwrote the collision response");
            move_valid=0;response_ready=1;clocks(1);response_ready=0;
            if(response_valid || !move_ready) $fatal(1,"Collision did not release after handshake");
        end
    endtask
    task ground;
        begin count=1;terrain={96'd0,8'd8,8'd96,8'd56,8'd0};end
    endtask
    initial begin
        clocks(3);reset=0;clocks(1);
        ground();check(4*256,31*256,34*256,512,32*256,1);
        ground();check(-16*256,31*256,34*256,512,32*256,1);
        ground();check(-24*256,31*256,34*256,512,34*256,0); // Touching left edge is not overlap.
        ground();check(96*256,31*256,34*256,512,34*256,0);
        ground();check(4*256,31*256,34*256,-256,34*256,0); // Upward motion never lands.
        ground();check(4*256,34*256,35*256,256,35*256,0); // Already below the top.
        count=4;terrain={8'd8,8'd96,8'd52,8'd0,8'd8,8'd96,8'd56,8'd0,
                         8'd8,8'd96,8'd48,8'd0,8'd8,8'd96,8'd55,8'd0};
        check(4*256,20*256,34*256,512,24*256,1); // Choose highest crossed platform, regardless of ordering.
        count=2;terrain={64'd0,8'd0,8'd96,8'd48,8'd0,8'd8,8'd0,8'd48,8'd0};
        check(4*256,20*256,34*256,512,34*256,0); // Empty dimensions.
        count=1;terrain={96'd0,8'd8,8'd20,8'd56,8'd250};
        check(-10*256,31*256,34*256,512,34*256,0); // Rectangle-right addition must not wrap at 255.
        ground();move_valid=1;clocks(1);move_valid=0;reset=1;clocks(1);reset=0;clocks(4);
        if(response_valid || !move_ready) $fatal(1,"Reset did not discard a pending collision");
        $display("PASS collision_engine_tb: staged capture, four-platform selection, signed bounds, strict overlap, rising/below cases, empty rectangles, backpressure and reset");
        $finish;
    end
    initial begin #100000;$fatal(1,"Collision test timed out");end
endmodule
