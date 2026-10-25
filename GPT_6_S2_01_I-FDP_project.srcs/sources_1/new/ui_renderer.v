// Owner: Role 1 - Kaushal; shared left-screen layout with Role 4 - Marcus.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ui_renderer (
    input wire [12:0] pixel_index,
    input wire [15:0] base_pixel,
    input wire [2:0] game_state, feedback_code,
    input wire [1:0] diary_page,
    input wire [`LP_LEVEL_BITS-1:0] level_index,
    input wire build_valid, engine_enabled, boost_active,
    input wire fan_available, fan_on, rocket_available, rocket_ready,
    input wire [6:0] cursor_x, cursor_y,
    output reg [15:0] pixel_data
);
    `include "ui_font.vh"
    `include "part_sprites.vh"
    wire [6:0] x=pixel_index%96, y=pixel_index/96;
    reg [127:0] line;
    integer text_left, text_top, row, button_left, button_right;
    reg [1:0] tile;
    reg tile_hover;
    reg text_visible, button, enabled;
    reg [15:0] ink;
    always @* begin
        pixel_data=base_pixel; line="                ";
        text_left=0; text_top=0; row=0; button_left=0; button_right=0;
        text_visible=0; button=0; enabled=1; ink=16'hffff; tile=0; tile_hover=0;
        if (game_state==`LP_GUIDE) begin
            pixel_data=16'h0841;
            text_visible=1; text_left=2;
            if (y<9) begin row=0; text_top=1; ink=16'h07ff; end
            else if (y<18) begin row=1; text_top=10; end
            else if (y<27) begin row=2; text_top=19; end
            else if (y<36) begin row=3; text_top=28; end
            else if (y<45) begin row=4; text_top=37; end
            else begin row=5; text_top=46; end
            case (diary_page)
                0: case (row)
                    0: case (level_index)
                        0: line="DIARY L1 1/3    ";
                        1: line="DIARY L2 1/3    ";
                        2: line="DIARY L3 1/3    ";
                        default: line="DIARY L4 1/3    ";
                    endcase
                    1: line="GET PIG TO FLAG ";
                    2: line="DRAG PARTS IN   ";
                    3: line="RIGHT CLICK OUT ";
                    4: line="SW0 POWERS CAR  ";
                    5: line="U BACK C NEXT   ";
                endcase
                1: case (row)
                    0: line="PART RULES 2/3  ";
                    1: line="PIG IN A FRAME  ";
                    2: line="ENGINE IN FRAME ";
                    3: line="WHEELS UP/DOWN  ";
                    4: line="BALLOONS ABOVE  ";
                    5: line="CLICK TO POP    ";
                endcase
                default: case (row)
                    0: line="LEVEL HINT 3/3  ";
                    1: line=(level_index>=2) ? "MAP TEST ONLY   " : level_index ? "PROTECT ENGINE  " : "TRY MIDDLE ROW  ";
                    2: line=(level_index>=2) ? "PHYSICS PENDING " : level_index ? "TNT BREAKS PARTS" : "PIG IN CENTRE   ";
                    3: line=(level_index>=2) ? "SW3 ZOOM        " : "ENGINE AT REAR  ";
                    4: line=(level_index>=2) ? "SW4 LOOK AROUND " : level_index ? "KEEP PIG SAFE   " : "WHEELS AT EDGES ";
                    5: line="RETRY RESTORES  ";
                endcase
            endcase
        end
        // Compact BUILD toolbar keeps the full 48 by 48 construction grid.
        if (game_state==`LP_BUILD && y>=55) begin
            pixel_data=16'h0841; text_visible=1; text_top=56;
            if (x<18) begin
                button=1; button_left=0; button_right=17; text_left=2;
                line="GO              "; enabled=build_valid;
            end else if (x>=64 && x<80) begin
                button=1; button_left=64; button_right=79; text_left=69; line="?               ";
            end else if (x>=20 && x<63) begin
                text_left=20; ink=feedback_code>=3 ? 16'hf800 : (build_valid ? 16'h07e0 : 16'hffe0);
                case (feedback_code)
                    `LP_FEEDBACK_PLACED: line="PLACED          ";
                    `LP_FEEDBACK_REMOVED: line="REMOVED         ";
                    `LP_FEEDBACK_NO_STOCK: line="STOCK 0         ";
                    `LP_FEEDBACK_FRAME_ABOVE, `LP_FEEDBACK_FRAME_BELOW, `LP_FEEDBACK_NEED_FRAME: line="FRAME?          ";
                    `LP_FEEDBACK_OCCUPIED: line="TAKEN           ";
                    default: line=build_valid ? "READY           " : "CHECK           ";
                endcase
            end else begin pixel_data=base_pixel; text_visible=0; end
        end
        if (game_state==`LP_BUILD && y<3) pixel_data=x<54 ? 16'h04b4 : 16'h2945;
        if (game_state==`LP_RUN && x>=54 && y>=3 && y<54) begin
            pixel_data=16'h0841;
            if (x>=56 && x<95) begin
                if (y>=4 && y<16) begin
                    button=1; button_left=56; button_right=94; text_top=7; text_left=70;
                    line=engine_enabled ? "ON              " : "OFF             ";
                end else if (y>=18 && y<30) begin
                    button=1; button_left=56; button_right=94; text_top=21; text_left=58;
                    line=fan_available ? (fan_on ? "FAN ON          " : "FAN -           ") : "FAN -           ";
                    enabled=fan_available;
                end else if (y>=32 && y<42) begin
                    button=1; button_left=56; button_right=94; text_top=33; text_left=58;
                    line="BOOST           "; ink=boost_active ? 16'hffe0 : 16'hffff;
                end else if (y>=44 && y<54) begin
                    button=1; button_left=56; button_right=94; text_top=45; text_left=58;
                    line="ROCKET          "; enabled=rocket_available && rocket_ready;
                end
            end
        end
        if (game_state==`LP_RUN && y>=55) begin
            pixel_data=16'h0841; text_visible=1; text_left=2; text_top=56; line="SW0 POWER       "; ink=16'h07ff;
        end
        if ((game_state==`LP_GUIDE || game_state==`LP_SUCCESS || game_state==`LP_FAIL) && y>=55) begin
            pixel_data=16'h0841; text_visible=0; text_top=56;
            if (x<28) begin
                button=1; button_left=0; button_right=27; text_left=2;
                line=game_state==`LP_GUIDE ? "BACK            " : "TRY             ";
            end else if (x>=32 && x<60) begin
                button=1; button_left=32; button_right=59; text_left=34;
                line=game_state==`LP_GUIDE ? "PREV            " : (game_state==`LP_SUCCESS ? "NEXT            " : "EDIT            ");
                enabled=game_state!=`LP_GUIDE || diary_page>0;
            end else if (x>=64) begin
                button=1; button_left=64; button_right=95; text_left=65;
                line=game_state==`LP_GUIDE ? "NEXT            " : "DIARY           ";
                enabled=game_state!=`LP_GUIDE || diary_page<2;
            end
        end
        if (button) begin
            pixel_data=enabled ? 16'h18e5 : 16'h18c3;
            if (enabled && cursor_x>=button_left && cursor_x<=button_right &&
                cursor_y>=text_top-3 && cursor_y<text_top+11) pixel_data=16'h0351;
            if (x==button_left || x==button_right || y==text_top-1 || y==text_top+7)
                pixel_data=enabled ? 16'h04b4 : 16'h4208;
            if (!enabled) ink=16'h7bef;
            text_visible=1;
        end
        if (game_state==`LP_RUN && x>=56 && x<95 && y>=4 && y<16)
            pixel_data=part_sprite(`LP_PART_ENGINE,x-58,y-6,1'b0,pixel_data);
        if (text_visible && text_on(line,text_left,text_top,x,y)) pixel_data=ink;
        // Replace the old level-cycle label with a folded-map icon.
        if (game_state==`LP_BUILD && x>=`LP_LEVEL_BUTTON_X && x<`LP_LEVEL_BUTTON_X+`LP_LEVEL_BUTTON_W && y>=55) begin
            pixel_data=16'h18e5;
            if (x==`LP_LEVEL_BUTTON_X || x==`LP_LEVEL_BUTTON_X+`LP_LEVEL_BUTTON_W-1 || y==55 || y==63) pixel_data=16'h04b4;
            if (x>=83 && x<=92 && y>=57 && y<=61) begin
                pixel_data=16'hcf36;
                if (x==86 || x==89) pixel_data=16'h6b4d;
                if ((x==84 && y==60) || (x==85 && y==59) || (x==90 && y==58)) pixel_data=16'h04b4;
            end
        end
        if (game_state==`LP_LEVEL_SELECT) begin
            pixel_data=16'h0841;
            if (text_on("SELECT LEVEL    ",12,2,x,y)) pixel_data=16'h07ff;
            // Two columns, two rows. The selected map has a green outline.
            if (((x>=2 && x<46) || (x>=50 && x<94)) &&
                ((y>=12 && y<32) || (y>=34 && y<54))) begin
                tile={y>=34,x>=50};
                button_left=tile[0] ? 50 : 2; button_right=button_left+43;
                text_top=tile[1] ? 34 : 12;
                tile_hover=cursor_x>=button_left && cursor_x<=button_right &&
                           cursor_y>=text_top && cursor_y<text_top+20;
                pixel_data=tile_hover ? 16'h0351 : 16'h18e5;
                if (x==button_left || x==button_right || y==text_top || y==text_top+19)
                    pixel_data=(tile==level_index) ? 16'h07e0 : (tile>=2 ? 16'hfd20 : 16'h04b4);
                case (tile)
                    0: line="TRACK           ";
                    1: line="TNT PIT         ";
                    2: line="ARCH            ";
                    3: line="FLIGHT          ";
                endcase
                if (text_on(line,button_left+1,text_top+2,x,y)) pixel_data=16'hffff;
                case (tile)
                    0: line="1               ";
                    1: line="2               ";
                    2: line="3 WIP           ";
                    3: line="4 WIP           ";
                endcase
                if (text_on(line,button_left+1,text_top+11,x,y)) pixel_data=tile>=2 ? 16'hfd20 : 16'h07ff;
            end
            if (y>=55) begin
                if (x<28) begin
                    pixel_data=16'h18e5;
                    if (x==0 || x==27 || y==55 || y==63) pixel_data=16'h04b4;
                    if (text_on("BACK            ",2,56,x,y)) pixel_data=16'hffff;
                end else if (text_on("PICK A MAP      ",32,56,x,y)) pixel_data=16'h7bef;
            end
        end
        // The pointer is also visible on diary/result controls.
        if ((x==cursor_x && y+2>=cursor_y && y<=cursor_y+2) ||
            (y==cursor_y && x+2>=cursor_x && x<=cursor_x+2)) pixel_data=16'hffff;
    end
endmodule
