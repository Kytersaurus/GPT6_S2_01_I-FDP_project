// Owner: Role 3 - Yap Ting. Goal, hazard and bounds checks after movement.
`timescale 1ns / 1ps
`include "game_defs.vh"

// World results are sampled from the committed vehicle pose. The module
// holds its flags until Role 4 accepts the world_valid response.
module world_outcomes (
    input wire clk, reset, run_init,
    input wire [2:0] game_state,
    output reg init_ready,
    input wire movement_committed,
    input wire signed [`LP_COORD_BITS-1:0] vehicle_x, vehicle_y,
    input wire signed [3:0] vehicle_tilt,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire [31:0] goal_rect,
    input wire map_level,
    input wire [9:0] world_width, world_height,
    input wire [9:0] flag_x, flag_y,
    input wire [1:0] hazard_count,
    input wire [63:0] hazard_rects,
    output reg world_valid,
    input wire world_ready,
    output reg goal_hit,
    output reg hazard_hit,
    output reg out_of_bounds
);
    `include "rotation_geometry.vh"
    localparam IDLE=0, POSE=1, GOAL=2, HAZARD_SETUP=3, X_PRODUCTS=4,
               X_SUM_Y_PRODUCTS=5, Y_SUM=6, HAZARD_CHECK=7, FINISH=8;
    reg [3:0] phase;
    reg signed [20:0] centre_x, centre_y, pig_x, pig_y;
    reg signed [20:0] vehicle_left, vehicle_top, vehicle_right, vehicle_bottom;
    reg signed [20:0] goal_left, goal_top, goal_right, goal_bottom;
    reg [9:0] saved_width, saved_height;
    reg signed [14:0] body_extent;
    reg signed [9:0] tilt_cos, tilt_sin, tilt_abs_sin;
    reg signed [4:0] pig_local_x, pig_local_y;
    reg pig_found;
    reg [63:0] saved_hazards;
    reg [1:0] saved_hazard_count, hazard_index;
    reg hazard_aabb;
    reg signed [20:0] hazard_dx, hazard_dy;
    reg [7:0] hazard_w, hazard_h;
    reg signed [30:0] product_a, product_b;
    reg signed [18:0] extent_product_a, extent_product_b;
    reg signed [31:0] hazard_local_x, hazard_local_y;
    reg signed [26:0] hazard_extent_x, hazard_extent_y;
    integer index;
    reg candidate_pig_found;
    reg signed [4:0] candidate_pig_x, candidate_pig_y;
    wire [31:0] hazard_rect=saved_hazards >> (hazard_index[0]*32);
    wire [7:0] hx=hazard_rect[7:0], hy=hazard_rect[15:8];
    wire [7:0] hw=hazard_rect[23:16], hh=hazard_rect[31:24];
    wire signed [20:0] hx_fp=$signed({1'b0,hx,8'b0});
    wire signed [20:0] hy_fp=$signed({1'b0,hy,8'b0});
    wire signed [20:0] hr_fp=hx_fp+$signed({1'b0,hw,8'b0});
    wire signed [20:0] hb_fp=hy_fp+$signed({1'b0,hh,8'b0});

    // Cell centre coordinates are only -8,0,+8, so rotating the pig
    // needs signed shifts/muxes rather than four general multipliers.
    function signed [14:0] cell_component;
        input signed [4:0] position;
        input signed [9:0] coefficient;
        reg signed [14:0] extended_coefficient;
        begin
            extended_coefficient=coefficient;
            case(position)
                -5'sd8: cell_component=-(extended_coefficient <<< 3);
                 5'sd8: cell_component=extended_coefficient <<< 3;
                default: cell_component=0;
            endcase
        end
    endfunction
    wire signed [15:0] pig_offset_x=cell_component(pig_local_x,tilt_cos)-cell_component(pig_local_y,tilt_sin);
    wire signed [15:0] pig_offset_y=cell_component(pig_local_x,tilt_sin)+cell_component(pig_local_y,tilt_cos);

    always @* begin
        candidate_pig_found=0; candidate_pig_x=0; candidate_pig_y=0;
        for(index=0;index<9;index=index+1)
            if(intact_mask[index] && build_grid[index*3 +: 3]==`LP_PART_PIG) begin
                candidate_pig_found=1;
                candidate_pig_x=(index%3)*8-8;
                candidate_pig_y=(index/3)*8-8;
            end
    end
    always @(posedge clk) begin
        if(reset) begin
            phase<=IDLE; init_ready<=0; world_valid<=0;
            goal_hit<=0; hazard_hit<=0; out_of_bounds<=0;
            centre_x<=0; centre_y<=0; pig_x<=0; pig_y<=0;
            vehicle_left<=0; vehicle_top<=0; vehicle_right<=0; vehicle_bottom<=0;
            goal_left<=0; goal_top<=0; goal_right<=0; goal_bottom<=0;
            saved_width<=0; saved_height<=0; body_extent<=0;
            tilt_cos<=256; tilt_sin<=0; tilt_abs_sin<=0;
            pig_local_x<=0; pig_local_y<=0; pig_found<=0;
            saved_hazards<=0; saved_hazard_count<=0; hazard_index<=0;
            hazard_aabb<=0; hazard_dx<=0; hazard_dy<=0; hazard_w<=0; hazard_h<=0;
            product_a<=0; product_b<=0; extent_product_a<=0; extent_product_b<=0;
            hazard_local_x<=0; hazard_local_y<=0; hazard_extent_x<=0; hazard_extent_y<=0;
        end else begin
            if(!run_init) init_ready<=0;
            if(run_init && !init_ready) begin
                init_ready<=1; phase<=IDLE; world_valid<=0;
                goal_hit<=0; hazard_hit<=0; out_of_bounds<=0;
            end else begin
                if(world_valid && world_ready) world_valid<=0;
                if(game_state!=`LP_RUN) phase<=IDLE;
                else case(phase)
                    IDLE: if(movement_committed && !world_valid) begin
                        // Capture one coherent committed pose and its geometry.
                        centre_x<=$signed(vehicle_x)+21'sd3072;
                        centre_y<=$signed(vehicle_y)+21'sd3072;
                        body_extent<=rotation_extent(vehicle_tilt);
                        tilt_cos<=rotation_cos(vehicle_tilt);
                        tilt_sin<=rotation_sin(vehicle_tilt);
                        tilt_abs_sin<=rotation_sin(vehicle_tilt)<0 ? -rotation_sin(vehicle_tilt) : rotation_sin(vehicle_tilt);
                        pig_found<=candidate_pig_found;
                        pig_local_x<=candidate_pig_x; pig_local_y<=candidate_pig_y;
                        saved_width<=world_width; saved_height<=world_height;
                        saved_hazards<=hazard_rects; saved_hazard_count<=hazard_count;
                        if(map_level) begin
                            goal_left<=$signed({1'b0,flag_x,8'b0});
                            goal_right<=$signed({1'b0,flag_x,8'b0})+21'sd4096;
                            goal_top<=$signed({1'b0,flag_y,8'b0})-21'sd2560;
                            goal_bottom<=$signed({1'b0,flag_y,8'b0})+21'sd3584;
                        end else begin
                            goal_left<=$signed({1'b0,goal_rect[7:0],8'b0});
                            goal_top<=$signed({1'b0,goal_rect[15:8],8'b0});
                            goal_right<=$signed({1'b0,goal_rect[7:0],8'b0})+$signed({1'b0,goal_rect[23:16],8'b0});
                            goal_bottom<=$signed({1'b0,goal_rect[15:8],8'b0})+$signed({1'b0,goal_rect[31:24],8'b0});
                        end
                        hazard_hit<=0; hazard_index<=0; phase<=POSE;
                    end
                    POSE: begin
                        pig_x<=centre_x+pig_offset_x; pig_y<=centre_y+pig_offset_y;
                        vehicle_left<=centre_x-body_extent; vehicle_right<=centre_x+body_extent;
                        vehicle_top<=centre_y-body_extent; vehicle_bottom<=centre_y+body_extent;
                        phase<=GOAL;
                    end
                    GOAL: begin
                        goal_hit<=pig_found && pig_x>=goal_left && pig_x<goal_right &&
                                  pig_y>=goal_top && pig_y<goal_bottom;
                        out_of_bounds<=vehicle_left>=$signed({1'b0,saved_width,8'b0}) || vehicle_right<=0 ||
                                       vehicle_top>=$signed({1'b0,saved_height,8'b0}) || vehicle_bottom<=0;
                        phase<=HAZARD_SETUP;
                    end
                    HAZARD_SETUP: begin
                        if(hazard_index>=saved_hazard_count || hazard_index>=2) phase<=FINISH;
                        else begin
                            // Rectangle centres and broad-phase comparisons end
                            // here before either projection multiplier starts.
                            hazard_dx<=hx_fp+$signed({1'b0,hw,7'b0})-centre_x;
                            hazard_dy<=hy_fp+$signed({1'b0,hh,7'b0})-centre_y;
                            hazard_w<=hw; hazard_h<=hh;
                            hazard_aabb<=hw!=0 && hh!=0 && vehicle_right>hx_fp && vehicle_left<hr_fp &&
                                         vehicle_bottom>hy_fp && vehicle_top<hb_fp;
                            phase<=X_PRODUCTS;
                        end
                    end
                    X_PRODUCTS: begin
                        product_a<=hazard_dx*tilt_cos;
                        product_b<=hazard_dy*tilt_sin;
                        extent_product_a<=$signed({1'b0,hazard_w})*tilt_cos;
                        extent_product_b<=$signed({1'b0,hazard_h})*tilt_abs_sin;
                        phase<=X_SUM_Y_PRODUCTS;
                    end
                    X_SUM_Y_PRODUCTS: begin
                        hazard_local_x<=$signed(product_a)+$signed(product_b);
                        hazard_extent_x<=27'sd786432+($signed(extent_product_a) <<< 7)+($signed(extent_product_b) <<< 7);
                        // Share the same products for the orthogonal axis.
                        product_a<=hazard_dx*tilt_sin;
                        product_b<=hazard_dy*tilt_cos;
                        extent_product_a<=$signed({1'b0,hazard_w})*tilt_abs_sin;
                        extent_product_b<=$signed({1'b0,hazard_h})*tilt_cos;
                        phase<=Y_SUM;
                    end
                    Y_SUM: begin
                        hazard_local_y<=-$signed(product_a)+$signed(product_b);
                        hazard_extent_y<=27'sd786432+($signed(extent_product_a) <<< 7)+($signed(extent_product_b) <<< 7);
                        phase<=HAZARD_CHECK;
                    end
                    HAZARD_CHECK: begin
                        // Four separating axes reject empty rotated-hull corners.
                        if(hazard_aabb && hazard_local_x>-hazard_extent_x && hazard_local_x<hazard_extent_x &&
                           hazard_local_y>-hazard_extent_y && hazard_local_y<hazard_extent_y) hazard_hit<=1;
                        hazard_index<=hazard_index+1'b1; phase<=HAZARD_SETUP;
                    end
                    FINISH: begin world_valid<=1; phase<=IDLE; end
                    default: phase<=IDLE;
                endcase
            end
        end
    end
endmodule
