// Owner: Shared. Independent rotated-square/terrain and handshake validation.
`timescale 1ns / 1ps
`include "game_defs.vh"
module rotating_collision_tb;
    reg clk=0, reset=1, move_valid=0, response_ready=0;
    always #5 clk=~clk;
    reg map_level=1, rotation_enabled=1;
    reg signed [19:0] px=0,py=0,nx=0,ny=0;
    reg signed [15:0] vx=0,vy=0;
    reg signed [`LP_TILT_BITS-1:0] old_tilt=0,new_tilt=0;
    reg [9:0] width=192,height=192;
    reg [3:0] scene=0;
    reg [2:0] query_class=`LP_MAP_CAVE;
    wire signed [10:0] qx,qy;
    wire signed [19:0] cx,cy;
    wire signed [15:0] cvx,cvy;
    wire signed [`LP_TILT_BITS-1:0] tilt;
    wire signed [7:0] slope;
    wire move_ready,response_valid,grounded;
    reg [84+`LP_TILT_BITS-4:0] held;
    integer waited,max_latency=0,cases=0,index;
    integer floor_y,left_start,right_start,up_start,down_start,xx,yy;
    integer saved_y;
    reg captured_map;

    function solid_pixel;
        input integer x,y;
        integer floor;
        begin
            floor=140; solid_pixel=0;
            if (x>=0 && x<192 && y>=0 && y<192) begin
                case(scene)
                    0: solid_pixel=0;
                    1: solid_pixel=y>=140;
                    2: solid_pixel=y>=140 || x>=120;
                    3: solid_pixel=y<50 || y>=160;
                    4: solid_pixel=y<100 || y>=124;
                    5: begin floor=100+x-64; solid_pixel=y>=floor; end
                    6: begin floor=187-x; solid_pixel=y>=floor; end
                    7: solid_pixel=y>=140 || x<=40;
                    8: solid_pixel=y>=140 || x==120;
                    default: solid_pixel=0;
                endcase
            end
        end
    endfunction
    always @(posedge clk) query_class<=solid_pixel($signed(qx),$signed(qy)) ? `LP_MAP_ROCK : `LP_MAP_CAVE;

    collision_engine dut (
        .clk(clk),.reset(reset),.move_valid(move_valid),.move_ready(move_ready),
        .previous_x(px),.previous_y(py),.proposed_x(nx),.proposed_y(ny),
        .previous_tilt(old_tilt),.proposed_tilt(new_tilt),
        .proposed_vx(vx),.proposed_vy(vy),.terrain_count(3'd1),
        .terrain_rects({96'd0,8'd52,8'd192,8'd140,8'd0}),
        .map_level(map_level),.rotation_enabled(rotation_enabled),
        .world_width(width),.world_height(height),.query_x(qx),.query_y(qy),.query_class(query_class),
        .response_valid(response_valid),.response_ready(response_ready),
        .corrected_x(cx),.corrected_y(cy),.corrected_vx(cvx),.corrected_vy(cvy),
        .corrected_tilt(tilt),.grounded(grounded),.ground_slope(slope)
    );

    // Independent real-valued SAT oracle for the square defined by the
    // renderer's inverse map. The four separating axes include both pixel
    // cell axes, not merely whether its centre lies inside the body.
    function overlap_pixel;
        input integer pose_x,pose_y,angle,pixel_x,pixel_y;
        integer cosine,sine;
        real c,s,abs_s,norm,extent,dx,dy,u,v,limit;
        begin
            cosine=256; sine=0;
            case(angle)
                 1: begin cosine=251;sine=50;end
                -1: begin cosine=251;sine=-50;end
                 2: begin cosine=237;sine=98;end
                -2: begin cosine=237;sine=-98;end
                 3: begin cosine=213;sine=142;end
                -3: begin cosine=213;sine=-142;end
                 4: begin cosine=181;sine=181;end
                -4: begin cosine=181;sine=-181;end
            endcase
            c=cosine/256.0;s=sine/256.0;abs_s=s<0 ? -s : s;
            norm=c*c+s*s;extent=12.0*(c+abs_s)/norm;
            dx=pixel_x+0.5-pose_x/256.0-12.0;
            dy=pixel_y+0.5-pose_y/256.0-12.0;
            u=c*dx+s*dy;v=-s*dx+c*dy;
            limit=12.0+0.5*(c+abs_s);
            overlap_pixel=dx<extent+0.5 && dx> -extent-0.5 &&
                          dy<extent+0.5 && dy> -extent-0.5 &&
                          u<limit && u> -limit && v<limit && v> -limit;
        end
    endfunction
    function overlap_terrain;
        input integer pose_x,pose_y,angle;
        integer x,y;
        begin
            overlap_terrain=0;
            for(y=(pose_y >>> 8)-7;y<=(pose_y >>> 8)+31;y=y+1)
                for(x=(pose_x >>> 8)-7;x<=(pose_x >>> 8)+31;x=x+1)
                    if(solid_pixel(x,y) && overlap_pixel(pose_x,pose_y,angle,x,y)) overlap_terrain=1;
        end
    endfunction
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk);end
    endtask
    task move;
        input integer old_x,old_y,proposed_x,proposed_y,input_vx,input_vy,previous_angle,wanted_angle;
        input integer expected_ground,expected_tilt;
        begin
            captured_map=map_level;
            width=192;height=192;rotation_enabled=1;
            px=old_x;py=old_y;nx=proposed_x;ny=proposed_y;vx=input_vx;vy=input_vy;
            old_tilt=previous_angle;new_tilt=wanted_angle;
            if(!move_ready) $fatal(1,"Rotating checker unavailable");
            move_valid=1;clocks(1);move_valid=0;
            px=0;py=0;nx=0;ny=0;vx=0;vy=0;old_tilt=0;new_tilt=0;
            map_level=!captured_map;rotation_enabled=0;width=1;height=1;
            waited=0;
            while(!response_valid && waited<200000) begin clocks(1);waited=waited+1;end
            if(!response_valid) $fatal(1,"Rotated case%0d exceeded cycle budget",cases);
            if(waited>max_latency) max_latency=waited;
            if(overlap_terrain($signed(cx),$signed(cy),$signed(tilt)))
                $fatal(1,"Rotated case%0d penetrates scene%0d: pose(%0d,%0d) angle%0d",cases,scene,cx,cy,tilt);
            if(grounded && (!overlap_terrain($signed(cx),$signed(cy)+1,$signed(tilt)) || cvy!==0))
                $fatal(1,"Rotated case%0d grounded without exact supporting terrain",cases);
            if(expected_ground>=0 && grounded!==expected_ground[0])
                $fatal(1,"Rotated case%0d unexpected ground%0d, expected%0d",cases,grounded,expected_ground);
            if(tilt!==expected_tilt[`LP_TILT_BITS-1:0])
                $fatal(1,"Rotated case%0d angle%0d, expected%0d",cases,tilt,expected_tilt);
            held={cx,cy,cvx,cvy,tilt,grounded,slope};
            move_valid=1;clocks(7);
            if(move_ready || !response_valid || {cx,cy,cvx,cvy,tilt,grounded,slope}!==held)
                $fatal(1,"Rotated response changed under backpressure");
            move_valid=0;response_ready=1;clocks(1);response_ready=0;
            map_level=captured_map;
            if(!move_ready || response_valid) $fatal(1,"Rotated response did not release");
            cases=cases+1;
        end
    endtask

    initial begin
        clocks(3);reset=0;clocks(1);
        // All orientations remain clear and stationary in open air.
        scene=0;
        for(index=-4;index<=4;index=index+1) begin
            move(64*256,64*256,64*256,64*256,0,0,index,index,0,index);
            if(cx!==64*256 || cy!==64*256 || cvx!==0 || cvy!==0)
                $fatal(1,"Stationary rotated air pose changed");
        end
        move(64*256,64*256,64*256,64*256,0,0,0,4,0,4);
        // A flat zero-tilt contact retains the original exact coordinates.
        scene=1;
        move(64*256,116*256,64*256,116*256+32,0,32,0,0,1,0);
        if(cy!==116*256) $fatal(1,"Flat rotated route changed exact floor contact");
        // Area-based collision must stop both diagonal corner orientations.
        move(64*256,110*256,64*256,114*256,0,1024,4,4,1,4);
        saved_y=cy;
        if(cy>=114*256 || cvy!==0) $fatal(1,"Rotated floor did not stop fall");
        move(64*256,110*256,64*256,114*256,0,1024,-4,-4,1,-4);
        if(cy!==saved_y) $fatal(1,"Symmetric tilted floor contacts differ");
        for(index=-3;index<=3;index=index+1)
            if(index!=0) move(64*256,110*256,64*256,116*256,0,1536,index,index,1,index);
        scene=2;
        move(90*256,saved_y,94*256,saved_y+32,1024,32,4,4,1,4);
        if(cx>=94*256 || cvx!==0) $fatal(1,"Rotated right wall was tunneled");
        scene=7;
        move(46*256,saved_y,42*256,saved_y+32,-1024,32,-4,-4,1,-4);
        if(cx<=42*256 || cvx!==0) $fatal(1,"Rotated left wall was tunneled");
        scene=8;
        move(90*256,saved_y,94*256,saved_y+32,1024,32,4,4,1,4);
        if(cx>=94*256 || cvx!==0) $fatal(1,"Thin wall was tunneled by rotated body");
        scene=3;
        move(64*256,56*256,64*256,50*256,0,-1536,4,4,0,4);
        if(cy<=50*256 || cvy!==0) $fatal(1,"Rotated ceiling was tunneled");
        // This 24-pixel passage fits only an upright square; a requested turn
        // must retain the old safe angle rather than rotate through its roof.
        scene=4;
        move(64*256,100*256,64*256,100*256+32,0,32,0,1,1,0);
        if(cy!==100*256) $fatal(1,"Blocked turn moved through corridor roof/floor");
        scene=5;
        move(64*256,76*256,64*256,76*256+32,0,32,0,1,1,1);
        if(slope!==16) $fatal(1,"Rotated contact lost downhill slope measurement");
        scene=6;
        move(64*256,76*256,64*256,76*256+32,0,32,0,-1,1,-1);
        if(slope!==-16) $fatal(1,"Rotated contact lost uphill slope measurement");
        // A later rectangle transaction must clear the rotated response route.
        scene=1;map_level=0;
        move(64*256,116*256,64*256,116*256+32,0,32,4,4,1,0);
        if(cy!==116*256 || slope!==0) $fatal(1,"Rectangle response inherited rotation");
        // Reset during a live terrain read cancels the pending orientation.
        scene=0;map_level=1;rotation_enabled=1;width=192;height=192;
        px=64*256;py=64*256;nx=65*256;ny=64*256;old_tilt=4;new_tilt=4;
        move_valid=1;clocks(1);move_valid=0;clocks(10);
        reset=1;clocks(1);reset=0;clocks(3);
        if(!move_ready || response_valid) $fatal(1,"Reset retained a rotated transaction");
        move(64*256,64*256,64*256,64*256,0,0,-4,-4,0,-4);
        // The fixture's address(0,0) is solid here. Outside scan coordinates
        // must be masked rather than aliasing that registered ROM response.
        scene=3;
        move(1024*256,64*256,1025*256,65*256,256,256,4,4,0,4);
        if(cx!==1025*256 || cy!==65*256) $fatal(1,"Outside rotated coordinates aliased terrain");
        move(-2048*256,-1000*256,-2048*256,-1001*256,0,-256,-4,-4,0,-4);
        if(cx!==-2048*256 || cy!==-1001*256) $fatal(1,"Numeric edge wrapped rotated pose");
        $display("PASS rotating_collision_tb: %0d independent SAT, floor/wall/ceiling, slope, blocked turn, route, backpressure and reset cases; max latency=%0d clocks",cases,max_latency);
        $finish;
    end
    initial begin #50000000;$fatal(1,"Rotating collision tests timed out");end
endmodule
