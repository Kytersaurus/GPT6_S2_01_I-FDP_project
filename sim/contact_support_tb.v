// Owner: Role 3 - coherent ground, balance span and gradient validity.
`timescale 1ns / 1ps
`include "game_defs.vh"
module contact_support_tb #(parameter ROTATED=1);
    localparam [26:0] GRID={`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
        `LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,9'd0};
    localparam [8:0] PARTS=9'b101011000, FRAMES=9'b000111000;
    reg clk=0,reset=1,request=0,ready=0;
    reg [2:0] scene=0;
    wire move_ready,valid,grounded,unstable,slope_valid,span_valid;
    wire signed [19:0] cx,cy;
    wire signed [15:0] vx,vy;
    wire signed [4:0] tilt;
    wire signed [7:0] slope;
    wire signed [1:0] tip;
    wire signed [9:0] left_q2,right_q2,support_y_q2;
    wire signed [10:0] qx,qy;
    reg [2:0] map_class=0;
    integer waited,cases=0;
    reg [154:0] held;
    wire [3:0] contact_wheels;
    wire signed [9:0] left_y_q2,right_y_q2;
    always #5 clk=~clk;
    function solid;
        input integer x,y;
        integer floor_y;
        begin
            case(scene)
                0:floor_y=104;
                1:floor_y=x<92 ? 107 : x<96 ? 111 : 104;
                2:floor_y=x<92 ? 108 : x<96 ? 111 : 104;
                3:floor_y=(x<88 || x>=96) ? 104 : 150;
                5:floor_y=104+((x-80) >>> 2);
                6:floor_y=104+((103-x) >>> 2);
                default:floor_y=150;
            endcase
            solid=x>=0 && x<192 && y>=floor_y && y<192;
        end
    endfunction
    always @(posedge clk) map_class<=solid($signed(qx),$signed(qy)) ? `LP_MAP_ROCK : `LP_MAP_SKY;
    collision_engine #(.ROTATION_ONLY(ROTATED)) dut(
        .clk(clk),.reset(reset),.move_valid(request),.move_ready(move_ready),
        .previous_x(20'sd20480),.previous_y(20'sd20480),.proposed_x(20'sd20480),.proposed_y(20'sd20512),
        .proposed_vx(16'sd0),.proposed_vy(16'sd32),.terrain_count(3'd0),.terrain_rects(128'd0),.map_level(1'b1),
        .rotation_enabled(ROTATED!=0),.previous_tilt(5'sd0),.proposed_tilt(5'sd0),.collision_mask(PARTS|FRAMES),
        .cg_enabled(1'b1),.build_grid(GRID),.part_intact_mask(PARTS),.frame_intact_mask(FRAMES),
        .world_width(10'd192),.world_height(10'd192),.query_x(qx),.query_y(qy),.query_class(map_class),
        .response_valid(valid),.response_ready(ready),.corrected_x(cx),.corrected_y(cy),
        .corrected_vx(vx),.corrected_vy(vy),.corrected_tilt(tilt),.grounded(grounded),.ground_slope(slope),
        .ground_slope_valid(slope_valid),.support_span_valid(span_valid),.support_wheel_count(contact_wheels),.support_left_q2(left_q2),.support_right_q2(right_q2),.support_y_q2(support_y_q2),.support_left_y_q2(left_y_q2),.support_right_y_q2(right_y_q2),
        .tip_dir(tip),.support_unstable(unstable));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task check;
        input integer expected_ground,expected_gradient,expected_tip,expected_left,expected_right;
        begin
            if(!move_ready) $fatal(1,"Contact request unavailable");
            request=1;clocks(1);request=0;waited=0;
            while(!valid && waited<200000) begin clocks(1);waited=waited+1;end
            if(!valid || grounded!==expected_ground[0] || slope_valid!==expected_gradient[0])
                $fatal(1,"Contact case%0d scene%0d ground%0b gradient%0b slope%0d",cases,scene,grounded,slope_valid,slope);
            if(expected_ground && ROTATED && support_y_q2!==10'sd48) $fatal(1,"Contact height does not match actual floor");
            if(ROTATED && contact_wheels!==(expected_ground ? ((scene==2 || scene==5 || scene==6) ? 4'd1 : 4'd2) : 4'd0))
                $fatal(1,"Contacting wheel count wrong: scene%0d wheels%0d",scene,contact_wheels);
            if(ROTATED && expected_ground) begin
                if(scene==1 && (left_y_q2!=60 || right_y_q2!=48)) $fatal(1,"Rough-floor endpoint heights wrong");
                if(scene==5 && (slope!=4 || left_y_q2!=48 || right_y_q2!=52)) $fatal(1,"Positive ramp endpoints wrong");
                if(scene==6 && (slope!=-4 || left_y_q2!=52 || right_y_q2!=48)) $fatal(1,"Negative ramp endpoints wrong");
            end
            if(vx!==0 || tilt!==0) $fatal(1,"Contact query introduced motion");
            if(ROTATED) begin
                if(span_valid!==expected_ground[0] || tip!==expected_tip[1:0] || unstable!==(expected_tip!=0) ||
                   left_q2!==expected_left || right_q2!==expected_right)
                    $fatal(1,"Contact case%0d scene%0d span%0b tip%0d bounds%0d,%0d",cases,scene,span_valid,tip,left_q2,right_q2);
            end else if(span_valid || left_q2!=0 || right_q2!=0 || support_y_q2!=0 || unstable || tip!=0)
                $fatal(1,"Upright reference invented an occupied-cell support span");
            held={cx,cy,vx,vy,tilt,grounded,slope,slope_valid,span_valid,contact_wheels,left_q2,right_q2,support_y_q2,left_y_q2,right_y_q2,tip,unstable};clocks(4);
            if(!valid || {cx,cy,vx,vy,tilt,grounded,slope,slope_valid,span_valid,contact_wheels,left_q2,right_q2,support_y_q2,left_y_q2,right_y_q2,tip,unstable}!==held)
                $fatal(1,"Contact metadata changed under backpressure");
            ready=1;clocks(1);ready=0;clocks(1);cases=cases+1;
        end
    endtask
    initial begin
        clocks(3);reset=0;clocks(1);
        check(1,1,0,-52,52);
        if(ROTATED) begin
            scene=1;check(1,0,0,-52,52); // Three-pixel roughness can share load.
            scene=2;check(1,0,-1,12,52); // Four-pixel gap remains outside contact slop.
            scene=3;check(1,1,0,-52,52); // A bridge supports COM above open air.
            scene=5;check(1,1,1,-52,-12); // Endpoints retain matching ramp heights.
            scene=6;check(1,1,-1,12,52);
        end
        scene=4;check(0,0,0,0,0); // Near-contact tolerance cannot ground free flight.
        request=1;clocks(1);request=0;clocks(8);reset=1;clocks(1);reset=0;clocks(2);
        if(valid || grounded || slope_valid || span_valid || left_q2!=0 || right_q2!=0 || support_y_q2!=0 || unstable)
            $fatal(1,"Contact reset retained metadata");
        $display("PASS contact_support_tb: ROTATED=%0d %0d valid flat/unknown slopes, bounded contact slop, true ledge, bridge, air and backpressure cases",ROTATED,cases);$finish;
    end
    initial begin #20000000;$fatal(1,"Contact support timeout");end
endmodule
