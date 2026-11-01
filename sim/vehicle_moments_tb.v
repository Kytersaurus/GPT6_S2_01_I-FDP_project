`timescale 1ns / 1ps
`include "game_defs.vh"
module vehicle_moments_tb;
    reg clk=0,reset=1,start=0,fan=0,rocket=0,grounded=0,force_valid=1;
    reg [26:0] grid=0;
    reg [8:0] frames=0,alive=0,frame_alive=0,facing=0,vertical=0;
    reg signed [4:0] tilt=0,next_tilt=0;
    reg signed [15:0] wheel_force=0;
    reg contact_valid=0;
    reg signed [9:0] contact_left=0,contact_right=0,contact_y=0;
    reg endpoint_y_valid=0,terrain_slope_valid=0;
    reg signed [9:0] contact_left_y=0,contact_right_y=0;
    reg signed [7:0] terrain_slope=0;
    reg pivot_contact=0;
    reg signed [1:0] pivot_direction=0;
    reg accept_result=0,pivot_start=0,pivot_ready=0;
    wire valid,pivot_valid;
    wire signed [15:0] accel;
    wire signed [15:0] gravity_tilt;
    wire normal_unstable;
    wire signed [6:0] comx,comy;
    wire signed [13:0] pdx,pdy;
    wire signed [23:0] torque;
    wire [7:0] mass;
    wire [15:0] support_neg,support_pos;
    integer waited,tests=0,angle,forward_x,forward_y,reference_torque,reference_accel,reference_pivot_x,reference_pivot_y;
    integer reference_support_neg,reference_support_pos,reference_gravity;
    reg signed [15:0] held_accel;
    always #5 clk=~clk;
    vehicle_moments dut(.clk(clk),.reset(reset),.start(start),.build_grid(grid),.build_frames(frames),
        .intact_mask(alive),.frame_intact_mask(frame_alive),.facing_left(facing),.rocket_vertical_mask(vertical),
        .fan_on(fan),.rocket_on(rocket),.grounded(grounded),.tilt(tilt),
        .contact_span_valid(contact_valid),.contact_left_q2(contact_left),.contact_right_q2(contact_right),.contact_y_q2(contact_y),
        .contact_endpoint_y_valid(endpoint_y_valid),.contact_left_y_q2(contact_left_y),.contact_right_y_q2(contact_right_y),
        .ground_slope(terrain_slope),.ground_slope_valid(terrain_slope_valid),
        .wheel_force_valid(force_valid),.wheel_force(wheel_force),.result_valid(valid),.result_ready(accept_result),
        .angular_accel_q8(accel),.gravity_tilt_q8(gravity_tilt),.grounded_support_unstable(normal_unstable),.support_negative_q8(support_neg),.support_positive_q8(support_pos),.com_x_q2(comx),.com_y_q2(comy),.body_mass(mass),.torque_q10(torque),
        .pivot_start(pivot_start),.next_tilt(next_tilt),.pivot_about_contact(pivot_contact),.pivot_direction(pivot_direction),.pivot_valid(pivot_valid),.pivot_ready(pivot_ready),
        .pivot_dx(pdx),.pivot_dy(pdy));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task empty;begin
        grid=0;frames=0;alive=0;frame_alive=0;facing=0;vertical=0;
        tilt=0;next_tilt=0;fan=0;rocket=0;grounded=0;wheel_force=0;force_valid=1;
        contact_valid=0;contact_left=0;contact_right=0;contact_y=0;pivot_contact=0;pivot_direction=0;
        endpoint_y_valid=0;terrain_slope_valid=0;contact_left_y=0;contact_right_y=0;terrain_slope=0;
    end endtask
    task put;input integer cell_id;input [2:0] kind;begin
        grid[cell_id*3 +: 3]=kind;alive[cell_id]=1;
    end endtask
    task centre;begin empty();frames[4]=1;frame_alive[4]=1;put(4,`LP_PART_PIG);end endtask
    task begin_calc;begin start=1;clocks(1);start=0;end endtask
    task wait_calc;begin
        waited=0;while(!valid && waited<1500) begin clocks(1);waited=waited+1;end
        if(!valid) $fatal(1,"Moment calculation timeout");tests=tests+1;
    end endtask
    task finish;begin
        accept_result=1;clocks(1);accept_result=0;pivot_start=1;clocks(1);pivot_start=0;
        waited=0;while(!pivot_valid && waited<200) begin clocks(1);waited=waited+1;end
        if(!pivot_valid) $fatal(1,"COM pivot correction timeout");
        pivot_ready=1;clocks(1);pivot_ready=0;
    end endtask
    initial begin
        clocks(3);reset=0;
        centre();put(1,`LP_PART_FAN);fan=1;begin_calc();wait_calc();
        if(mass!=6 || comx!=0 || comy!=-10 || torque!=-1408 || accel!=-29)
            $fatal(1,"Offset fan mass/COM/torque wrong: %0d (%0d,%0d) %0d %0d",mass,comx,comy,torque,accel);
        held_accel=accel;clocks(5);if(!valid || accel!=held_accel) $fatal(1,"Stalled moment changed");
        next_tilt=8;finish();
        // COM offset (0,-2.5 px) rotates to (+2.5,0) at 90 degrees.
        if(pdx!=-640 || pdy!=-640) $fatal(1,"COM-preserving origin correction wrong: %0d,%0d",pdx,pdy);
        centre();put(7,`LP_PART_FAN);fan=1;begin_calc();wait_calc();
        if(torque!=1408 || accel!=29) $fatal(1,"Mirrored fan arm did not reverse moment");finish();
        centre();put(3,`LP_PART_FAN);fan=1;begin_calc();wait_calc();
        if(torque!=0 || accel!=0) $fatal(1,"Force through COM created torque");finish();
        centre();put(1,`LP_PART_FAN);put(7,`LP_PART_FAN);fan=1;facing[7]=1;
        begin_calc();wait_calc();if(comy!=0 || torque!=-4096 || accel!=-64)
            $fatal(1,"Pure couple incorrectly cancelled with net force");finish();
        centre();put(3,`LP_PART_BOOSTER);vertical[3]=1;rocket=1;
        begin_calc();wait_calc();if(torque!=11264 || accel!=234) $fatal(1,"Vertical left rocket moment wrong");finish();
        centre();put(5,`LP_PART_BOOSTER);vertical[5]=1;rocket=1;
        begin_calc();wait_calc();if(torque!=-11264 || accel!=-234) $fatal(1,"Vertical right rocket moment wrong");finish();
        centre();put(3,`LP_PART_BOOSTER);put(5,`LP_PART_BOOSTER);vertical=9'b000101000;rocket=1;
        begin_calc();wait_calc();if(torque!=0 || accel!=0) $fatal(1,"Symmetric rocket moments did not cancel");finish();
        centre();put(1,`LP_PART_BOOSTER);rocket=1;tilt=-8;next_tilt=-8;
        begin_calc();wait_calc();if(torque!=11264 || accel!=234)
            $fatal(1,"Rotating attached horizontal rocket changed its local moment");finish();
        // Drive acts at the wheel, irrespective of which side contains the engine.
        centre();frames[3]=1;frame_alive[3]=1;put(3,`LP_PART_ENGINE);put(7,`LP_PART_WHEEL);
        grounded=1;wheel_force=96;begin_calc();wait_calc();
        if(mass!=10 || comy!=3 || torque!=0 || accel!=0) $fatal(1,"Wheel contact force wrong");finish();
        centre();frames[5]=1;frame_alive[5]=1;put(5,`LP_PART_ENGINE);put(7,`LP_PART_WHEEL);
        grounded=1;wheel_force=96;begin_calc();wait_calc();
        if(torque!=0 || accel!=0) $fatal(1,"Engine position moved traction force off wheels");finish();
        grounded=0;begin_calc();wait_calc();if(torque!=0) $fatal(1,"Airborne wheel created traction");finish();
        centre();put(7,`LP_PART_WHEEL);grounded=1;wheel_force=96;tilt=8;next_tilt=8;
        begin_calc();wait_calc();if(torque!=0) $fatal(1,"Moment arm did not rotate with body");finish();
        centre();put(1,`LP_PART_FAN);fan=1;begin_calc();
        // Snapshot survives live damage and direction changes while busy.
        alive=0;facing=9'h1ff;wait_calc();if(torque!=-1408) $fatal(1,"Live changes corrupted moment snapshot");finish();
        centre();put(1,`LP_PART_FAN);fan=1;alive[1]=0;begin_calc();wait_calc();
        if(mass!=4 || comx!=0 || comy!=0 || torque!=0) $fatal(1,"Destroyed actuator retained mass or torque");finish();
        centre();put(1,`LP_PART_FAN);put(7,`LP_PART_FAN);fan=1;facing[7]=1;
        frames[3]=1;frames[5]=1;frame_alive=frames;
        begin_calc();wait_calc();if(mass!=12 || torque!=-4096 || accel!=-42)
            $fatal(1,"Greater mass did not reduce angular acceleration");finish();
        centre();frames=9'b000111000;frame_alive=frames;
        put(6,`LP_PART_WHEEL);put(7,`LP_PART_WHEEL);put(8,`LP_PART_WHEEL);grounded=1;wheel_force=95;
        begin_calc();wait_calc();if(mass!=11 || comy!=8 || torque!=0 || accel!=0)
            $fatal(1,"Wheel force sharing lost integer remainder");finish();
        wheel_force=-95;begin_calc();wait_calc();if(torque!=0 || accel!=0)
            $fatal(1,"Reverse wheel force sharing lost sign");finish();
        centre();frames=9'b000111000;frame_alive=frames;
        put(3,`LP_PART_ENGINE);put(0,`LP_PART_WHEEL);put(2,`LP_PART_WHEEL);
        put(6,`LP_PART_WHEEL);put(8,`LP_PART_WHEEL);grounded=1;wheel_force=300;
        begin_calc();wait_calc();
        if(mass!=15 || accel!=0 || support_neg!=168 || support_pos!=216)
            $fatal(1,"Wheel normal reaction capacity wrong: %0d %0d %0d",accel,support_neg,support_pos);finish();
        wheel_force=0;begin_calc();wait_calc();
        if(accel!=0 || support_neg!=168 || support_pos!=216)
            $fatal(1,"Passive wheels lost normal reaction support");finish();
        put(1,`LP_PART_BALLOON);wheel_force=300;begin_calc();wait_calc();
        if(mass!=16 || support_neg!=42 || support_pos!=54)
            $fatal(1,"Balloon did not reduce normal reaction capacity");finish();
        centre();frames=9'b000111000;frame_alive=frames;put(3,`LP_PART_ENGINE);
        put(6,`LP_PART_WHEEL);put(8,`LP_PART_WHEEL);put(0,`LP_PART_BALLOON);put(1,`LP_PART_BALLOON);
        grounded=1;wheel_force=300;begin_calc();wait_calc();
        if(support_neg!=0 || support_pos!=0) $fatal(1,"Net upward lift retained ground normal reaction");finish();
        // Actual contacts support bare frames, not just inferred wheel rows.
        centre();grounded=1;contact_valid=1;contact_left=-16;contact_right=20;
        begin_calc();wait_calc();
        if(support_neg!=64 || support_pos!=80 || gravity_tilt!=0)
            $fatal(1,"Actual frame support did not balance COM");finish();
        contact_left=-20;contact_right=16;begin_calc();wait_calc();
        if(support_neg!=80 || support_pos!=64 || gravity_tilt!=0)
            $fatal(1,"Mirrored actual support did not mirror capacities");finish();
        // Once COM leaves the span, gravity supplies angular acceleration only.
        contact_left=-20;contact_right=-8;begin_calc();wait_calc();
        if(support_neg!=0 || support_pos!=0 || gravity_tilt!=48)
            $fatal(1,"Left contact did not turn right overhang clockwise");finish();
        contact_left=8;contact_right=20;begin_calc();wait_calc();
        if(gravity_tilt!=-48) $fatal(1,"Right contact did not mirror gravity tilt");finish();
        put(1,`LP_PART_BALLOON);contact_left=-20;contact_right=-8;
        begin_calc();wait_calc();if(gravity_tilt!=12) $fatal(1,"Balloon did not reduce gravity tilt");finish();
        contact_left=8;contact_right=20;begin_calc();wait_calc();
        if(gravity_tilt!=-12) $fatal(1,"Balloon gravity tilt lost mirror symmetry");finish();
        put(0,`LP_PART_BALLOON);begin_calc();wait_calc();
        if(gravity_tilt!=0 || support_neg!=0 || support_pos!=0)
            $fatal(1,"Net upward lift retained ground gravity/support");finish();
        centre();grounded=1;contact_valid=1;contact_left=-100;contact_right=-80;
        begin_calc();wait_calc();if(gravity_tilt!=256) $fatal(1,"Positive gravity tilt cap failed");finish();
        contact_left=80;contact_right=100;begin_calc();wait_calc();
        if(gravity_tilt!=-256) $fatal(1,"Negative gravity tilt cap failed");finish();
        grounded=0;begin_calc();wait_calc();
        if(gravity_tilt!=0 || support_neg!=0 || support_pos!=0)
            $fatal(1,"Airborne body retained contact moments");finish();
        // Contact bounds are in world x: subtract the rotated COM offset.
        centre();put(1,`LP_PART_FAN);grounded=1;contact_valid=1;
        tilt=8;next_tilt=8;contact_left=-8;contact_right=12;
        begin_calc();wait_calc();if(support_neg!=72 || support_pos!=8 || gravity_tilt!=0)
            $fatal(1,"Rotated COM did not shift actual support arms");finish();
        tilt=-8;next_tilt=-8;contact_left=-12;contact_right=8;
        begin_calc();wait_calc();if(support_neg!=8 || support_pos!=72 || gravity_tilt!=0)
            $fatal(1,"Mirrored rotated COM support arms wrong");finish();
        centre();grounded=1;contact_valid=1;contact_left=-16;contact_right=16;
        begin_calc();contact_valid=0;contact_left=-100;contact_right=-80;wait_calc();
        if(support_neg!=64 || support_pos!=64 || gravity_tilt!=0)
            $fatal(1,"Live contact changes corrupted accepted span");finish();
        // Only one tyre may really touch: a nominal second wheel must not
        // overwrite the accepted narrow span and invent balanced support.
        empty();frames=9'b000111000;frame_alive=frames;grounded=1;contact_valid=1;
        put(3,`LP_PART_ENGINE);put(4,`LP_PART_PIG);put(6,`LP_PART_WHEEL);put(8,`LP_PART_WHEEL);
        contact_left=32;contact_right=48;begin_calc();wait_calc();
        if(comx!=-7 || support_neg!=0 || support_pos!=0 || gravity_tilt!=-172)
            $fatal(1,"Inferred wheels overrode actual right contact");finish();
        grid[3*3 +: 3]=`LP_PART_EMPTY;alive[3]=0;put(5,`LP_PART_ENGINE);
        contact_left=-48;contact_right=-32;begin_calc();wait_calc();
        if(comx!=7 || support_neg!=0 || support_pos!=0 || gravity_tilt!=172)
            $fatal(1,"Actual left contact lost mirror symmetry");finish();
        // Symmetric fan forces cannot create torque at any body angle.
        for(angle=-16;angle<16;angle=angle+1) begin
            centre();put(1,`LP_PART_FAN);put(7,`LP_PART_FAN);fan=1;
            tilt=angle;next_tilt=angle;begin_calc();wait_calc();
            if(torque!=0 || accel!=0) $fatal(1,"Balanced fans created torque at angle %0d: %0d",angle,torque);
            finish();
            // A force couple reverses exactly when both actuator forces flip.
            facing[7]=1;begin_calc();wait_calc();reference_torque=torque;reference_accel=accel;finish();
            facing=9'b000000010;begin_calc();wait_calc();
            if($signed(torque)!=-reference_torque || $signed(accel)!=-reference_accel)
                $fatal(1,"Fan couple reversal lost symmetry at angle %0d",angle);
            finish();
        end
        // A reflected body at the reflected angle has the reflected torque
        // and pivot displacement. Use an asymmetric COM to expose rounding.
        for(angle=-16;angle<16;angle=angle+1) begin
            centre();put(0,`LP_PART_FAN);fan=1;tilt=angle;next_tilt=angle+1;
            begin_calc();wait_calc();reference_torque=torque;reference_accel=accel;finish();
            reference_pivot_x=pdx;reference_pivot_y=pdy;
            centre();put(2,`LP_PART_FAN);facing[2]=1;fan=1;tilt=-angle;next_tilt=-(angle+1);
            begin_calc();wait_calc();
            if($signed(torque)!=-reference_torque || $signed(accel)!=-reference_accel)
                $fatal(1,"Mirrored fan layout lost torque symmetry at angle %0d",angle);
            finish();
            if($signed(pdx)!=-reference_pivot_x || $signed(pdy)!=reference_pivot_y)
                $fatal(1,"Mirrored COM pivot lost position symmetry at angle %0d",angle);
        end
        // Actual contact capacities and overhang weight also mirror at every
        // angle, including fractional world projections of an offset COM.
        for(angle=-16;angle<16;angle=angle+1) begin
            centre();put(0,`LP_PART_FAN);grounded=1;contact_valid=1;
            tilt=angle;next_tilt=angle;contact_left=-20;contact_right=24;
            begin_calc();wait_calc();reference_support_neg=support_neg;reference_support_pos=support_pos;finish();
            centre();put(2,`LP_PART_FAN);grounded=1;contact_valid=1;
            tilt=-angle;next_tilt=-angle;contact_left=-24;contact_right=20;
            begin_calc();wait_calc();
            if(support_neg!=reference_support_pos || support_pos!=reference_support_neg || gravity_tilt!=0)
                $fatal(1,"Actual contact capacity lost mirror symmetry at angle %0d",angle);
            finish();
            contact_left=-32;contact_right=-24;begin_calc();wait_calc();reference_gravity=gravity_tilt;finish();
            centre();put(0,`LP_PART_FAN);grounded=1;contact_valid=1;
            tilt=angle;next_tilt=angle;contact_left=24;contact_right=32;
            begin_calc();wait_calc();
            if($signed(gravity_tilt)!=-reference_gravity || support_neg!=0 || support_pos!=0)
                $fatal(1,"Actual contact gravity lost mirror symmetry at angle %0d",angle);
            finish();
        end
        // Toppling uses the physical contact edge, expressed in world axes.
        // The contact point is (-2,12) pixels from the grid centre; its
        // one-pixel stability margin must not move the physical anchor.
        centre();grounded=1;contact_valid=1;contact_left=-20;contact_right=-4;contact_y=48;
        next_tilt=1;begin_calc();wait_calc();finish();
        if(pdx!=0 || pdy!=0) $fatal(1,"Free COM pivot moved a centred mass");
        pivot_contact=1;pivot_direction=1;begin_calc();wait_calc();finish();
        if(pdx!=590 || pdy!=160) $fatal(1,"Right toppling did not preserve actual contact point: %0d,%0d",pdx,pdy);
        contact_left=4;contact_right=20;pivot_direction=-1;next_tilt=-1;
        begin_calc();wait_calc();finish();
        if(pdx!=-590 || pdy!=160) $fatal(1,"Left toppling did not mirror physical contact pivot");
        contact_left=-20;contact_right=-4;pivot_direction=1;tilt=3;next_tilt=4;
        begin_calc();wait_calc();finish();
        if(pdx!=590 || pdy!=160) $fatal(1,"Contact point was rotated twice instead of using angle change");
        next_tilt=tilt;begin_calc();wait_calc();finish();
        if(pdx!=0 || pdy!=0) $fatal(1,"Stationary contact pivot introduced motion");
        empty();frames=9'b000111000;frame_alive=frames;
        put(3,`LP_PART_ENGINE);put(4,`LP_PART_PIG);put(6,`LP_PART_WHEEL);put(8,`LP_PART_WHEEL);
        tilt=0;next_tilt=1;begin_calc();wait_calc();finish();reference_pivot_x=pdx;reference_pivot_y=pdy;
        pivot_contact=1;pivot_direction=1;begin_calc();wait_calc();finish();
        if(pdx!=reference_pivot_x || pdy!=reference_pivot_y)
            $fatal(1,"Missing actual contact did not fall back to COM pivot");
        // A 24-pixel framed body on a 45-degree ramp: both lower corners
        // balance it when aligned, despite unequal endpoint heights.
        centre();frames=9'h1ff;frame_alive=frames;grounded=1;contact_valid=1;
        endpoint_y_valid=1;terrain_slope_valid=1;terrain_slope=16;tilt=4;next_tilt=4;
        contact_left=-72;contact_right=4;contact_left_y=0;contact_right_y=68;
        begin_calc();wait_calc();
        if(normal_unstable || gravity_tilt!=0 || support_neg!=144 || support_pos!=144)
            $fatal(1,"Aligned ramp body did not balance its normal reaction");finish();
        terrain_slope=-16;tilt=-4;next_tilt=-4;
        contact_left=-4;contact_right=72;contact_left_y=68;contact_right_y=0;
        begin_calc();wait_calc();
        if(normal_unstable || gravity_tilt!=0 || support_neg!=144 || support_pos!=144)
            $fatal(1,"Mirrored aligned ramp normal reaction wrong");finish();
        // Above the ramp angle, front-corner normal torque restores CCW.
        // A vertical-only reaction would wrongly accelerate the body CW.
        terrain_slope=16;tilt=5;next_tilt=5;contact_left=-17;contact_right=-9;
        contact_left_y=66;contact_right_y=66;begin_calc();wait_calc();
        if(!normal_unstable || gravity_tilt!=-106 || support_neg!=0 || support_pos!=0)
            $fatal(1,"Steeper body did not restore toward positive ramp");finish();
        terrain_slope=-16;tilt=-5;next_tilt=-5;contact_left=9;contact_right=17;
        begin_calc();wait_calc();if(!normal_unstable || gravity_tilt!=106)
            $fatal(1,"Steeper mirrored body lost restoring torque");finish();
        // Below the ramp angle, the rear corner supplies the opposite torque.
        terrain_slope=16;tilt=3;next_tilt=3;contact_left=-70;contact_right=-62;
        contact_left_y=13;contact_right_y=13;begin_calc();wait_calc();
        if(!normal_unstable || gravity_tilt!=106) $fatal(1,"Shallower body did not restore toward ramp");finish();
        terrain_slope=-16;tilt=-3;next_tilt=-3;contact_left=62;contact_right=70;
        begin_calc();wait_calc();if(!normal_unstable || gravity_tilt!=-106)
            $fatal(1,"Shallower mirrored body lost restoring torque");finish();
        // Non-45-degree slopes require both the dy term and normalization.
        terrain_slope=8;tilt=3;next_tilt=3;contact_left=9;contact_right=17;
        contact_left_y=66;contact_right_y=66;begin_calc();wait_calc();
        if(!normal_unstable || gravity_tilt!=-147) $fatal(1,"Half-gradient normal factor wrong");finish();
        terrain_slope=-8;tilt=-3;next_tilt=-3;contact_left=-17;contact_right=-9;
        begin_calc();wait_calc();if(!normal_unstable || gravity_tilt!=147)
            $fatal(1,"Mirrored half-gradient normal factor wrong");finish();
        terrain_slope=8;tilt=2;next_tilt=2;contact_left=-66;contact_right=-58;
        contact_left_y=26;contact_right_y=26;begin_calc();wait_calc();
        if(!normal_unstable || gravity_tilt!=156) $fatal(1,"Half-gradient rear normal torque wrong");finish();
        terrain_slope=-8;tilt=-2;next_tilt=-2;contact_left=58;contact_right=66;
        begin_calc();wait_calc();if(!normal_unstable || gravity_tilt!=-156)
            $fatal(1,"Mirrored half-gradient rear normal torque wrong");finish();
        terrain_slope=16;tilt=5;next_tilt=5;contact_left=-17;contact_right=-9;
        endpoint_y_valid=0;contact_y=66;contact_left_y=0;contact_right_y=0;
        begin_calc();wait_calc();if(gravity_tilt!=-106)
            $fatal(1,"Legacy shared contact y fallback ignored");finish();
        terrain_slope_valid=0;begin_calc();wait_calc();if(gravity_tilt!=52)
            $fatal(1,"Unknown gradient did not use vertical ledge normal");finish();
        terrain_slope_valid=1;put(1,`LP_PART_BALLOON);begin_calc();wait_calc();
        if(gravity_tilt!=-26) $fatal(1,"Balloon did not reduce inclined normal torque");finish();
        put(7,`LP_PART_BALLOON);begin_calc();wait_calc();
        if(gravity_tilt!=0 || support_neg!=0 || support_pos!=0)
            $fatal(1,"Net upward lift retained inclined reaction torque");finish();
        // Quantized absolute COM offsets must telescope around every angle.
        empty();frames=9'b000111000;frame_alive=frames;
        put(3,`LP_PART_ENGINE);put(4,`LP_PART_PIG);put(6,`LP_PART_WHEEL);put(8,`LP_PART_WHEEL);
        for(angle=-16;angle<16;angle=angle+1) begin
            tilt=angle;next_tilt=angle+1;begin_calc();wait_calc();finish();
            forward_x=pdx;forward_y=pdy;
            tilt=angle+1;next_tilt=angle;begin_calc();wait_calc();finish();
            if(forward_x+$signed(pdx)!=0 || forward_y+$signed(pdy)!=0)
                $fatal(1,"Closed pivot cycle drifted at angle %0d",angle);
        end
        empty();contact_valid=1;grounded=1;contact_left=-16;contact_right=16;
        begin_calc();wait_calc();if(mass!=0 || torque!=0 || accel!=0 || gravity_tilt!=0 || support_neg!=0 || support_pos!=0)
            $fatal(1,"Empty vehicle retained mass, force or support");finish();
        centre();put(1,`LP_PART_FAN);fan=1;force_valid=0;begin_calc();clocks(120);
        if(valid) $fatal(1,"Moment read unready wheel force");force_valid=1;wait_calc();finish();
        centre();begin_calc();clocks(4);reset=1;clocks(1);reset=0;clocks(2);
        if(valid || pivot_valid) $fatal(1,"Reset retained an incomplete result");
        $display("PASS vehicle_moments_tb: %0d COM, fan/rocket couples, actual frame/wheel support, gravity tilt, closed pivot cycles, damage, snapshot and handshake cases",tests);
        $finish;
    end
    initial begin #2000000;$fatal(1,"Moment test timeout");end
endmodule
