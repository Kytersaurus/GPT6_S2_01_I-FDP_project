// Owner: Role 4 - Marcus. Right OLED map and vehicle drawing with a following camera.
`timescale 1ns / 1ps
`include "game_defs.vh"
// The camera centres on the vehicle and stops at the world edges. Zoomed in (the default)
// shows 48 by 32 world pixels at 2x with 16 by 16 sprites; zoomed out shows 96 by 64 at 1x
// with 8 by 8 sprites, which is the whole world on levels 1 and 2. In free look (SW4) the
// cursor position picks the camera instead, so the whole map can be explored without driving.
// Drawing order: background (map, or sky and terrain), hazards, goal, flag, TNT, vehicle,
// explosions, then the result border. Before launch the vehicle is drawn at the spawn point.
// Positions inside the drawing use "fine" half-world-pixel units, so zoomed-in art has
// full screen resolution. Output has one clock of latency: map_x/map_y go to the level_map
// draw port and its class returns with the registered pixel on the next clock.
module right_renderer (
    input wire clk,
    input wire [12:0] pixel_index,
    input wire zoomed_out,
    // Free look: the camera follows the mouse cursor (0..95, 0..63) across the whole world.
    input wire free_look,
    input wire [6:0] cursor_x, cursor_y,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    // 20-bit Q12.8 positions, ready for wider physics; today's 16-bit values are sign-extended.
    input wire signed [19:0] vehicle_x, vehicle_y,
    input wire signed [19:0] spawn_x, spawn_y,
    input wire [2:0] terrain_count,
    input wire [127:0] terrain_rects,
    input wire [31:0] goal_rect,
    input wire [2:0] tnt_count,
    input wire [`LP_TNT_BITS-1:0] tnt_positions,
    input wire [`LP_MAX_TNT-1:0] tnt_intact,
    input wire [1:0] hazard_count,
    input wire [`LP_HAZARD_BITS-1:0] hazard_rects,
    input wire [2*`LP_MAX_TNT-1:0] blast_phase,
    input wire anim_phase,
    input wire map_level,
    input wire [9:0] world_width, world_height,
    input wire [9:0] flag_x, flag_y,
    output reg signed [10:0] map_x, map_y,
    input wire [2:0] map_class,
    output reg [15:0] pixel_data
);
    `include "part_sprites.vh"

    wire before_launch = (game_state == `LP_BUILD || game_state == `LP_GUIDE);
    // Vehicle (or spawn) top-left in whole world pixels.
    wire signed [19:0] origin_x = before_launch ? spawn_x : vehicle_x;
    wire signed [19:0] origin_y = before_launch ? spawn_y : vehicle_y;
    wire signed [11:0] vx = origin_x[19:8];
    wire signed [11:0] vy = origin_y[19:8];

    // Stage 0: camera and the world position under this pixel.
    integer sx, sy, view_w, view_h, cam_x, cam_y, max_x, max_y, next_fx, next_fy;
    always @* begin
        sx = pixel_index % 96;
        sy = pixel_index / 96;
        view_w = zoomed_out ? 96 : 48;
        view_h = zoomed_out ? 64 : 32;
        // Signed limits: a camera left of or above the world must clamp to zero, not wrap.
        max_x = world_width;
        max_y = world_height;
        max_x = max_x - view_w;
        max_y = max_y - view_h;
        if (free_look) begin
            // Scale the cursor to the camera range: 86/8192 ~ 1/95 and 130/8192 ~ 1/63.
            cam_x = (cursor_x * max_x * 86) >>> 13;
            cam_y = (cursor_y * max_y * 130) >>> 13;
        end else begin
            cam_x = vx + 12 - view_w/2;
            cam_y = vy + 12 - view_h/2;
        end
        if (cam_x > max_x) cam_x = max_x;
        if (cam_y > max_y) cam_y = max_y;
        if (cam_x < 0) cam_x = 0;
        if (cam_y < 0) cam_y = 0;
        next_fx = 2*cam_x + (zoomed_out ? 2*sx : sx);
        next_fy = 2*cam_y + (zoomed_out ? 2*sy : sy);
        map_x = next_fx >>> 1;
        map_y = next_fy >>> 1;
    end

    // Stage 1: registered beside the map read.
    reg [6:0] px, py;
    reg signed [11:0] fx, fy;
    reg zoomed_out_q;
    always @(posedge clk) begin
        px <= sx; py <= sy; fx <= next_fx; fy <= next_fy; zoomed_out_q <= zoomed_out;
    end

    // Staggered stones with mortar and a lit top-left edge in three shades.
    function [15:0] stone;
        input integer fine_x, fine_y;
        input [15:0] mortar, light, tone_a, tone_b, tone_c;
        integer row, shifted, lx, ly, shade;
        begin
            row = fine_y >>> 3;
            shifted = fine_x + ((row * 5) & 15);
            lx = shifted & 15;
            ly = fine_y & 7;
            shade = ((shifted >>> 4) ^ (row << 1) ^ (shifted >>> 6) ^ row) & 3;
            if (lx == 0 || ly == 0 || (lx == 1 && ly == 1)) stone = mortar;
            else if (lx == 1 || ly == 1) stone = light;
            else if (shade == 0) stone = tone_a;
            else if (shade == 2) stone = tone_c;
            else stone = tone_b;
        end
    endfunction

    function [15:0] map_colour;
        input [2:0] map_cell;
        input integer fine_x, fine_y;
        integer band, mx, my;
        begin
            case (map_cell)
                `LP_MAP_CAVE: map_colour = stone(fine_x, fine_y, 16'h08a2, 16'h2a88, 16'h1985, 16'h21c6, 16'h2227);
                `LP_MAP_ROCK: map_colour = stone(fine_x, fine_y, 16'h1988, 16'h6c97, 16'h3af0, 16'h4352, 16'h4bd4);
                `LP_MAP_GRASS: map_colour = ((fine_x ^ fine_y) & 3) == 0 ? 16'h2bc3 : 16'h4d86;
                `LP_MAP_ROAD: map_colour = ((fine_x*3 ^ fine_y*5) & 7) == 0 ? 16'h4a89 : 16'h3a28;
                `LP_MAP_DARK: map_colour = 16'h1082;
                default: begin
                    // Night sky lightening towards the horizon, with the moon seen through the arch.
                    band = fine_y >>> 6;
                    case (band)
                        0: map_colour = 16'h322d;
                        1: map_colour = 16'h3a8f;
                        2: map_colour = 16'h4af1;
                        3: map_colour = 16'h5b94;
                        4: map_colour = 16'h6c57;
                        5: map_colour = 16'h8d1a;
                        default: map_colour = 16'ha5fd;
                    endcase
                    mx = fine_x - 464; my = fine_y - 332;
                    if (mx*mx + my*my <= 324) map_colour = (mx*mx + (my+6)*(my+6) <= 16) ? 16'hc65a : 16'he75e;
                end
            endcase
        end
    endfunction

    wire goal_pixel;
    integer wx, wy, index, rx, ry, rw, rh, rel_x, rel_y, cell_index, tx, ty, dx, dy, distance, radius;
    reg [2:0] part;
    reg [31:0] rectangle;

    square u_goal_box (
        .x(wx[6:0]), .y(wy[6:0]), .pos_x(goal_rect[6:0]), .pos_y(goal_rect[14:8]),
        .width_x(goal_rect[22:16]), .length_y(goal_rect[30:24]), .is_in_square(goal_pixel)
    );

    always @* begin
        wx = fx >>> 1;
        wy = fy >>> 1;
        rx = 0; ry = 0; rw = 0; rh = 0; rel_x = 0; rel_y = 0; cell_index = 0;
        tx = 0; ty = 0; dx = 0; dy = 0; distance = 0; radius = 0; part = 0; rectangle = 0;
        if (map_level) pixel_data = map_colour(map_class, fx, fy);
        else begin
            pixel_data = 16'h0010;
            for (index = 0; index < 4; index = index + 1) begin
                rectangle = terrain_rects >> (index*32);
                rx = rectangle[7:0]; ry = rectangle[15:8];
                rw = rectangle[23:16]; rh = rectangle[31:24];
                if (index < terrain_count && wx >= rx && wx < rx+rw && wy >= ry && wy < ry+rh) pixel_data = 16'h8320;
            end
        end
        // Spikes: four-pixel teeth, pointed in their outer columns.
        for (index = 0; index < `LP_MAX_HAZARDS; index = index + 1) begin
            rectangle = hazard_rects >> (index*32);
            rx = rectangle[7:0]; ry = rectangle[15:8];
            rw = rectangle[23:16]; rh = rectangle[31:24];
            if (index < hazard_count && wx >= rx && wx < rx+rw && wy >= ry && wy < ry+rh &&
                ((wx-rx)%4 == 1 || (wx-rx)%4 == 2 || wy-ry >= rh/2)) pixel_data = 16'hc618;
        end
        if (goal_pixel && wx < 128 && wy < 128) pixel_data = 16'h0320;
        // Finish flag on map levels: a 6 by 12 pole with a checkered cloth.
        if (map_level) begin
            dx = fx - 2*flag_x; dy = fy - 2*flag_y;
            if (dx >= 0 && dx < 2 && dy >= 0 && dy < 24) pixel_data = 16'hc618;
            else if (dx >= 2 && dx < 12 && dy >= 0 && dy < 10)
                pixel_data = (((dx >>> 1) ^ (dy >>> 1)) & 1) ? 16'h0000 : 16'hffff;
        end
        // TNT: 16 by 16 when zoomed in, 8 by 8 when zoomed out.
        for (index = 0; index < `LP_MAX_TNT; index = index + 1) begin
            tx = tnt_positions[index*16 +: 8];
            ty = tnt_positions[index*16+8 +: 8];
            if (index < tnt_count && tnt_intact[index])
                pixel_data = zoomed_out_q ? tnt_sprite(wx - tx, wy - ty, pixel_data)
                                    : tnt_sprite16(fx - 2*tx, fy - 2*ty, pixel_data);
        end
        // Vehicle: 48 by 48 fine units; 16 by 16 sprites zoomed in, 8 by 8 zoomed out.
        rel_x = fx - 2*vx;
        rel_y = fy - 2*vy;
        if (rel_x >= 0 && rel_x < 48 && rel_y >= 0 && rel_y < 48) begin
            cell_index = (rel_y/16)*3 + rel_x/16;
            part = build_grid >> (cell_index*3);
            if (zoomed_out_q) begin
                if (frame_intact_mask[cell_index])
                    pixel_data = part_sprite(`LP_PART_FRAME, (rel_x%16)/2, (rel_y%16)/2, 1'b0, pixel_data);
                if (intact_mask[cell_index])
                    pixel_data = part_sprite(part, (rel_x%16)/2, (rel_y%16)/2, anim_phase, pixel_data);
            end else begin
                if (frame_intact_mask[cell_index])
                    pixel_data = part_sprite16(`LP_PART_FRAME, rel_x%16, rel_y%16, 1'b0, pixel_data);
                if (intact_mask[cell_index])
                    pixel_data = part_sprite16(part, rel_x%16, rel_y%16, anim_phase, pixel_data);
            end
        end
        // Explosions grow over three phases: yellow flash, orange fireball, grey smoke.
        for (index = 0; index < `LP_MAX_TNT; index = index + 1) begin
            dx = fx - 2*tnt_positions[index*16 +: 8] - `LP_TNT_PIXELS;
            dy = fy - 2*tnt_positions[index*16+8 +: 8] - `LP_TNT_PIXELS;
            distance = dx*dx + dy*dy;
            radius = 2*(2 + 3*blast_phase[index*2 +: 2]);
            if (index < tnt_count && blast_phase[index*2 +: 2] != 0 && distance <= radius*radius) case (blast_phase[index*2 +: 2])
                2'd1: pixel_data = 16'hffe0;
                2'd2: pixel_data = (distance <= 36) ? 16'hffe0 : 16'hfd20;
                default: pixel_data = 16'h8410;
            endcase
        end
        if (px == 0 || px == 95 || py == 0 || py == 63) begin
            if (game_state == `LP_SUCCESS) pixel_data = 16'h07e0;
            else if (game_state == `LP_FAIL) pixel_data = 16'hf800;
        end
    end
endmodule
