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
    // Cave Arch's collision ROM is the traced terrain after build_cave_arch_map.ps1 opens
    // decorative grass and smooths floors (Classify.SmoothTerrain), and the colour map is
    // recoloured to match. So drawing and collision must agree: solid pixels are drawn as
    // rock/grass/road/underground; rock, road and underground are always solid; grass may
    // be open (decorative). Cave Flight keeps the exact class rule.
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
        // Allow primitive global reset to finish in post-synthesis simulation.
        repeat(20) @(negedge clk);
        for(m=0;m<2;m=m+1) begin
            map_id=m;
            for(yy=0;yy<(m ? `LP_FLIGHT_HEIGHT : `LP_MAP_HEIGHT);yy=yy+1)
                for(xx=0;xx<(m ? `LP_FLIGHT_WIDTH : `LP_MAP_WIDTH);xx=xx+1) begin
                    x=xx;y=yy;
                    expected_class=m ? flight[yy*1024+xx] : arch[yy*512+xx];
                    expected_solid=expected_class>=`LP_MAP_ROCK && expected_class<=`LP_MAP_DARK;
                    @(negedge clk);
                    if(m==0 && expected_class==`LP_MAP_GRASS) begin
                        // Grass is solid ground or open decoration.
                        if(solid!==1'b0 && solid!==1'b1)
                            $fatal(1,"Solidity unknown map0 (%0d,%0d)",xx,yy);
                        if(!solid) decor_checks=decor_checks+1;
                    end else if(solid!==expected_solid)
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
