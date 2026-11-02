`timescale 1ns / 1ps
`include "game_defs.vh"
module cg_support_tb;
    reg clk=0,reset=1,request=0,ready=0;
    reg [2:0] scene=0;
    reg [26:0] grid=0;
    reg [8:0] frames=9'h1ff,parts=0;
    reg signed [19:0] px=80*256,py=80*256;
    reg signed [4:0] angle=0;
    wire signed [10:0] qx,qy;
    reg [2:0] map_class=0;
    wire valid,move_ready,grounded,unstable;
    wire signed [1:0] tip;
    wire signed [7:0] slope;
    wire signed [19:0] cx,cy;
    integer waited,cases=0;
    reg mutate=0;
    reg [63:0] held;
    always #5 clk=~clk;
    function solid;
        input integer x,y;
        begin
            case(scene)
                0:solid=y>=104;
                1:solid=y>=104 && x<90;
                2:solid=y>=104 && x<92;
                3:solid=y>=104 && x>=92;
                4:solid=y>=104 && (x<84 || x>=100);
                5:solid=y>=100+x-64;
                default:solid=0;
            endcase
        end
    endfunction
    always @(posedge clk) map_class<=solid($signed(qx),$signed(qy)) ? `LP_MAP_ROCK : `LP_MAP_CAVE;
    rotating_map_collision_engine dut(.clk(clk),.reset(reset),.move_valid(request),.move_ready(move_ready),
        .previous_x(px),.previous_y(py),.proposed_x(px),.proposed_y(py+20'sd32),
        .previous_tilt(5'sd0),.proposed_tilt(angle),.collision_mask(frames|parts),
        .cg_enabled(1'b1),.build_grid(grid),.part_intact_mask(parts),.frame_intact_mask(frames),
        .proposed_vx(16'sd0),.proposed_vy(16'sd32),.world_width(10'd192),.world_height(10'd192),
        .query_x(qx),.query_y(qy),.query_class(map_class),.response_valid(valid),.response_ready(ready),
        .corrected_x(cx),.corrected_y(cy),.corrected_vx(),.corrected_vy(),.corrected_tilt(),
        .grounded(grounded),.ground_slope(slope),.tip_dir(tip),.support_unstable(unstable));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task check;input signed [1:0] expected_tip;begin
        request=1;clocks(1);request=0;waited=0;
        if(mutate) begin grid=0;parts=0;end
        while(!valid && waited<100000) begin clocks(1);waited=waited+1;end
        if(!valid || !grounded || tip!==expected_tip || unstable!==(expected_tip!=0))
            $fatal(1,"CG case%0d scene%0d: valid%0b ground%0b tip%0d expected%0d COMsum%0d limits%0d,%0d slope%0d",cases,scene,valid,grounded,tip,expected_tip,dut.cg_sum,dut.left_support_sum,dut.right_support_sum,slope);
        held={cx,cy,slope,grounded,tip,unstable};clocks(3);
        if(!valid || {cx,cy,slope,grounded,tip,unstable}!==held) $fatal(1,"CG response changed under backpressure");
        ready=1;clocks(1);ready=0;clocks(1);cases=cases+1;
    end endtask
    initial begin
        clocks(3);reset=0;
        check(0);scene=1;check(1);
        // Same hull/contacts: moving the engine mass across COM changes stability.
        scene=2;check(0);grid[17:15]=`LP_PART_ENGINE;parts[5]=1;check(1);
        parts=0;check(0); // Destroyed engine contributes no weight.
        grid=0;grid[11:9]=`LP_PART_ENGINE;parts=9'b000001000;
        scene=3;check(-1);
        scene=4;check(0); // COM is over air, but two contacts safely bridge it.
        // Gravity sees the accepted world orientation, including quarter turns
        // and upside-down parts, not the unrotated grid column.
        scene=2;angle=-16;check(1);
        grid=0;grid[17:15]=`LP_PART_ENGINE;parts=9'b000100000;check(0);
        angle=8;check(0);
        grid=0;grid[5:3]=`LP_PART_ENGINE;parts=9'b000000010;check(1);
        angle=-8;check(0);
        angle=0;grid=0;parts=0;frames=9'b110110110;check(1);
        frames=9'b011011011;check(0);frames=9'h1ff;
        grid[17:15]=`LP_PART_ENGINE;parts=9'b000100000;mutate=1;check(1);mutate=0;check(0);
        // A nearby smooth slope must not veto an actual COM overhang.
        grid=0;parts=0;scene=5;px=64*256;py=76*256;angle=1;check(1);
        if(slope!=16) $fatal(1,"Slope fixture did not exercise old slope veto");
        // Reset cancels an incomplete COM/support calculation.
        request=1;clocks(1);request=0;clocks(8);reset=1;clocks(1);reset=0;clocks(2);
        if(valid || unstable) $fatal(1,"Reset retained support result");
        $display("PASS cg_support_tb: %0d mass-weighted ledges, damage, bridge, slope veto and response cases",cases);$finish;
    end
    initial begin #15000000;$fatal(1,"CG support timeout");end
endmodule
