`timescale 1ns / 1ps
`include "game_defs.vh"
module physics_moments_tb;
    reg clk=0,reset=1,init=0,step=0,release_step=0;
    reg [2:0] state=`LP_BUILD;
    reg [26:0] grid=0;
    reg [8:0] frames=0,alive=0,frame_alive=0,facing=0,vertical=0;
    reg [7:0] mass=6;
    reg signed [4:0] fans=1,rockets=0,vrockets=0;
    reg [3:0] wheel_count=0,engine_count=0,rocket_count=0;
    reg fan=1,engine=0,fire=0,contact=0,accept_move=0,response=0,block_turn=0,boost=0;
    reg [3:0] down=0,up=0;
    wire valid,ready,committed;
    wire signed [19:0] nx,ny,x,y;
    wire signed [15:0] vx,vy;
    wire signed [4:0] nt,tilt;
    integer waited,i,start_comx,start_comy,end_comx,end_comy,peak_wait=0;
    reg signed [13:0] held_spin;
    `include "rotation_geometry.vh"
    always #5 clk=~clk;
    physics_engine #(.ENGINE_FORCE(320)) dut(.clk(clk),.reset(reset),.run_init(init),.game_state(state),
        .spawn_x(20'sd8192),.spawn_y(20'sd8192),.step_start(step),.update_release(release_step),
        .wheel_count(wheel_count),.wheels_down(down),.wheels_up(up),.engine_count(engine_count),
        .balloon_count(4'd0),.mass_units(mass),.engine_enabled(engine),.engine_reverse(1'b0),
        .jump_press(1'b0),.boost_req(boost),.moments_enabled(1'b1),
        .build_grid(grid),.build_frames(frames),.intact_mask(alive),.frame_intact_mask(frame_alive),
        .build_facing_left(facing),.rocket_vertical_mask(vertical),
        .fan_balance(fans),.rocket_balance(rockets),.rocket_vertical_balance(vrockets),
        .rocket_count(rocket_count),.fan_enabled(fan),.rocket_req(fire),
        .move_valid(valid),.move_ready(accept_move),.proposed_x(nx),.proposed_y(ny),
        .proposed_vx(vx),.proposed_vy(vy),.proposed_tilt(nt),.vehicle_tilt(tilt),
        .response_valid(response),.response_ready(ready),.corrected_x(nx),.corrected_y(ny),
        .corrected_vx(vx),.corrected_vy(contact ? 16'sd0 : vy),.grounded(contact),.ground_slope(8'sd0),
        .corrected_tilt(block_turn ? 5'sd0 : nt),.tip_dir(2'sd0),
        .movement_committed(committed),.vehicle_x(x),.vehicle_y(y));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task put;input integer cell_id;input [2:0] kind;begin grid[cell_id*3 +: 3]=kind;alive[cell_id]=1;end endtask
    task empty;begin
        grid=0;frames=0;alive=0;frame_alive=0;facing=0;vertical=0;fans=0;rockets=0;vrockets=0;
        wheel_count=0;engine_count=0;rocket_count=0;fan=0;engine=0;fire=0;contact=0;block_turn=0;boost=0;down=0;up=0;
        frames[4]=1;frame_alive[4]=1;put(4,`LP_PART_PIG);
    end endtask
    task restart;begin state=`LP_INIT_RUN;init=1;clocks(2);init=0;state=`LP_RUN;clocks(1);end endtask
    task begin_step;begin
        step=1;clocks(1);step=0;waited=0;
        while(!valid && waited<2000) begin clocks(1);waited=waited+1;end
        if(!valid) $fatal(1,"Moment physics request timeout");
        if(waited>peak_wait) peak_wait=waited;
        // Rotation may shift the grid origin, but not add spurious COM motion.
        start_comx=x+((rotation_cos(tilt)*dut.u_moments.com_x_q2-rotation_sin(tilt)*dut.u_moments.com_y_q2) >>> 2);
        start_comy=y+((rotation_sin(tilt)*dut.u_moments.com_x_q2+rotation_cos(tilt)*dut.u_moments.com_y_q2) >>> 2);
        end_comx=nx+((rotation_cos(nt)*dut.u_moments.com_x_q2-rotation_sin(nt)*dut.u_moments.com_y_q2) >>> 2);
        end_comy=ny+((rotation_sin(nt)*dut.u_moments.com_x_q2+rotation_cos(nt)*dut.u_moments.com_y_q2) >>> 2);
        if(end_comx-start_comx-vx>1 || end_comx-start_comx-vx< -1 ||
           end_comy-start_comy-vy>1 || end_comy-start_comy-vy< -1)
            $fatal(1,"Spin introduced COM translation: %0d %0d",end_comx-start_comx-vx,end_comy-start_comy-vy);
    end endtask
    task finish;begin
        accept_move=1;clocks(1);accept_move=0;response=1;clocks(1);response=0;
        if(!committed) $fatal(1,"Moment update did not commit");
        release_step=1;clocks(1);release_step=0;
    end endtask
    task update;begin begin_step();finish();end endtask
    initial begin
        clocks(3);reset=0;
        empty();put(1,`LP_PART_FAN);fans=1;fan=1;mass=6;restart();
        for(i=0;i<30;i=i+1) update();
        if(tilt>=0 || dut.angular_velocity_q8>=0) $fatal(1,"Offset fan did not spin body");
        fan=0;held_spin=dut.angular_velocity_q8;
        for(i=0;i<12;i=i+1) update();
        if(dut.angular_velocity_q8!=held_spin) $fatal(1,"Airborne angular momentum did not persist");
        // A pure couple rotates while horizontal COM velocity remains zero.
        empty();put(1,`LP_PART_FAN);put(7,`LP_PART_FAN);facing[7]=1;fan=1;fans=0;mass=8;restart();
        for(i=0;i<24;i=i+1) update();
        if(tilt>=0 || vx!=0) $fatal(1,"Force couple lost spin or gained net translation");
        empty();put(1,`LP_PART_FAN);put(7,`LP_PART_FAN);fan=1;fans=2;mass=8;restart();
        for(i=0;i<24;i=i+1) update();
        if(tilt!=0 || dut.angular_velocity_q8!=0 || vx>=0) $fatal(1,"Balanced fans created spin");
        // Upward thrust on the left produces a clockwise moment.
        empty();put(3,`LP_PART_BOOSTER);vertical[3]=1;vrockets=-1;rocket_count=1;mass=6;restart();
        fire=1;clocks(1);fire=0;
        for(i=0;i<12;i=i+1) update();
        if(tilt<=0 || vy>=0) $fatal(1,"Vertical rocket did not lift and rotate");
        for(i=0;i<78;i=i+1) update();
        held_spin=dut.angular_velocity_q8;update();
        if(dut.u_moments.torque_q10!=0 || dut.angular_velocity_q8!=held_spin)
            $fatal(1,"Expended rocket kept adding angular acceleration");
        // The engine drives only grounded wheels; a blocked terrain turn kills spin.
        empty();frames[3]=1;frame_alive[3]=1;put(3,`LP_PART_ENGINE);put(7,`LP_PART_WHEEL);
        mass=10;wheel_count=1;engine_count=1;engine=1;restart();
        update();if(vx!=0 || dut.u_moments.torque_q10!=0) $fatal(1,"Airborne wheel drove body");
        contact=1;update();block_turn=1;
        i=0;
        begin_step();
        while(nt==0 && i<40) begin finish();begin_step();i=i+1;end
        if(nt==0 || vx<=0) $fatal(1,"Wheel drive did not create traction moment");
        finish();
        if(tilt!=0 || dut.angular_velocity_q8!=0) $fatal(1,"Blocked turn retained spin");
        // Ordinary drive is held by normal reactions; boost can exceed them.
        empty();frames=9'b000111000;frame_alive=frames;put(3,`LP_PART_ENGINE);
        put(0,`LP_PART_WHEEL);put(2,`LP_PART_WHEEL);put(6,`LP_PART_WHEEL);put(8,`LP_PART_WHEEL);
        mass=15;wheel_count=4;down=2;up=2;engine_count=1;engine=1;restart();
        update();contact=1;update();for(i=0;i<24;i=i+1) update();
        if(tilt!=0 || dut.angular_velocity_q8!=0 || vx<=0) $fatal(1,"Supported cart tipped under ordinary drive");
        boost=1;clocks(1);boost=0;clocks(1);
        for(i=0;i<16;i=i+1) update();
        if(dut.angular_velocity_q8>=0) $fatal(1,"Excess drive torque could not overcome normal reaction");
        step=1;clocks(1);step=0;clocks(4);restart();
        if(tilt!=0 || x!=8192 || y!=8192 || dut.angular_velocity_q8!=0 || valid)
            $fatal(1,"Retry retained moment calculation or spin");
        $display("PASS physics_moments_tb: off-centre spin, angular momentum, force couples, balanced thrust, vertical rockets, wheel traction, COM trajectory, blocked turns and retry; max latency=%0d clocks",peak_wait);
        $finish;
    end
    initial begin #3000000;$fatal(1,"Physics moments timeout");end
endmodule
