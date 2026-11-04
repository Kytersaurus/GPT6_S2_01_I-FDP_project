// Owner: Role 4 - Marcus. Right OLED map and vehicle drawing with a following camera.
`timescale 1ns / 1ps
`include "game_defs.vh"
// The camera centres on the vehicle and stops at the world edges. The map view (the default)
// shows 64 by 43 screen pixels at 1.5x (about 43 by 29 world pixels) with 12 by 12 sprites;
// normal zoom-out shows 96 by 64 world pixels at 1.0x with 8 by 8 sprites, and overview shows
// 192 by 128 world pixels at 0.5x. In free look (SW4) the
// cursor position picks the camera instead, so the whole map can be explored without driving.
// Drawing order: background (map, or sky and terrain), hazards, goal, flag, TNT, vehicle,
// explosions, then the result border. Before launch the vehicle is drawn at the spawn point.
// Three coordinate sets per pixel: world pixels (terrain, map ROM), screen-scale pixels
// (sprites; a world position p is at 3p/2 at 1.5x, with an even camera so this is exact) and
// half-world texture units (stone, flag and explosions). Output has one clock of latency:
// map_x/map_y go to the level_map draw port and the class returns with the registered pixel.
module right_renderer #(
    parameter USE_PIXEL_INDEX = 1
) (
    input wire clk,
    input wire [12:0] pixel_index,
    input wire [6:0] in_x,
    input wire [5:0] in_y,
    input wire zoomed_out,
    input wire overview,
    // Free look: the camera follows the mouse cursor (0..95, 0..63) across the whole world.
    input wire free_look,
    input wire [6:0] cursor_x, cursor_y,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] build_facing_left,
    input tri0 [8:0] build_facing_down,
    input tri0 [8:0] active_fans,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    // 20-bit Q12.8 positions, ready for wider physics; today's 16-bit values are sign-extended.
    // vehicle_x/y are the rendered sprite position. camera_x/y are separate so
    // callers can choose whether the camera follows raw or filtered motion.
    input wire signed [19:0] vehicle_x, vehicle_y,
    input wire signed [19:0] camera_x, camera_y,
    input wire signed [`LP_TILT_BITS-1:0] vehicle_tilt,
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
    input tri0 [1:0] death_phase,
    input wire signed [`LP_COORD_BITS-1:0] death_x, death_y,
    // Visual-only debris from a high-fall impact. The cells are animated
    // deterministically in this renderer; they are not separate physics bodies.
    input tri0 [8:0] scatter_mask,
    input tri0 signed [`LP_COORD_BITS-1:0] scatter_x, scatter_y,
    input tri0 [5:0] scatter_phase,
    input wire launch_flash,
    input wire anim_phase,
    input wire map_level,
    input wire map_id,  // 0 Cave Arch (has the moon), 1 Cave Flight
    input wire [9:0] world_width, world_height,
    input wire [9:0] flag_x, flag_y,
    input wire [9:0] star_box_x, star_box_y,
    input wire star_box_collected,
    input tri0 [7:0] run_seconds,
    output reg signed [10:0] map_x, map_y,
    input wire [2:0] map_class,
    output reg [15:0] pixel_data
);
    `include "part_sprites.vh"
    `include "ui_font.vh"
    `include "rotation_geometry.vh"
    wire [5:0] raw_pi_y = ({12'd0, pixel_index} * 25'd2731) >> 18;
    wire [6:0] raw_pi_x = pixel_index - (raw_pi_y << 6) - (raw_pi_y << 5);
    wire [6:0] x = USE_PIXEL_INDEX ? raw_pi_x : in_x;
    wire [5:0] y = USE_PIXEL_INDEX ? raw_pi_y : in_y;

    wire before_launch = (game_state == `LP_BUILD || game_state == `LP_GUIDE);
    // Vehicle (or spawn) top-left in whole world pixels.
    wire signed [19:0] origin_x = before_launch ? spawn_x : vehicle_x;
    wire signed [19:0] origin_y = before_launch ? spawn_y : vehicle_y;
    wire signed [19:0] camera_origin_x = before_launch ? spawn_x : camera_x;
    wire signed [19:0] camera_origin_y = before_launch ? spawn_y : camera_y;
    wire signed [11:0] vx = camera_origin_x[19:8];
    wire signed [11:0] vy = camera_origin_y[19:8];

    // Stage 0: camera and the world position under this pixel.
    integer sx, sy, view_w, view_h, world_view_w, world_view_h, cam_x, cam_y, max_x, max_y;
    integer next_fx, next_fy, next_wx, next_wy, next_tx, next_ty;
    always @* begin
        sx = x; sy = y;
        view_w = overview ? 192 : (zoomed_out ? 96 : 64);
        view_h = overview ? 128 : (zoomed_out ? 64 : 43);
        // Camera limits are in world pixels. At the default 1.5x scale each
        // screen pixel covers 2/3 of a world pixel, so using the raw screen
        // dimensions here would leave the start ground and map edges clipped.
        if (overview) begin
            world_view_w = 192; world_view_h = 128;
        end else if (zoomed_out) begin
            world_view_w = 96; world_view_h = 64;
        end else begin
            world_view_w = 43; world_view_h = 29;
        end
        // Signed limits: a camera left of or above the world must clamp to zero, not wrap.
        max_x = world_width;
        max_y = world_height;
        max_x = max_x - world_view_w;
        max_y = max_y - world_view_h;
        if (free_look) begin
            // Scale the cursor to the camera range: 86/8192 ~ 1/95 and 130/8192 ~ 1/63.
            cam_x = (cursor_x * max_x * 86) >>> 13;
            cam_y = (cursor_y * max_y * 130) >>> 13;
        end else begin
            cam_x = vx + 12 - (world_view_w >>> 1);
            cam_y = vy + 12 - (world_view_h >>> 1);
        end
        if (cam_x > max_x) cam_x = max_x;
        if (cam_y > max_y) cam_y = max_y;
        if (cam_x < 0) cam_x = 0;
        if (cam_y < 0) cam_y = 0;
        if (overview) begin
            // Half scale uses shifts and the existing sprite data, with no new image ROM.
            cam_x=cam_x & ~1; cam_y=cam_y & ~1;
            next_wx=cam_x+2*sx; next_wy=cam_y+2*sy;
            next_fx=(cam_x >>> 1)+sx; next_fy=(cam_y >>> 1)+sy;
            next_tx=2*next_wx; next_ty=2*next_wy;
        end else if (zoomed_out) begin
            next_wx = cam_x + sx;                  next_wy = cam_y + sy;
            next_fx = next_wx;                     next_fy = next_wy;
            next_tx = 2*next_wx;                   next_ty = 2*next_wy;
        end else begin
            // An even camera keeps 3*cam/2 whole; screen steps of 2/3 world pixel.
            cam_x = cam_x & ~1;                    cam_y = cam_y & ~1;
            next_wx = cam_x + (2*sx)/3;            next_wy = cam_y + (2*sy)/3;
            next_fx = (3*cam_x)/2 + sx;            next_fy = (3*cam_y)/2 + sy;
            next_tx = 2*cam_x + (4*sx)/3;          next_ty = 2*cam_y + (4*sy)/3;
        end
        map_x = next_wx;
        map_y = next_wy;
    end

    // Stage 1: registered beside the map read.
    reg [6:0] px, py;
    reg signed [11:0] fx, fy, wx, wy, tex_x, tex_y;
    reg zoomed_out_q, overview_q;
    reg signed [`LP_TILT_BITS-1:0] tilt_q;
    always @(posedge clk) begin
        px <= sx; py <= sy; zoomed_out_q <= zoomed_out; overview_q <= overview;
        fx <= next_fx; fy <= next_fy; wx <= next_wx; wy <= next_wy; tex_x <= next_tx; tex_y <= next_ty;
        tilt_q <= before_launch ? 0 : sanitize_tilt(vehicle_tilt);
    end

    // One text line is shared by the launch "GO!" and the ending card titles:
    // they are never on screen together, and each text_on call costs real logic.
    wire in_result_state = (game_state == `LP_SUCCESS || game_state == `LP_FAIL);
    reg [127:0] banner_text;
    reg [6:0] banner_left, banner_top;
    always @* begin
        if (game_state == `LP_SUCCESS) begin
            banner_text = "LEVEL CLEAR!    "; banner_left = 7'd12; banner_top = 7'd11;
        end else if (game_state == `LP_FAIL) begin
            banner_text = "GAME OVER       "; banner_left = 7'd21; banner_top = 7'd14;
        end else begin
            banner_text = "GO!             "; banner_left = 7'd39; banner_top = 7'd1;
        end
    end
    wire banner_lit = text_on(banner_text, banner_left, banner_top, px, py);
    // Ending card layout: the clear card keeps its pig below the row of stars.
    wire [6:0] card_pig_top = (game_state == `LP_SUCCESS) ? 7'd36 : 7'd28;
    wire [1:0] stars_earned = 2'd1 + (star_box_collected ? 2'd1 : 2'd0) + ((run_seconds < 8'd20) ? 2'd1 : 2'd0);
    reg [6:0] card_star_x;
    reg card_star_earned;

    // World position to screen-scale position for sprites.
    function integer scaled;
        input integer world;
        input zoomed_out_now;
        begin scaled = zoomed_out_now ? world : (3*world) >>> 1; end
    endfunction
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
                // 3-tone turf shading on 2-world-pixel cells (exact 3x3 screen blocks at 1.5x zoom).
                `LP_MAP_GRASS: begin
                    case ((((fine_x >>> 2) * 3) ^ ((fine_y >>> 2) * 5)) & 3)
                        0, 1: map_colour = fine_y[1] ? 16'h4d86 : 16'h5e27;
                        2:    map_colour = 16'h3504;
                        default: map_colour = 16'h4d86;
                    endcase
                end
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
                    // Centre in half-world units: Cave Arch world pixel (280, 78) in the night sky above the start hill.
                    mx = fine_x - 560; my = fine_y - 156;
                    if (!map_id && mx*mx + my*my <= 324) map_colour = (mx*mx + (my+6)*(my+6) <= 16) ? 16'hc65a : 16'he75e;
                end
            endcase
        end
    endfunction

    wire goal_pixel;
    integer index, rx, ry, rw, rh, rel_x, rel_y, cell_px, cell_col, cell_row, cell_index, tx, ty, dx, dy, distance, radius;
    integer scatter_dx, scatter_dy, scatter_world_x, scatter_world_y;
    integer scatter_size, scatter_local_x, scatter_local_y;
    integer scatter_base_x, scatter_base_y;
    reg [2:0] part;
    reg [31:0] rectangle;
    // Half-pixel centred coordinates keep opposite corners symmetric. Only
    // nearby pixels enter these small products, preventing outside-world
    // positions from aliasing into the sprite after narrowing.
    reg signed [8:0] rotation_dx2, rotation_dy2;
    reg signed [9:0] rotation_c, rotation_s;
    reg signed [19:0] rotation_x_sum, rotation_y_sum;

    square u_goal_box (
        .x(wx[6:0]), .y(wy[6:0]), .pos_x(goal_rect[6:0]), .pos_y(goal_rect[14:8]),
        .width_x(goal_rect[22:16]), .length_y(goal_rect[30:24]), .is_in_square(goal_pixel)
    );

    always @* begin
        rx = 0; ry = 0; rw = 0; rh = 0; rel_x = 0; rel_y = 0; cell_px = 0; cell_col = 0; cell_row = 0;
        cell_index = 0; tx = 0; ty = 0; dx = 0; dy = 0; distance = 0; radius = 0; part = 0; rectangle = 0;
        scatter_dx = 0; scatter_dy = 0; scatter_world_x = 0; scatter_world_y = 0;
        scatter_size = 0; scatter_local_x = 0; scatter_local_y = 0;
        scatter_base_x = 0; scatter_base_y = 0;
        rotation_dx2=0; rotation_dy2=0; rotation_c=0; rotation_s=0;
        rotation_x_sum=0; rotation_y_sum=0;
        if (map_level) pixel_data = map_colour(map_class, tex_x, tex_y);
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
                (((wx-rx) & 3) == 1 || ((wx-rx) & 3) == 2 || wy-ry >= (rh >>> 1))) pixel_data = 16'hc618;
        end
        if (goal_pixel && wx < 128 && wy < 128) pixel_data = 16'h0320;
        // Finish flag on map levels, in half-world units from its top-left: a 3-wide orange
        // wooden pole 28 tall (lit left edge, dark right edge) and a 20 by 16 checkered cloth
        // with a dark border and 4-unit (2 world pixel) squares.
        if (map_level) begin
            dx = tex_x - 2*flag_x; dy = tex_y - 2*flag_y;
            if (dx >= 0 && dx < 3 && dy >= 0 && dy < 28)
                pixel_data = (dx == 0) ? 16'hfd8c : (dx == 1) ? 16'hec05 : 16'haa82;
            else if (dx >= 3 && dx < 23 && dy >= 1 && dy < 17) begin
                if (dx == 3 || dx == 22 || dy == 1 || dy == 16) pixel_data = 16'h3186;
                else pixel_data = ((((dx-3) >>> 2) ^ ((dy-1) >>> 2)) & 1) ? 16'h0000 : 16'hffff;
            end
            // Star box: 12 by 12 close, 8 by 8 normal/overview, the same sizes as TNT.
            tx = star_box_x; ty = star_box_y;
            if (`LP_STAR_BOX_ENABLED && !star_box_collected)
                pixel_data = (zoomed_out_q || overview_q) ? star_sprite(wx - tx, wy - ty, pixel_data)
                                          : star_sprite12(fx - scaled(tx, 1'b0), fy - scaled(ty, 1'b0), pixel_data);
        end
        // TNT: 12 by 12 close, 8 by 8 normal/overview (overview naturally samples it smaller).
        for (index = 0; index < `LP_MAX_TNT; index = index + 1) begin
            tx = tnt_positions[index*`LP_TNT_ENTRY_BITS +: `LP_TNT_COORD_BITS];
            ty = tnt_positions[index*`LP_TNT_ENTRY_BITS+`LP_TNT_COORD_BITS +: `LP_TNT_COORD_BITS];
            if (index < tnt_count && tnt_intact[index])
                pixel_data = (zoomed_out_q || overview_q) ? tnt_sprite(wx - tx, wy - ty, pixel_data)
                                          : tnt_sprite12(fx - scaled(tx, 1'b0), fy - scaled(ty, 1'b0), pixel_data);
        end
        // Vehicle: three cells of 12, 8, or 4 screen pixels, using existing sprites.
        cell_px = overview_q ? 4 : (zoomed_out_q ? 8 : 12);
        rel_x = fx - (overview_q ? (vx >>> 1) : scaled(vx, zoomed_out_q));
        rel_y = fy - (overview_q ? (vy >>> 1) : scaled(vy, zoomed_out_q));
        // Inverse-map every destination pixel through the body's rotation.
        // Zero tilt retains the original sprite lookup exactly at every zoom.
        if (tilt_q != 0) begin
            if (rel_x >= -cell_px && rel_x < 4*cell_px &&
                rel_y >= -cell_px && rel_y < 4*cell_px) begin
                rotation_dx2=2*rel_x+1-3*cell_px;
                rotation_dy2=2*rel_y+1-3*cell_px;
                rotation_c=rotation_cos(tilt_q); rotation_s=rotation_sin(tilt_q);
                rotation_x_sum=rotation_c*rotation_dx2+rotation_s*rotation_dy2;
                rotation_y_sum=-rotation_s*rotation_dx2+rotation_c*rotation_dy2;
                rel_x=(rotation_x_sum+3*cell_px*256) >>> 9;
                rel_y=(rotation_y_sum+3*cell_px*256) >>> 9;
            end else begin rel_x=-1; rel_y=-1; end
        end
        if (rel_x >= 0 && rel_x < 3*cell_px && rel_y >= 0 && rel_y < 3*cell_px) begin
            cell_col = (rel_x >= 2*cell_px) ? 2 : (rel_x >= cell_px) ? 1 : 0;
            cell_row = (rel_y >= 2*cell_px) ? 2 : (rel_y >= cell_px) ? 1 : 0;
            rel_x = rel_x - cell_col*cell_px;
            rel_y = rel_y - cell_row*cell_px;
            cell_index = cell_row*3 + cell_col;
            part = build_grid >> (cell_index*3);
            if (overview_q) begin
                rel_x=2*rel_x;
                rel_y=2*rel_y;
                if (frame_intact_mask[cell_index]) pixel_data = part_sprite(`LP_PART_FRAME, rel_x, rel_y, 1'b0, pixel_data);
                if (intact_mask[cell_index]) pixel_data = part_sprite_mounted(part, rel_x, rel_y, 8, build_facing_left[cell_index], build_facing_down[cell_index], frame_intact_mask, cell_index, anim_phase, pixel_data);
            end else if (zoomed_out_q) begin
                if (frame_intact_mask[cell_index]) pixel_data = part_sprite(`LP_PART_FRAME, rel_x, rel_y, 1'b0, pixel_data);
                if (intact_mask[cell_index]) pixel_data = part_sprite_mounted(part, rel_x, rel_y, 8, build_facing_left[cell_index], build_facing_down[cell_index], frame_intact_mask, cell_index, anim_phase, pixel_data);
            end else begin
                if (frame_intact_mask[cell_index]) pixel_data = part_sprite12(`LP_PART_FRAME, rel_x, rel_y, 1'b0, pixel_data);
                if (intact_mask[cell_index]) pixel_data = part_sprite_mounted(part, rel_x, rel_y, 12, build_facing_left[cell_index], build_facing_down[cell_index], frame_intact_mask, cell_index, anim_phase, pixel_data);
            end
        end
        // High-fall debris: show a compact three-piece scatter burst while the
        // damaged cells leave the vehicle. This is deliberately a small sprite
        // overlay, not nine independent moving bodies.
        if (scatter_phase != 0 && (|scatter_mask)) begin
            // Compare in world pixels. The existing wx/wy pipeline already
            // accounts for 0.5x, 1x and 1.5x display sampling.
            scatter_size = 6;
            scatter_base_x = $signed(scatter_x) >>> 8;
            scatter_base_y = $signed(scatter_y) >>> 8;
            for (index = 0; index < 3; index = index + 1) begin
                case (index)
                    0: begin scatter_dx = -(scatter_phase >>> 1); scatter_dy = -(scatter_phase >>> 2); end
                    1: begin scatter_dx =  (scatter_phase >>> 1); scatter_dy =  (scatter_phase >>> 2); end
                    default: begin scatter_dx = 0; scatter_dy = scatter_phase; end
                endcase
                scatter_world_x = scatter_base_x + scatter_dx;
                scatter_world_y = scatter_base_y + scatter_dy;
                scatter_local_x = wx - scatter_world_x;
                scatter_local_y = wy - scatter_world_y;
                if (scatter_local_x >= 0 && scatter_local_x < scatter_size &&
                    scatter_local_y >= 0 && scatter_local_y < scatter_size) begin
                    if (scatter_local_x == 0 || scatter_local_y == 0 ||
                        scatter_local_x == scatter_size-1 || scatter_local_y == scatter_size-1)
                        pixel_data = 16'h630c;
                    else if (index != 1)
                        pixel_data = 16'hfd20;
                    else
                        pixel_data = 16'hc618;
                end
            end
        end
        // Explosions grow over three phases: yellow flash, orange fireball, grey smoke.
        for (index = 0; index < `LP_MAX_TNT; index = index + 1) begin
            dx = tex_x - 2*tnt_positions[index*`LP_TNT_ENTRY_BITS +: `LP_TNT_COORD_BITS] - `LP_TNT_PIXELS;
            dy = tex_y - 2*tnt_positions[index*`LP_TNT_ENTRY_BITS+`LP_TNT_COORD_BITS +: `LP_TNT_COORD_BITS] - `LP_TNT_PIXELS;
            distance = dx*dx + dy*dy;
            radius = 2*(2 + 3*blast_phase[index*2 +: 2]);
            if (index < tnt_count && blast_phase[index*2 +: 2] != 0 && distance <= radius*radius) case (blast_phase[index*2 +: 2])
                2'd1: pixel_data = 16'hffe0;
                2'd2: pixel_data = (distance <= 36) ? 16'hffe0 : 16'hfd20;
                default: pixel_data = 16'h8410;
            endcase
        end
        if (launch_flash && game_state==`LP_RUN && px>=34 && px<62 && py<10) begin
            pixel_data=16'h04b4;
            if (banner_lit) pixel_data=16'hffff;
        end
        // Ending card: a midnight navy panel over the map, 80 by 48 and centred.
        // Clear shows the title, three stars and a pig; crash shows a dizzy pig.
        // The chip is nearly full, so each drawing helper is used only once and
        // its position is chosen first. Each call is its own copy of the logic.
        if (in_result_state && px >= 8 && px < 88 && py >= 8 && py < 56) begin
            if (px == 8 || px == 87 || py == 8 || py == 55) pixel_data = 16'h4a69; // Card edge
            else pixel_data = 16'h0869; // Midnight navy
            if (banner_lit) pixel_data = (game_state == `LP_SUCCESS) ? 16'hffe0 : 16'hf800;
            if (game_state == `LP_SUCCESS) begin
                // Three stars share one lookup: pick the star this column falls in.
                if (px >= 66) begin
                    card_star_x = px - 7'd66;
                    card_star_earned = (stars_earned == 2'd3);
                end else if (px >= 42) begin
                    card_star_x = px - 7'd42;
                    card_star_earned = (stars_earned >= 2'd2);
                end else begin
                    card_star_x = px - 7'd18;
                    card_star_earned = 1'b1;
                end
                if (px >= 18) pixel_data = gold_star12(card_star_earned ? 16'hfee0 : 16'h39e7, card_star_x, py - 20, pixel_data);
            end
            pixel_data = part_sprite16(`LP_PART_PIG, px - 40, py - card_pig_top, 1'b0, pixel_data);
            // Dizzy eyes: a small black and white check over each 2 by 2 eye.
            if (game_state == `LP_FAIL && (py == 34 || py == 35) &&
                (px == 44 || px == 45 || px == 50 || px == 51))
                pixel_data = ((px + py) & 1) ? 16'h0000 : 16'hffff;
        end
        // World-space pig burst stays visible after the pig's intact bit clears.
        tx=wx-($signed(death_x) >>> 8); ty=wy-($signed(death_y) >>> 8);
        if (death_phase!=0) begin
            distance=(tx<0 ? -tx : tx)+(ty<0 ? -ty : ty);
            if (death_phase==1 && distance<=4) pixel_data=16'hffe0;
            else if (death_phase==2 && distance<=7 && (tx==0 || ty==0 || tx==ty || tx==-ty)) pixel_data=16'hf800;
            else if (death_phase==3 && distance>=7 && distance<=9 && (tx==6 || tx==-6 || ty==6 || ty==-6)) pixel_data=16'hb800;
        end
        if (px == 0 || px == 95 || py == 0 || py == 63) begin
            if (game_state == `LP_SUCCESS) pixel_data = 16'h07e0;
            else if (game_state == `LP_FAIL) pixel_data = 16'hf800;
        end
    end
endmodule
