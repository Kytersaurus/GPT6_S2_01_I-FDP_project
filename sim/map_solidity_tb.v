`timescale 1ns / 1ps
`include "game_defs.vh"
// Exhaustive asset contract; also run against synthesized ROMs. This catches
// synthesis-only initialization errors that movement RTL simulations miss.
module map_solidity_tb;
    reg clk=0, map_id=0;
    reg signed [10:0] x=0,y=0;
    wire solid;
    wire [2:0] drawn_class, queried_class;
    reg [2:0] arch[0:512*`LP_MAP_HEIGHT-1];
    reg [2:0] flight[0:1024*`LP_FLIGHT_HEIGHT-1];
    integer m,xx,yy,checks=0,cave_checks=0,ground_checks=0,decor_checks=0,old_errors=0,old_cave_errors=0,old_flight_floor_errors=0;
    reg [2:0] expected_class;
    reg expected_solid;
    always #5 clk=~clk;
    // Cave Arch decorative grass, an independent copy of the rule in
    // scripts/build_cave_arch_map.ps1. Open GRASS is either in an 8-connected patch that
    // touches no rock/road/underground (floating), or in a vertical run taller than 5
    // above its bottom 2 pixels (all of it when the run hangs over open space), with no
    // ground within 2 pixels to the left or right.
    localparam integer ARCH_CELLS = 512*`LP_MAP_HEIGHT;
    reg arch_decor[0:ARCH_CELLS-1];
    integer arch_patch[0:ARCH_CELLS-1];
    reg patch_grounded[0:ARCH_CELLS-1];
    integer flood[0:ARCH_CELLS-1];
    integer i,p,head,tail,patches,nx,ny,dx,dy,top,bottom,keep,g;
    reg beside;
    function arch_ground;
        input integer px, py;
        begin
            arch_ground = px>=0 && px<`LP_MAP_WIDTH && py>=0 && py<`LP_MAP_HEIGHT &&
                (arch[py*512+px]==`LP_MAP_ROCK || arch[py*512+px]==`LP_MAP_ROAD || arch[py*512+px]==`LP_MAP_DARK);
        end
    endfunction
    task find_arch_decor;
        begin
            patches=0;
            for(i=0;i<ARCH_CELLS;i=i+1) begin arch_decor[i]=0; arch_patch[i]=-1; end
            for(i=0;i<ARCH_CELLS;i=i+1)
                if(i%512<`LP_MAP_WIDTH && arch[i]==`LP_MAP_GRASS && arch_patch[i]<0) begin
                    patch_grounded[patches]=0; arch_patch[i]=patches; head=0; tail=1; flood[0]=i;
                    while(head<tail) begin
                        p=flood[head]; head=head+1;
                        for(dy=-1;dy<=1;dy=dy+1) for(dx=-1;dx<=1;dx=dx+1) begin
                            nx=p%512+dx; ny=p/512+dy;
                            if(arch_ground(nx,ny)) patch_grounded[patches]=1;
                            else if(nx>=0 && nx<`LP_MAP_WIDTH && ny>=0 && ny<`LP_MAP_HEIGHT &&
                                    arch[ny*512+nx]==`LP_MAP_GRASS && arch_patch[ny*512+nx]<0) begin
                                arch_patch[ny*512+nx]=patches; flood[tail]=ny*512+nx; tail=tail+1;
                            end
                        end
                    end
                    patches=patches+1;
                end
            for(xx=0;xx<`LP_MAP_WIDTH;xx=xx+1) begin
                yy=0;
                while(yy<`LP_MAP_HEIGHT) begin
                    if(arch[yy*512+xx]!=`LP_MAP_GRASS) yy=yy+1;
                    else begin
                        top=yy;
                        while(yy<`LP_MAP_HEIGHT && arch[yy*512+xx]==`LP_MAP_GRASS) yy=yy+1;
                        bottom=yy;
                        if(!patch_grounded[arch_patch[top*512+xx]])
                            for(g=top;g<bottom;g=g+1) arch_decor[g*512+xx]=1;
                        else if(bottom-top>5) begin
                            keep=(bottom<`LP_MAP_HEIGHT && !arch_ground(xx,bottom)) ? 0 : 2;
                            for(g=top;g<bottom-keep;g=g+1) begin
                                beside=arch_ground(xx-2,g) || arch_ground(xx-1,g) || arch_ground(xx+1,g) || arch_ground(xx+2,g);
                                if(!beside) arch_decor[g*512+xx]=1;
                            end
                        end
                    end
                end
            end
        end
    endtask
`ifdef POST_SYNTHESIS
    map_mask_fixed dut(.clk(clk),.map_id(map_id),.x(x),.y(y),.solid(solid),.draw_class(drawn_class));
`ifdef COMPARE_OLD_ROM
    wire old_solid;
    map_mask_old old_dut(.clk(clk),.map_id(map_id),.x(x),.y(y),.solid(old_solid));
`endif
`else
    level_map #(.ARCH_SCALED(0)) dut(.map_id(map_id),.draw_clk(clk),.draw_x(x),.draw_y(y),.draw_class(drawn_class),
        .query_clk(clk),.query_map_id(map_id),.query_x(x),.query_y(y),.query_class(queried_class),.query_solid(solid));
`endif
    initial begin
        $readmemh("cave_arch_map.mem",arch);
        $readmemh("cave_flight_map.mem",flight);
        find_arch_decor;
        // Allow primitive global reset to finish in post-synthesis simulation.
        repeat(20) @(negedge clk);
        for(m=0;m<2;m=m+1) begin
            map_id=m;
            for(yy=0;yy<(m ? `LP_FLIGHT_HEIGHT : `LP_MAP_HEIGHT);yy=yy+1)
                for(xx=0;xx<(m ? `LP_FLIGHT_WIDTH : `LP_MAP_WIDTH);xx=xx+1) begin
                    x=xx;y=yy;
                    expected_class=m ? flight[yy*1024+xx] : arch[yy*512+xx];
                    expected_solid=expected_class>=`LP_MAP_ROCK && expected_class<=`LP_MAP_DARK &&
                                   !(m==0 && arch_decor[yy*512+xx]);
                    if(m==0 && arch_decor[yy*512+xx]) decor_checks=decor_checks+1;
                    @(negedge clk);
                    if(solid!==expected_solid)
                        $fatal(1,"Solidity mismatch map%0d (%0d,%0d) class%0d got%b expected%b",m,xx,yy,expected_class,solid,expected_solid);
                    if(drawn_class!==expected_class)
                        $fatal(1,"Draw colour mismatch map%0d (%0d,%0d) got%0d expected%0d",m,xx,yy,drawn_class,expected_class);
`ifndef POST_SYNTHESIS
                    if(queried_class!==expected_class)
                        $fatal(1,"Query colour mismatch map%0d (%0d,%0d) got%0d expected%0d",m,xx,yy,queried_class,expected_class);
`endif
`ifdef COMPARE_OLD_ROM
                    if(old_solid!==expected_solid) begin
                        old_errors=old_errors+1;
                        if(expected_class==`LP_MAP_CAVE) old_cave_errors=old_cave_errors+1;
                        if(m==1 && expected_solid) old_flight_floor_errors=old_flight_floor_errors+1;
                    end
`endif
                    checks=checks+1;
                    if(expected_class==`LP_MAP_CAVE) cave_checks=cave_checks+1;
                    if(expected_class==`LP_MAP_GRASS) ground_checks=ground_checks+1;
                end
        end
        if(cave_checks==0 || ground_checks==0) $fatal(1,"Missing background/floor coverage");
        // Only scenery is opened: most Cave Arch grass must stay solid ground.
        if(decor_checks==0 || decor_checks*2>ground_checks) $fatal(1,"Unexpected decorative grass count %0d",decor_checks);
`ifdef COMPARE_OLD_ROM
        if(old_errors==0) $fatal(1,"Old synthesized-ROM defect was not reproduced");
        $display("Old synthesized ROM mismatches: %0d; blocked cave-background pixels: %0d; missing Flight terrain pixels: %0d",old_errors,old_cave_errors,old_flight_floor_errors);
`endif
        $display("PASS map_solidity_tb: %0d colour/solidity pixels, %0d open cave pixels, %0d grass pixels (%0d decorative, open)",checks,cave_checks,ground_checks,decor_checks);
        $finish;
    end
    initial begin #10000000; $fatal(1,"Solidity test timed out"); end
endmodule
