// Owner: Shared. Rotated vehicle raster, zoom, facing and damage checks.
`timescale 1ns / 1ps
`include "game_defs.vh"
module vehicle_rotation_renderer_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg [12:0] pixel=0;
    reg zoomed_out=1, overview=0;
    reg [2:0] state=`LP_RUN;
    reg signed [3:0] tilt=0;
    reg [8:0] facing=9'b000001000;
    reg [8:0] intact=9'b101111101, frames=9'b000111000;
    wire [26:0] grid={`LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
                      `LP_PART_FAN, `LP_PART_PIG, `LP_PART_ENGINE,
                      `LP_PART_BOOSTER, `LP_PART_EMPTY, `LP_PART_BALLOON};
    wire [15:0] colour;
    wire signed [10:0] map_x, map_y;
    integer scale_index, angle_index, xx, yy, tested=0, raster_count=0;
    integer expected_tilt, cell_size;
    reg [15:0] expected;
    `include "part_sprites.vh"

    right_renderer dut (
        .clk(clk), .pixel_index(pixel), .zoomed_out(zoomed_out), .overview(overview),
        .free_look(1'b1), .cursor_x(7'd0), .cursor_y(7'd0), .game_state(state),
        .build_grid(grid), .build_facing_left(facing), .intact_mask(intact),
        .frame_intact_mask(frames), .vehicle_x(20'sd6144), .vehicle_y(20'sd4096),
        .vehicle_tilt(tilt), .spawn_x(20'sd6144), .spawn_y(20'sd4096),
        .terrain_count(3'd0), .terrain_rects(128'd0), .goal_rect(32'd0),
        .tnt_count(3'd0), .tnt_positions(64'd0), .tnt_intact(4'd0),
        .hazard_count(2'd0), .hazard_rects(64'd0), .blast_phase(8'd0),
        .death_phase(2'd0), .death_x(20'sd0), .death_y(20'sd0),
        .launch_flash(1'b0), .anim_phase(1'b1), .map_level(1'b0), .map_id(1'b0),
        .world_width(10'd192), .world_height(10'd128), .flag_x(10'd0), .flag_y(10'd0),
        .map_x(map_x), .map_y(map_y), .map_class(`LP_MAP_SKY), .pixel_data(colour)
    );

    // Independent real-valued inverse geometry, followed by the existing
    // sprite art as the colour oracle. Pixel centres avoid an arbitrary
    // left/top bias when a whole 3x3 vehicle rotates about its centre.
    function [15:0] golden;
        input integer sx, sy, angle;
        integer origin_x, origin_y, local_x, local_y, col, row, cell_index;
        integer sample_x, sample_y, c, s;
        reg [2:0] part;
        reg [15:0] result;
        real dx, dy, source_x, source_y;
        begin
            origin_x=3*cell_size; origin_y=2*cell_size;
            local_x=sx-origin_x; local_y=sy-origin_y;
            c=256; s=0;
            case (angle)
                 1: begin c=251; s=50; end
                -1: begin c=251; s=-50; end
                 4: begin c=181; s=181; end
                -4: begin c=181; s=-181; end
                 2: begin c=237; s=98; end
                -2: begin c=237; s=-98; end
                 3: begin c=213; s=142; end
                -3: begin c=213; s=-142; end
                default: begin c=256; s=0; end
            endcase
            dx=local_x+0.5-1.5*cell_size;
            dy=local_y+0.5-1.5*cell_size;
            source_x=(c*dx+s*dy)/256.0+1.5*cell_size;
            source_y=(-s*dx+c*dy)/256.0+1.5*cell_size;
            local_x=$floor(source_x); local_y=$floor(source_y);
            result=16'h0010;
            if (local_x>=0 && local_x<3*cell_size && local_y>=0 && local_y<3*cell_size) begin
                col=local_x/cell_size; row=local_y/cell_size;
                cell_index=row*3+col;
                sample_x=local_x%cell_size; sample_y=local_y%cell_size;
                part=grid[cell_index*3 +: 3];
                if (cell_size==4 || cell_size==6) begin
                    sample_x=cell_size==4 ? 2*sample_x : (4*sample_x)/3;
                    sample_y=cell_size==4 ? 2*sample_y : (4*sample_y)/3;
                end
                if (cell_size==12) begin
                    if (frames[cell_index]) result=part_sprite12(`LP_PART_FRAME,sample_x,sample_y,1'b0,result);
                    if (intact[cell_index]) result=part_sprite_facing(part,sample_x,sample_y,12,facing[cell_index],1'b1,result);
                end else begin
                    if (frames[cell_index]) result=part_sprite(`LP_PART_FRAME,sample_x,sample_y,1'b0,result);
                    if (intact[cell_index]) result=part_sprite_facing(part,sample_x,sample_y,8,facing[cell_index],1'b1,result);
                end
            end
            golden=result;
        end
    endfunction

    task check_raster;
        input integer angle;
        begin
            for (yy=0; yy<64; yy=yy+1)
                for (xx=0; xx<96; xx=xx+1) begin
                    @(negedge clk); pixel=yy*96+xx;
                    @(posedge clk); #1;
                    expected=golden(xx,yy,angle);
                    if (colour!==expected)
                        $fatal(1,"Rotation raster %0d zoom%0d angle%0d pixel(%0d,%0d) got %h expected %h",
                               raster_count,scale_index,angle,xx,yy,colour,expected);
                    tested=tested+1;
                end
            raster_count=raster_count+1;
        end
    endtask

    initial begin
        repeat(2) @(negedge clk);
        for (scale_index=0; scale_index<4; scale_index=scale_index+1) begin
            overview=scale_index>=2;
            zoomed_out=scale_index==1 || scale_index==2;
            case(scale_index)
                0: cell_size=12;
                1: cell_size=8;
                2: cell_size=6;
                default: cell_size=4;
            endcase
            for (angle_index=0; angle_index<9; angle_index=angle_index+1) begin
                case(angle_index)
                    0: expected_tilt=0;
                    1: expected_tilt=4;
                    2: expected_tilt=-4;
                    3: expected_tilt=2;
                    4: expected_tilt=-2;
                    5: expected_tilt=1;
                    6: expected_tilt=-1;
                    7: expected_tilt=3;
                    default: expected_tilt=-3;
                endcase
                tilt=expected_tilt; check_raster(expected_tilt);
            end
            // Rotation preserves the saved facing and each layer's damage.
            facing=~facing; intact=9'b001010100; frames=9'b000101000;
            tilt=2; check_raster(2);
            facing=9'b000001000; intact=9'b101111101; frames=9'b000111000;
            // Construction previews stay upright regardless of stale tilt.
            state=`LP_BUILD; tilt=4; check_raster(0); state=`LP_RUN;
            tilt=4'sd7; check_raster(0);
            tilt=4'bxxxx; check_raster(0);
        end
        $display("PASS vehicle_rotation_renderer_tb: %0d rasters, %0d pixels; +/- tilt, zero identity, four zooms, facing, damage, build and invalid inputs",
                 raster_count,tested);
        $finish;
    end
    initial begin #10000000; $fatal(1,"Vehicle rotation renderer timed out"); end
endmodule
