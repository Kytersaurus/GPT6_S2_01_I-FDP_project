// Occupied parts, not empty construction cells, define cave collisions.
`timescale 1ns / 1ps
`include "game_defs.vh"
module occupied_map_collision_tb;
    reg clk=0,reset=1,move_valid=0,response_ready=0,map_level=1;
    always #5 clk=~clk;
    reg signed [19:0] px=0,py=0,nx=0,ny=0;
    reg signed [15:0] vx=0,vy=0;
    reg signed [`LP_TILT_BITS-1:0] old_tilt=0,new_tilt=0;
    reg [8:0] collision_mask=9'h1ff;
    reg [9:0] width=478,height=291;
    reg [2:0] scene=0,synthetic_class=`LP_MAP_CAVE;
    wire signed [10:0] qx,qy;
    wire rom_solid;
    wire [2:0] query_class=scene==0 ? (rom_solid ? `LP_MAP_ROCK : `LP_MAP_CAVE) : synthetic_class;
    wire signed [19:0] cx,cy;
    wire signed [15:0] cvx,cvy;
    wire signed [`LP_TILT_BITS-1:0] tilt;
    wire signed [7:0] slope;
    wire move_ready,response_valid,grounded;
    reg [84+`LP_TILT_BITS-4:0] held;
    reg [2:0] arch[0:512*`LP_MAP_HEIGHT-1];
    integer waited,max_latency=0,cases=0,angle,corner;
    localparam [8:0] CAR=9'b101111000, CENTRE=9'b000010000;
    initial $readmemh("cave_arch_map.mem",arch);
    // Collision uses the solid ROM, which leaves decorative grass open.
    reg [0:0] arch_solid[0:512*`LP_MAP_HEIGHT-1];
    initial $readmemh("cave_arch_solid.mem",arch_solid);

    function solid_pixel;
        input integer x,y;
        reg [2:0] value;
        begin
            solid_pixel=0;value=0;
            if(scene==0) begin
                if(x>=0 && x<`LP_MAP_WIDTH && y>=0 && y<`LP_MAP_HEIGHT) solid_pixel=arch_solid[y*512+x];
            end else if(x>=0 && x<192 && y>=0 && y<192) begin
                case(scene)
                    1: solid_pixel=0;
                    2: solid_pixel=y>=140;
                    3: solid_pixel=y<100 || y>=160;
                    4: solid_pixel=x>=120 || y>=160;
                    default: solid_pixel=0;
                endcase
            end
        end
    endfunction
    always @(posedge clk) synthetic_class<=solid_pixel($signed(qx),$signed(qy)) ? `LP_MAP_ROCK : `LP_MAP_CAVE;
    level_map #(.ARCH_SCALED(0)) rom (
        .map_id(1'b1),.draw_clk(clk),.draw_x(11'sd0),.draw_y(11'sd0),.draw_class(),
        .query_clk(clk),.query_map_id(1'b0),.query_x(qx),.query_y(qy),.query_class(),.query_solid(rom_solid)
    );
    collision_engine dut (
        .clk(clk),.reset(reset),.move_valid(move_valid),.move_ready(move_ready),
        .previous_x(px),.previous_y(py),.proposed_x(nx),.proposed_y(ny),
        .previous_tilt(old_tilt),.proposed_tilt(new_tilt),.collision_mask(collision_mask),
        .proposed_vx(vx),.proposed_vy(vy),.terrain_count(3'd0),.terrain_rects(128'd0),
        .map_level(map_level),.rotation_enabled(1'b1),.world_width(width),.world_height(height),
        .query_x(qx),.query_y(qy),.query_class(query_class),
        .response_valid(response_valid),.response_ready(response_ready),
        .corrected_x(cx),.corrected_y(cy),.corrected_vx(cvx),.corrected_vy(cvy),
        .corrected_tilt(tilt),.grounded(grounded),.ground_slope(slope)
    );

    // Independent four-axis SAT on each 8x8 inverse-raster cell. Real-valued
    // cell centres and extents account for the quantized basis's exact norm.
    function overlap_pixel;
        input integer pose_x,pose_y,rotation,pixel_x,pixel_y;
        input [8:0] parts;
        integer cosine,sine,i;
        real c,s,abs_s,norm,extent,dx,dy,u,v,limit,cu,cv,centre_x,centre_y;
        begin
            cosine=256;sine=0;
            case(rotation)
                 1:begin cosine=251;sine=50;end
                -1:begin cosine=251;sine=-50;end
                 2:begin cosine=237;sine=98;end
                -2:begin cosine=237;sine=-98;end
                 3:begin cosine=213;sine=142;end
                -3:begin cosine=213;sine=-142;end
                 4:begin cosine=181;sine=181;end
                -4:begin cosine=181;sine=-181;end
            endcase
            c=cosine/256.0;s=sine/256.0;abs_s=s<0 ? -s : s;
            norm=c*c+s*s;extent=4.0*(c+abs_s)/norm;
            dx=pixel_x+0.5-pose_x/256.0-12.0;
            dy=pixel_y+0.5-pose_y/256.0-12.0;
            u=c*dx+s*dy;v=-s*dx+c*dy;limit=4.0+0.5*(c+abs_s);
            overlap_pixel=0;
            for(i=0;i<9;i=i+1) if(parts[i]) begin
                cu=(i%3-1)*8.0;cv=(i/3-1)*8.0;
                centre_x=(c*cu-s*cv)/norm;centre_y=(s*cu+c*cv)/norm;
                if(dx-centre_x<extent+0.5 && dx-centre_x> -extent-0.5 &&
                   dy-centre_y<extent+0.5 && dy-centre_y> -extent-0.5 &&
                   u-cu<limit && u-cu> -limit && v-cv<limit && v-cv> -limit)
                    overlap_pixel=1;
            end
        end
    endfunction
    function overlap_terrain;
        input integer pose_x,pose_y,rotation;
        input [8:0] parts;
        integer xx,yy;
        begin
            overlap_terrain=0;
            for(yy=(pose_y>>>8)-7;yy<=(pose_y>>>8)+31;yy=yy+1)
                for(xx=(pose_x>>>8)-7;xx<=(pose_x>>>8)+31;xx=xx+1)
                    if(solid_pixel(xx,yy) && overlap_pixel(pose_x,pose_y,rotation,xx,yy,parts)) overlap_terrain=1;
        end
    endfunction
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk);end
    endtask
    task move;
        input integer old_x,old_y,new_x,new_y,input_vx,input_vy,rotation,expected_ground;
        input [8:0] parts;
        begin
            px=old_x;py=old_y;nx=new_x;ny=new_y;vx=input_vx;vy=input_vy;
            old_tilt=rotation;new_tilt=rotation;collision_mask=parts;map_level=1;
            width=scene==0 ? `LP_MAP_WIDTH : 192;height=scene==0 ? `LP_MAP_HEIGHT : 192;
            if(overlap_terrain(old_x,old_y,rotation,parts)) $fatal(1,"Occupied fixture%0d starts embedded",cases);
            if(!move_ready) $fatal(1,"Occupied checker unavailable");
            move_valid=1;clocks(1);move_valid=0;
            // Captured masks must not change when a new damage mask, pose or
            // level is presented while this ROM transaction is still running.
            collision_mask=~parts;px=0;py=0;nx=0;ny=0;vx=0;vy=0;old_tilt=0;new_tilt=0;
            map_level=0;width=1;height=1;
            waited=0;
            while(!response_valid && waited<1500000) begin clocks(1);waited=waited+1;end
            if(!response_valid) $fatal(1,"Occupied case%0d exceeded cycle budget",cases);
            if(waited>max_latency) max_latency=waited;
            if(overlap_terrain($signed(cx),$signed(cy),$signed(tilt),parts))
                $fatal(1,"Occupied case%0d penetrated terrain scene%0d pose(%0d,%0d) angle%0d mask%b",cases,scene,cx,cy,tilt,parts);
            if(grounded && (!overlap_terrain($signed(cx),$signed(cy)+1,$signed(tilt),parts) || cvy!==0))
                $fatal(1,"Occupied case%0d manufactured support in an empty cell",cases);
            if(expected_ground>=0 && grounded!==expected_ground[0])
                $fatal(1,"Occupied case%0d ground%b expected%0d",cases,grounded,expected_ground);
            if(tilt!==rotation[`LP_TILT_BITS-1:0]) $fatal(1,"Occupied case%0d changed unchanged angle",cases);
            held={cx,cy,cvx,cvy,tilt,grounded,slope};move_valid=1;collision_mask=9'h1ff;clocks(7);
            if(move_ready || !response_valid || {cx,cy,cvx,cvy,tilt,grounded,slope}!==held)
                $fatal(1,"Occupied response changed under backpressure");
            move_valid=0;response_ready=1;clocks(1);response_ready=0;
            if(!move_ready || response_valid) $fatal(1,"Occupied response did not release");
            cases=cases+1;
        end
    endtask

    initial begin
        clocks(3);reset=0;clocks(1);
        // The exact photographed valley: the retained green lip is real ground,
        // low enough for the 6-pixel grounded step-up, and the road still
        // supports the full hull past it.
        scene=0;
        move(201*256,93*256,202*256,93*256+32,256,32,0,1,9'h1ff);
        if(cx!==202*256 || cvx!==256 || !grounded) $fatal(1,"Retained green lip was not climbed onto the road");
        // This pose overlaps real roof only in the empty top construction row.
        if(!overlap_terrain(215*256,95*256,0,9'h1ff) || overlap_terrain(215*256,95*256,0,CAR))
            $fatal(1,"Photographed empty-roof fixture lost its geometry");
        move(215*256,95*256,216*256,95*256+32,256,32,0,1,CAR);
        if(cx!==216*256 || cvx!==256) $fatal(1,"Empty top row still stopped cave travel");

        scene=2;
        move(64*256,116*256,64*256,116*256+32,0,32,0,1,9'h1ff);
        if(cy!==116*256) $fatal(1,"Full-mask legacy floor contact changed");
        move(64*256,116*256,64*256,120*256,0,1024,0,0,9'd0);
        if(cy!==120*256 || cvy!==1024 || slope!==0) $fatal(1,"Empty build acquired a phantom floor");
        move(64*256,120*256,64*256,128*256,0,2048,0,1,CENTRE);
        if(cy!==124*256 || cvy!==0) $fatal(1,"Centre-only cell used the empty bottom row as support");
        for(angle=-4;angle<=4;angle=angle+1) begin
            move(64*256,120*256,64*256,126*256,0,1536,angle,1,CENTRE);
            if(cy>=126*256 || cvy!==0) $fatal(1,"Tilted occupied cell fell through floor");
        end
        // Rotated corner cells require the nonzero cell-centre translation on
        // both world axes; a centred cell alone cannot exercise its signs.
        for(angle=-4;angle<=4;angle=angle+8) begin
            for(corner=0;corner<9;corner=corner+2) if(corner!=4) begin
                move(64*256,100*256,64*256,140*256,0,10240,angle,1,9'b1<<corner);
                if(cy<=100*256 || cy>=140*256 || cvy!==0)
                    $fatal(1,"Tilted corner%0d angle%0d did not land on its occupied cell",corner,angle);
            end
        end
        scene=3;
        move(64*256,93*256,64*256,88*256,0,-1280,0,0,CENTRE);
        if(cy!==92*256 || cvy!==0) $fatal(1,"Occupied centre cell tunneled through real ceiling");
        scene=4;
        move(100*256,64*256,109*256,64*256,2304,0,0,0,CENTRE);
        if(cx!==104*256 || cvx!==0) $fatal(1,"Occupied centre cell tunneled through real wall");
        scene=1;
        move(64*256,64*256,65*256,65*256,256,256,0,0,CAR);
        if(cx!==65*256 || cy!==65*256) $fatal(1,"Open cave scenery blocked sparse build");
        $display("PASS occupied_map_collision_tb: %0d actual-valley, sparse SAT, occupied floor/ceiling/wall, empty-mask, capture and backpressure cases; max latency=%0d clocks",cases,max_latency);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"Occupied map collision test timed out");end
endmodule
