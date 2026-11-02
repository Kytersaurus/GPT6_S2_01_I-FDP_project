// Owner: Role 1 - Kaushal. Direction balance, damage/retry and side attachment edges.
`timescale 1ns / 1ps
`include "game_defs.vh"
module directional_parts_tb;
    reg clk=0,reset=1,init=0,edit=0,left=0,damage=0;
    reg [2:0] state=`LP_BUILD,part=0;
    reg [1:0] op=`LP_EDIT_PLACE;
    reg [3:0] cell_id=0,source=0;
    reg [8:0] mask=0;
    wire [26:0] grid;
    wire [8:0] frames,direction,intact;
    wire signed [4:0] balance, fan_balance, rocket_balance;
    wire [3:0] engines,rockets,fans;
    wire [2:0] feedback;
    always #5 clk=~clk;
    vehicle_builder #(.FRAME_LIMIT(9),.ENGINE_LIMIT(2)) dut(
        .clk(clk),.reset(reset),.game_state(state),.run_init(init),.init_ready(),
        .edit_valid(edit),.edit_op(op),.edit_cell(cell_id),.edit_source(source),.edit_part(part),.edit_facing_left(left),
        .damage_valid(damage),.damage_ready(),.damage_mask(mask),.damage_frame_mask(9'd0),
        .build_grid(grid),.build_frames(frames),.build_facing_left(direction),.engine_balance(balance),.fan_balance(fan_balance),.rocket_balance(rocket_balance),
        .intact_mask(intact),.frame_intact_mask(),.engine_count(engines),.rockets_left(rockets),.fans_left(fans),
        .feedback_code(feedback));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task put;input integer dest;input [2:0] kind;input face;
        begin cell_id=dest;part=kind;left=face;op=`LP_EDIT_PLACE;edit=1;clocks(1);edit=0;clocks(2);end
    endtask
    initial begin
        clocks(3);reset=0;clocks(2);
        put(2,`LP_PART_FRAME,0);put(3,`LP_PART_BOOSTER,0);
        if(grid[11:9]!=0 || rockets!=1) $fatal(1,"Rocket support wrapped across rows");
        put(3,`LP_PART_FAN,0);
        if(grid[11:9]!=0 || fans!=1) $fatal(1,"Fan support wrapped across rows");
        put(3,`LP_PART_FRAME,0);put(4,`LP_PART_FRAME,0);
        put(3,`LP_PART_ENGINE,1);put(4,`LP_PART_ENGINE,0);
        if(engines!=2 || balance!=0 || !direction[3] || direction[4]) $fatal(1,"Opposing engines failed to cancel");
        put(5,`LP_PART_BOOSTER,1);put(0,`LP_PART_BOOSTER,0);
        if(rockets!=0 || grid[2:0]!=0 || !direction[5]) $fatal(1,"Rocket stock/direction or unsupported placement failed");
        put(1,`LP_PART_FAN,0);
        if(fan_balance!=1 || rocket_balance!=-1) $fatal(1,"Air part directions incorrect");
        state=`LP_INIT_RUN;init=1;clocks(2);init=0;state=`LP_RUN;clocks(2);
        mask=9'b000010000;damage=1;clocks(1);damage=0;clocks(2);
        if(engines!=1 || balance!=-1 || !direction[3] || grid[14:12]!=`LP_PART_ENGINE)
            $fatal(1,"Damage changed saved direction or engine balance did not update");
        mask=9'b000100010;damage=1;clocks(1);damage=0;clocks(2);
        if(fan_balance!=0 || rocket_balance!=0) $fatal(1,"Destroyed air parts still produced thrust");
        state=`LP_INIT_RUN;init=1;clocks(2);init=0;state=`LP_RUN;clocks(2);
        if(fan_balance!=1 || rocket_balance!=-1) $fatal(1,"Retry did not restore air directions");
        if(engines!=2 || balance!=0 || !direction[3] || !direction[5]) $fatal(1,"Retry lost directional construction");
        state=`LP_BUILD;clocks(2);
        source=3;cell_id=6;part=`LP_PART_FRAME;op=`LP_EDIT_MOVE;edit=1;clocks(1);edit=0;clocks(2);
        if(!frames[3] || frames[6] || grid[11:9]!=`LP_PART_ENGINE) $fatal(1,"Direct filled-frame bundle move accepted");
        cell_id=3;op=`LP_EDIT_REMOVE;edit=1;clocks(1);edit=0;clocks(2);
        if(direction[3] || !frames[3] || grid[11:9]!=0) $fatal(1,"Removing contents did not clear only their direction");
        put(3,`LP_PART_PIG,1);
        if(direction[3]) $fatal(1,"Nondirectional part retained an engine direction");
        $display("PASS directional_parts_tb: no side wrap, stock, opposing engine balance, damage/retry, filled-frame rejection and direction cleanup");
        $finish;
    end
    initial begin #50000;$fatal(1,"Directional parts timed out");end
endmodule
