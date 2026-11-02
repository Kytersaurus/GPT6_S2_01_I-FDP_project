// Owner: Role 2 - Kyle. Force invariants independent of map-specific geometry.
`timescale 1ns / 1ps
`include "game_defs.vh"
module physics_invariants_tb;
    reg clk=0,reset=1,run_init=0,step_start=0,update_release=0;
    reg [2:0] game_state=`LP_BUILD;
    reg moments=0,engine=0,reverse_drive=0,contact=1,grade_valid=1;
    reg follow_tilt=0;
    reg [7:0] mass=4;
    reg [3:0] wheels=2;
    reg signed [7:0] grade=0;
    reg unstable=1;
    reg signed [1:0] tip=0;
    reg accept=0,response=0;
    reg signed [19:0] cx=0,cy=0;
    reg signed [15:0] cvx=0;
    wire initialized,valid,response_ready,committed;
    wire signed [19:0] nx,ny,x,y;
    wire signed [15:0] nvx,nvy;
    wire signed [4:0] nt,tilt;
    reg signed [4:0] positive_angles[0:39];
    reg signed [13:0] positive_rates[0:39];
    integer cases=0,updates=0,waited,mode,hint,sign_choice,choice;
    integer starting_speed,previous_speed,new_speed,coast_updates,bound,tail,j;
    integer reference_velocity,raw_grade,rate_before,test_rate;
    reg signed [4:0] rest_angle;
    reg signed [19:0] stopped_x;
    always #5 clk=~clk;

    // A centred mass keeps rotation-origin compensation out of these
    // translational properties. Prescribed mass/wheel inputs exercise the
    // force interface independently of the builder's inventory restrictions.
    physics_engine dut(
        .clk(clk),.reset(reset),.run_init(run_init),.game_state(game_state),
        .spawn_x(20'sd8192),.spawn_y(20'sd8192),.init_ready(initialized),
        .step_start(step_start),.update_release(update_release),
        .wheel_count(wheels),.engine_count(4'd1),.balloon_count(4'd0),.mass_units(mass),
        .engine_enabled(engine),.engine_reverse(reverse_drive),.jump_press(1'b0),.boost_req(1'b0),
        .moments_enabled(moments),.build_grid({12'd0,`LP_PART_PIG,12'd0}),
        .build_frames(9'b000010000),.frame_intact_mask(9'b000010000),.intact_mask(9'b000010000),
        .build_facing_left(9'd0),.rocket_vertical_mask(9'd0),.fan_enabled(1'b0),.fan_balance(5'sd0),
        .rocket_balance(5'sd0),.rocket_vertical_balance(5'sd0),.rocket_count(4'd0),.rocket_req(1'b0),
        .move_valid(valid),.move_ready(accept),.proposed_x(nx),.proposed_y(ny),
        .proposed_vx(nvx),.proposed_vy(nvy),.vehicle_x(x),.vehicle_y(y),
        .proposed_tilt(nt),.vehicle_tilt(tilt),
        .response_valid(response),.response_ready(response_ready),
        .corrected_x(cx),.corrected_y(cy),.corrected_vx(cvx),.corrected_vy(16'sd0),
        .corrected_tilt(follow_tilt ? nt : 5'sd0),.grounded(contact),.ground_slope(grade),.ground_slope_valid(grade_valid),
        .support_unstable(unstable),.tip_dir(tip),.support_span_valid(1'b0),
        .support_left_q2(10'sd0),.support_right_q2(10'sd0),.movement_committed(committed)
    );
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task begin_step;begin
        step_start=1;clocks(1);step_start=0;waited=0;
        while(!valid && waited<3000) begin clocks(1);waited=waited+1;end
        if(!valid) $fatal(1,"Invariant request timeout mode%0d",moments);
    end endtask
    task finish_step;begin
        accept=1;clocks(1);accept=0;
        if(!response_ready) $fatal(1,"Invariant response not accepted");
        response=1;clocks(1);response=0;
        if(!committed || x!==cx || y!==cy) $fatal(1,"Invariant response failed to commit");
        clocks(1);update_release=1;clocks(1);update_release=0;updates=updates+1;
    end endtask
    task accept_proposal;begin cx=nx;cy=8192;cvx=nvx;finish_step;end endtask
    task seed;
        input integer vx_start;
        begin
            reset=1;game_state=`LP_BUILD;run_init=0;
            step_start=0;update_release=0;accept=0;response=0;
            clocks(2);reset=0;game_state=`LP_INIT_RUN;run_init=1;clocks(2);
            if(!initialized) $fatal(1,"Invariant initialization missing");
            run_init=0;game_state=`LP_RUN;begin_step;
            if(nvx!==0) $fatal(1,"Unconfirmed contact generated force");
            cx=8192;cy=8192;cvx=vx_start;finish_step;
        end
    endtask
    task configure_coast;
        input integer selected;
        begin
            case(selected)
                0: begin mass=1;wheels=1;starting_speed=1;end
                1: begin mass=4;wheels=2;starting_speed=2;end
                2: begin mass=11;wheels=2;starting_speed=7;end
                3: begin mass=31;wheels=1;starting_speed=80;end
                4: begin mass=11;wheels=2;starting_speed=256;end
                default: begin mass=255;wheels=9;starting_speed=2;end
            endcase
        end
    endtask
    initial begin
        clocks(3);
        for(mode=0;mode<2;mode=mode+1) begin
            moments=mode[0];engine=0;reverse_drive=0;grade=0;grade_valid=1;contact=1;unstable=1;follow_tilt=0;
            // Even a stale/unstable support hint cannot provide horizontal
            // force on a flat floor. True support/tilt release is tested elsewhere.
            for(hint=-1;hint<=1;hint=hint+1) begin
                tip=hint;mass=4;wheels=2;seed(0);stopped_x=x;
                repeat(24) begin
                    begin_step;
                    if(nvx!==0 || nx!==stopped_x)
                        $fatal(1,"Flat rest moved: mode%0d tip%0d vx%0d dx%0d",mode,hint,nvx,nx-stopped_x);
                    accept_proposal;
                end
                cases=cases+1;
            end
            // Include one/two-quantum speeds, heavy/light bodies and multiple
            // wheel counts. Friction may wait for a fraction, never accelerate
            // a coast, reverse its sign, or restart the body after stopping.
            for(choice=0;choice<6;choice=choice+1) begin
                configure_coast(choice);
                for(hint=-1;hint<=1;hint=hint+1) begin
                    tip=hint;
                    for(sign_choice=-1;sign_choice<=1;sign_choice=sign_choice+2) begin
                        seed(sign_choice*starting_speed);previous_speed=starting_speed;
                        coast_updates=0;bound=mass*starting_speed+16;
                        while(previous_speed!=0 && coast_updates<bound) begin
                            begin_step;new_speed=$signed(nvx)*sign_choice;
                            if(new_speed<0 || new_speed>previous_speed)
                                $fatal(1,"Coast gained/reversed speed mode%0d mass%0d wheels%0d tip%0d old%0d new%0d",mode,mass,wheels,hint,previous_speed,new_speed);
                            if(($signed(nx)-$signed(x))*sign_choice<0)
                                $fatal(1,"Coast moved opposite its velocity");
                            accept_proposal;previous_speed=new_speed;coast_updates=coast_updates+1;
                        end
                        if(previous_speed!=0) $fatal(1,"Positive friction never stopped coast");
                        stopped_x=x;
                        repeat(16) begin
                            begin_step;
                            if(nvx!==0 || nx!==stopped_x) $fatal(1,"Stopped coast restarted with no applied force mode%0d tip%0d",mode,hint);
                            accept_proposal;
                        end
                        cases=cases+1;
                    end
                end
            end
            // With no rolling or scraping resistance, force-free horizontal
            // motion is constant. CoG hints cannot add or remove momentum.
            wheels=0;
            for(choice=0;choice<3;choice=choice+1) begin
                mass=choice==0 ? 1 : choice==1 ? 11 : 255;
                starting_speed=choice==0 ? 1 : choice==1 ? 2 : 256;
                for(hint=-1;hint<=1;hint=hint+1) begin
                    tip=hint;
                    for(sign_choice=-1;sign_choice<=1;sign_choice=sign_choice+2) begin
                        seed(sign_choice*starting_speed);
                        repeat(12) begin
                            begin_step;
                            if($signed(nvx)!==sign_choice*starting_speed || $signed(nx)-$signed(x)!==sign_choice*starting_speed)
                                $fatal(1,"Force-free momentum changed mode%0d tip%0d",mode,hint);
                            accept_proposal;
                        end
                        cases=cases+1;
                    end
                end
            end
            // Prime an acceleration fraction through the public motor input,
            // then remove the force. The saved fraction alone must not move a
            // resting body or turn a later opposite support hint into a push.
            mass=255;grade=0;grade_valid=1;
            for(sign_choice=-1;sign_choice<=1;sign_choice=sign_choice+2) begin
                for(choice=0;choice<2;choice=choice+1) begin
                    wheels=choice==0 ? 0 : 2;tip=0;engine=1;reverse_drive=sign_choice<0;
                    seed(0);begin_step;
                    if(nvx!==0) $fatal(1,"Sub-quantum motor fixture produced whole velocity");
                    accept_proposal;engine=0;stopped_x=x;
                    for(j=0;j<24;j=j+1) begin
                        tip=j[0] ? 1 : -1;
                        begin_step;
                        if(nvx!==0 || nx!==stopped_x) $fatal(1,"Force-free saved fraction generated drift mode%0d",mode);
                        accept_proposal;
                    end
                    cases=cases+1;
                end
            end
            engine=0;reverse_drive=0;mass=11;wheels=2;
            // Marking a raw grade invalid must give the same translation as a
            // measured flat floor, irrespective of stale sign or support hint.
            for(raw_grade=-16;raw_grade<=16;raw_grade=raw_grade+32) begin
                for(hint=-1;hint<=1;hint=hint+1) begin
                    tip=hint;
                    for(sign_choice=-1;sign_choice<=1;sign_choice=sign_choice+2) begin
                        grade=0;grade_valid=1;seed(sign_choice*80);
                        begin_step;reference_velocity=$signed(nvx);
                        grade=raw_grade;grade_valid=0;seed(sign_choice*80);
                        begin_step;
                        if($signed(nvx)!==reference_velocity) $fatal(1,"Invalid grade generated horizontal gravity mode%0d raw%0d",mode,raw_grade);
                        accept_proposal;cases=cases+1;
                    end
                end
            end
            grade=0;grade_valid=1;
            // Quantized angular initial conditions have no public impulse port.
            // Deposit only the initial rate; every later step uses normal
            // request/response handshakes and must evolve symmetrically.
            contact=0;unstable=0;tip=0;mass=4;wheels=0;follow_tilt=1;
            if(!moments) begin
                for(sign_choice=-1;sign_choice<=1;sign_choice=sign_choice+2) begin
                    seed(0);dut.spin=sign_choice*2;dut.spin_frac=0;
                    repeat(12) begin
                        begin_step;
                        if(nt!==0) $fatal(1,"Tiny mirrored legacy spin introduced a full-angle bias");
                        accept_proposal;
                    end
                    cases=cases+1;
                end
            end
            for(sign_choice=1;sign_choice>=-1;sign_choice=sign_choice-2) begin
                seed(0);
                if(moments) begin dut.angular_velocity_q8=sign_choice*1024;dut.moment_angle_remainder=0;end
                else begin dut.spin=sign_choice*16;dut.spin_frac=0;end
                rate_before=moments ? 1024 : 16;
                for(j=0;j<40;j=j+1) begin
                    begin_step;
                    test_rate=moments ? $signed(dut.angular_velocity_q8) : $signed(dut.spin);
                    if(test_rate*sign_choice<0 || test_rate*sign_choice>rate_before)
                        $fatal(1,"Angular drag gained speed or reversed mode%0d",mode);
                    rate_before=test_rate*sign_choice;
                    if(sign_choice>0) begin positive_angles[j]=nt;positive_rates[j]=test_rate;end
                    else if(nt!==-positive_angles[j] || test_rate!=-positive_rates[j])
                        $fatal(1,"Angular mirror symmetry failed mode%0d update%0d tilt%0d mirror%0d rate%0d mirror_rate%0d",mode,j,nt,-positive_angles[j],test_rate,-positive_rates[j]);
                    accept_proposal;
                end
                if(test_rate!=0) $fatal(1,"Unpowered angular motion never stopped mode%0d",mode);
                rest_angle=tilt;
                repeat(12) begin
                    begin_step;
                    if(nt!==rest_angle) $fatal(1,"Stopped angular state restarted mode%0d",mode);
                    accept_proposal;
                end
                cases=cases+1;
            end
        end
        $display("PASS physics_invariants_tb: %0d scenarios/%0d accepted updates; both rotation modes, flat rest, mirrored coasts to rest, force-free momentum, saved fractions, invalid grades and mirrored angular drag",cases,updates);$finish;
    end
    initial begin #100000000;$fatal(1,"Physics invariant timeout");end
endmodule
