`timescale 1ns / 1ps
`include "game_defs.vh"
// Real ROMs on independent draw/query map selections. A test-only copy of the
// map validates every occupied output pixel, independent of the collision FSM.
module map_rom_collision_tb;
    reg clk=0, reset=1, move_valid=0, response_ready=0, map_id=0;
    reg signed [19:0] px=0,py=0,nx=0,ny=0;
    reg signed [15:0] vx=0,vy=32;
    wire signed [10:0] qx,qy;
    wire query_solid;
    wire [2:0] query_class=query_solid ? `LP_MAP_ROCK : `LP_MAP_SKY;
    wire [2:0] draw_class;
    wire signed [19:0] cx,cy;
    wire signed [15:0] cvx,cvy;
    wire move_ready,response_valid,grounded;
    wire [9:0] width=map_id ? `LP_FLIGHT_WIDTH : `LP_MAP_WIDTH;
    wire [9:0] height=map_id ? `LP_FLIGHT_HEIGHT : `LP_MAP_HEIGHT;
    reg [2:0] arch[0:512*`LP_MAP_HEIGHT-1];
    reg [2:0] flight[0:1024*`LP_FLIGHT_HEIGHT-1];
    integer waited,xx,yy,left_pixel,right_pixel,top_pixel,bottom_pixel,support,steps;
    always #5 clk=~clk;
    initial begin
        $readmemh("cave_arch_map.mem",arch);
        $readmemh("cave_flight_map.mem",flight);
    end
    level_map rom (
        .map_id(!map_id), .draw_clk(clk), .draw_x(11'sd104), .draw_y(11'sd50), .draw_class(draw_class),
        .query_clk(clk), .query_map_id(map_id), .query_x(qx), .query_y(qy), .query_class(), .query_solid(query_solid)
    );
    collision_engine dut (
        .clk(clk), .reset(reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(vx), .proposed_vy(vy), .terrain_count(3'd0), .terrain_rects(128'd0),
        .map_level(1'b1), .world_width(width), .world_height(height),
        .query_x(qx), .query_y(qy), .query_class(query_class),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(cx), .corrected_y(cy), .corrected_vx(cvx), .corrected_vy(cvy), .grounded(grounded)
    );
    function is_solid;
        input integer x,y;
        reg [2:0] value;
        begin
            value=0;
            if (x>=0 && x<width && y>=0 && y<height)
                value=map_id ? flight[y*1024+x] : arch[y*512+x];
            is_solid=value>=2 && value<=5;
        end
    endfunction
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    task move;
        input integer dx,dy;
        begin
            nx=px+dx; ny=py+dy; vx=dx; vy=dy;
            move_valid=1; clocks(1); move_valid=0;
            waited=0;
            while (!response_valid && waited<30000) begin clocks(1); waited=waited+1; end
            if (!response_valid) $fatal(1,"Real map collision exceeded update budget");
            if(draw_class !== (map_id ? arch[50*512+104] : flight[50*1024+104]))
                $fatal(1,"Draw colour class changed while collision used the other map");
            left_pixel=$signed(cx) >>> 8; right_pixel=($signed(cx)+6143) >>> 8;
            top_pixel=$signed(cy) >>> 8; bottom_pixel=($signed(cy)+6143) >>> 8;
            for(yy=top_pixel; yy<=bottom_pixel; yy=yy+1)
                for(xx=left_pixel; xx<=right_pixel; xx=xx+1)
                    if(is_solid(xx,yy)) $fatal(1,"Vehicle penetrated map %0d at (%0d,%0d)",map_id,xx,yy);
            if(grounded) begin
                support=0;
                for(xx=left_pixel; xx<=right_pixel; xx=xx+1)
                    if(is_solid(xx,($signed(cy)+6144) >>> 8)) support=1;
                if(!support || cvy!=0) $fatal(1,"Grounded without real support");
            end
            px=cx; py=cy;
            response_ready=1; clocks(1); response_ready=0;
        end
    endtask
    initial begin
        clocks(3); reset=0; clocks(1);
        px=104*256; py=26*256;
        move(0,32);
        if(!grounded || cy!=26*256) $fatal(1,"Arch spawn floor was not read from ROM");
        for(steps=0;steps<12;steps=steps+1) move(256,32);
        for(steps=0;steps<12;steps=steps+1) move(-256,32);
        map_id=1; px=68*256; py=178*256;
        move(0,32);
        if(!grounded || cy!=178*256) $fatal(1,"Flight spawn floor was not read from independent query map");
        for(steps=0;steps<12;steps=steps+1) move(256,32);
        // Valid open pose near the real Flight flag; no fabricated platform.
        px=757*256; py=32*256; move(0,32);
        if(!grounded || cy!=32*256) $fatal(1,"Flight goal ledge missing");
        $display("PASS map_rom_collision_tb: real maps, full footprint, spawn terrain, ledge and independent map selection");
        $finish;
    end
    initial begin #15000000; $fatal(1,"Real map collision timed out"); end
endmodule
